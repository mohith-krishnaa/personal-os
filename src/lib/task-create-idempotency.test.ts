import test from 'node:test'
import assert from 'node:assert/strict'
import {
  findExistingTaskRequest,
  hashClientRequestPayload,
  insertTaskRequest,
  normalizeClientRequestId,
} from './task-create-idempotency'

const REQUEST_ID = '91000000-0000-4000-8000-000000000099'
const PAYLOAD = { kind: 'TASK', title: 'Retry-safe task', priority: 'MEDIUM' }
const HASH = hashClientRequestPayload(PAYLOAD)

function taskRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'task-1',
    user_id: 'owner-1',
    title: 'Retry-safe task',
    client_request_id: REQUEST_ID,
    client_request_hash: HASH,
    ...overrides,
  }
}

function createSupabase(plans: Array<{ action: 'select' | 'upsert'; data: unknown; error: unknown | null }>) {
  const pending = [...plans]
  const calls: Array<{ action: string; values?: Record<string, unknown>; options?: unknown; filters: Array<[string, string]> }> = []
  const supabase = {
    from(table: string) {
      assert.equal(table, 'tasks')
      const call = { action: 'select', filters: [] as Array<[string, string]>, values: undefined as Record<string, unknown> | undefined, options: undefined as unknown }
      calls.push(call)
      const query = {
        select() { return query },
        eq(column: string, value: string) { call.filters.push([column, value]); return query },
        upsert(values: Record<string, unknown>, options: unknown) {
          call.action = 'upsert'
          call.values = values
          call.options = options
          return query
        },
        maybeSingle: async () => {
          const plan = pending.shift()
          assert.ok(plan, 'unexpected database query')
          assert.equal(plan.action, call.action)
          return { data: plan.data, error: plan.error }
        },
      }
      return query
    },
  } as any
  return { supabase, calls }
}

test('normalizes valid UUID request IDs and rejects malformed values', () => {
  assert.equal(normalizeClientRequestId('  ' + REQUEST_ID.toUpperCase() + '  '), REQUEST_ID)
  assert.throws(() => normalizeClientRequestId('not-a-uuid'), /valid client request ID/)
})

test('hashes equivalent payload objects independent of property order', () => {
  assert.equal(
    hashClientRequestPayload({ title: 'Task', nested: { b: 2, a: 1 } }),
    hashClientRequestPayload({ nested: { a: 1, b: 2 }, title: 'Task' }),
  )
})

test('returns a newly inserted task without exposing request metadata', async () => {
  const { supabase, calls } = createSupabase([
    { action: 'upsert', data: taskRow(), error: null },
  ])

  const result = await insertTaskRequest(supabase, 'owner-1', REQUEST_ID, HASH, { title: 'Retry-safe task' })

  assert.equal(result.id, 'task-1')
  assert.equal('client_request_hash' in result, false)
  assert.equal('client_request_id' in result, false)
  assert.deepEqual(calls[0].options, { onConflict: 'user_id,client_request_id', ignoreDuplicates: true })
  assert.equal(calls[0].values?.client_request_hash, HASH)
})

test('returns the existing task for a same-payload retry without inserting again', async () => {
  const { supabase, calls } = createSupabase([
    { action: 'select', data: taskRow(), error: null },
  ])

  const result = await findExistingTaskRequest(supabase, 'owner-1', REQUEST_ID, HASH)

  assert.equal(result?.id, 'task-1')
  assert.equal(calls.length, 1)
  assert.deepEqual(calls[0].filters, [['user_id', 'owner-1'], ['client_request_id', REQUEST_ID]])
})

test('rejects reuse of a request ID with a different payload hash', async () => {
  const { supabase, calls } = createSupabase([
    { action: 'select', data: taskRow({ client_request_hash: 'f'.repeat(64) }), error: null },
  ])

  await assert.rejects(
    () => findExistingTaskRequest(supabase, 'owner-1', REQUEST_ID, HASH),
    /already been used with different task details/,
  )
  assert.equal(calls.length, 1)
})

test('resolves a concurrent conflict by reading the committed winning task', async () => {
  const { supabase, calls } = createSupabase([
    { action: 'upsert', data: null, error: null },
    { action: 'select', data: taskRow(), error: null },
  ])

  const result = await insertTaskRequest(supabase, 'owner-1', REQUEST_ID, HASH, { title: 'Retry-safe task' })

  assert.equal(result.id, 'task-1')
  assert.equal(calls.length, 2)
  assert.equal(calls[0].action, 'upsert')
  assert.deepEqual(calls[1].filters, [['user_id', 'owner-1'], ['client_request_id', REQUEST_ID]])
})

test('does not claim success when a conflict cannot be resolved to a visible row', async () => {
  const { supabase } = createSupabase([
    { action: 'upsert', data: null, error: null },
    { action: 'select', data: null, error: null },
  ])

  await assert.rejects(
    () => insertTaskRequest(supabase, 'owner-1', REQUEST_ID, HASH, { title: 'Retry-safe task' }),
    /could not be confirmed/,
  )
})

test('propagates database errors instead of converting them to successful retries', async () => {
  const databaseError = { code: '42501', message: 'permission denied' }
  const { supabase } = createSupabase([
    { action: 'upsert', data: null, error: databaseError },
  ])

  await assert.rejects(() => insertTaskRequest(supabase, 'owner-1', REQUEST_ID, HASH, { title: 'Retry-safe task' }), error => error === databaseError)
})
