import { createHash } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Task } from '@/types/task'

type TaskRequestRow = Record<string, unknown> & {
  client_request_id: string
  client_request_hash: string | null
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function normalizeClientRequestId(value: string) {
  const normalized = value.trim().toLowerCase()
  if (!UUID_PATTERN.test(normalized)) {
    throw new Error('A valid client request ID is required.')
  }
  return normalized
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize)
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>
    return Object.fromEntries(
      Object.keys(record).sort().map(key => [key, canonicalize(record[key])]),
    )
  }
  return value
}

export function hashClientRequestPayload(payload: unknown) {
  const serialized = JSON.stringify(canonicalize(payload))
  if (serialized === undefined) throw new Error('Task creation payload cannot be serialized.')
  return createHash('sha256').update(serialized).digest('hex')
}

function toTask(row: TaskRequestRow, expectedHash: string): Task {
  if (row.client_request_hash !== expectedHash) {
    throw new Error('This creation request ID has already been used with different task details.')
  }
  const { client_request_id: _requestId, client_request_hash: _requestHash, ...task } = row
  return task as unknown as Task
}

export async function findExistingTaskRequest(
  supabase: SupabaseClient,
  userId: string,
  requestId: string,
  requestHash: string,
): Promise<Task | null> {
  const normalizedRequestId = normalizeClientRequestId(requestId)
  const { data, error } = await supabase
    .from('tasks')
    .select('*')
    .eq('user_id', userId)
    .eq('client_request_id', normalizedRequestId)
    .maybeSingle()

  if (error) throw error
  return data ? toTask(data as TaskRequestRow, requestHash) : null
}

/**
 * INSERT ... ON CONFLICT DO NOTHING is atomic under concurrent requests.
 * If another request wins the unique key, read and validate the winning row.
 */
export async function insertTaskRequest(
  supabase: SupabaseClient,
  userId: string,
  requestId: string,
  requestHash: string,
  values: Record<string, unknown>,
): Promise<Task> {
  const normalizedRequestId = normalizeClientRequestId(requestId)
  const { data, error } = await supabase
    .from('tasks')
    .upsert({
      ...values,
      user_id: userId,
      client_request_id: normalizedRequestId,
      client_request_hash: requestHash,
    }, {
      onConflict: 'user_id,client_request_id',
      ignoreDuplicates: true,
    })
    .select('*')
    .maybeSingle()

  if (error) throw error
  if (data) return toTask(data as TaskRequestRow, requestHash)

  const existing = await findExistingTaskRequest(supabase, userId, normalizedRequestId, requestHash)
  if (!existing) {
    throw new Error('Task creation could not be confirmed. Retry with the same request ID.')
  }
  return existing
}
