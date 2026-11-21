export type PendingClientRequest = {
  fingerprint: string
  fingerprintHash: string | null
  id: string
} | null

export type ClientRequestStorage = {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

type PersistedRequest = {
  fingerprintHash: string
  id: string
  status: 'pending' | 'completed'
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function getClientRequestStorage(): ClientRequestStorage | null {
  try {
    const storage = globalThis.sessionStorage
    return storage && typeof storage.getItem === 'function' && typeof storage.setItem === 'function'
      ? storage
      : null
  } catch {
    return null
  }
}

async function hashFingerprint(fingerprint: string): Promise<string | null> {
  try {
    const digest = await globalThis.crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(fingerprint),
    )
    return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('')
  } catch {
    // Storage persistence is an enhancement. The in-memory request ID remains
    // usable when Web Crypto is unavailable or blocked.
    return null
  }
}

function readPersistedRequests(storage: ClientRequestStorage, key: string): PersistedRequest[] {
  try {
    const raw = storage.getItem(key)
    if (!raw) return []
    const parsed = JSON.parse(raw) as { version?: unknown; requests?: unknown }
    if (parsed.version !== 1 || !Array.isArray(parsed.requests)) return []

    return parsed.requests.filter((value): value is PersistedRequest => {
      if (!value || typeof value !== 'object') return false
      const entry = value as Record<string, unknown>
      return typeof entry.fingerprintHash === 'string'
        && /^[0-9a-f]{64}$/.test(entry.fingerprintHash)
        && typeof entry.id === 'string'
        && UUID_PATTERN.test(entry.id)
        && (entry.status === 'pending' || entry.status === 'completed')
    })
  } catch {
    return []
  }
}

function writePersistedRequests(storage: ClientRequestStorage, key: string, requests: PersistedRequest[]) {
  try {
    storage.setItem(key, JSON.stringify({ version: 1, requests }))
  } catch {
    // Do not block task creation when browser storage is unavailable or full.
  }
}

/**
 * Reuse one request ID for the same payload, including after a component
 * remount or page reload in the same tab. Only a SHA-256 fingerprint and the
 * UUID are persisted; task text and other payload fields are never stored.
 */
export async function getClientRequestState<T>(
  current: PendingClientRequest,
  payload: T,
  createId: () => string,
  storage: ClientRequestStorage | null = null,
  storageKey?: string,
): Promise<Exclude<PendingClientRequest, null>> {
  const fingerprint = JSON.stringify(payload)
  if (fingerprint === undefined) {
    throw new Error('Task creation payload cannot be serialized.')
  }
  if (current?.fingerprint === fingerprint) return current

  const fingerprintHash = await hashFingerprint(fingerprint)
  if (storage && storageKey && fingerprintHash) {
    const requests = readPersistedRequests(storage, storageKey)
    const existing = requests.find(entry =>
      entry.fingerprintHash === fingerprintHash && entry.status === 'pending',
    )
    if (existing) {
      return { fingerprint, fingerprintHash, id: existing.id }
    }

    const pending = requests.filter(entry => entry.status === 'pending')
    const next = { fingerprint, fingerprintHash, id: createId() }
    if (UUID_PATTERN.test(next.id)) {
      pending.push({ fingerprintHash, id: next.id, status: 'pending' })
      writePersistedRequests(storage, storageKey, pending)
    }
    return next
  }

  return { fingerprint, fingerprintHash, id: createId() }
}

/** Mark a successful request complete so an identical future task gets a new ID. */
export function completeClientRequestState(
  request: Exclude<PendingClientRequest, null>,
  storage: ClientRequestStorage | null,
  storageKey: string,
) {
  if (!storage || !request.fingerprintHash) return

  const requests = readPersistedRequests(storage, storageKey)
  const entry = requests.find(item =>
    item.fingerprintHash === request.fingerprintHash && item.id === request.id,
  )
  if (!entry) return

  entry.status = 'completed'
  writePersistedRequests(storage, storageKey, requests)
}
