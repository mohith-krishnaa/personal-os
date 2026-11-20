export type PendingClientRequest = {
  fingerprint: string
  id: string
} | null

/**
 * Keep one request ID for retries of the same form payload. A changed payload
 * receives a new key so an old failed request cannot alias a new task.
 */
export function getClientRequestState<T>(
  current: PendingClientRequest,
  payload: T,
  createId: () => string,
): Exclude<PendingClientRequest, null> {
  const fingerprint = JSON.stringify(payload)
  if (current?.fingerprint === fingerprint) return current
  return { fingerprint, id: createId() }
}
