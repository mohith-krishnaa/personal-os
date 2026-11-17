import test from 'node:test'
import assert from 'node:assert/strict'
import { listTasksForUser } from './task-queries'

test('listTasksForUser scopes reads to the owner and optional project while preserving task ordering', async () => {
  const filters: Array<[string, string]> = []
  const orderCalls: Array<[string, Record<string, unknown>]> = []
  const tasks = [{ id: 'task-1', user_id: 'owner-1', project_id: 'project-1', title: 'Owned task' }]
  const query = {
    eq(column: string, value: string) {
      filters.push([column, value])
      return this
    },
    order(column: string, options: Record<string, unknown>) {
      orderCalls.push([column, options])
      return orderCalls.length === 2
        ? Promise.resolve({ data: tasks, error: null })
        : this
    },
  }
  const supabase = {
    from(table: string) {
      assert.equal(table, 'tasks')
      return {
        select(columns: string) {
          assert.equal(columns, '*')
          return query
        },
      }
    },
  } as any

  const result = await listTasksForUser(supabase, 'owner-1', 'project-1')

  assert.deepEqual(filters, [
    ['user_id', 'owner-1'],
    ['project_id', 'project-1'],
  ])
  assert.deepEqual(orderCalls, [
    ['due_at', { ascending: true, nullsFirst: false }],
    ['created_at', { ascending: false }],
  ])
  assert.deepEqual(result, tasks)
})

test('listTasksForUser leaves project filtering optional while retaining owner filtering', async () => {
  const filters: Array<[string, string]> = []
  const query = {
    eq(column: string, value: string) {
      filters.push([column, value])
      return this
    },
    order() {
      return this
    },
    then(resolve: (value: { data: unknown[]; error: null }) => unknown) {
      return Promise.resolve({ data: [], error: null }).then(resolve)
    },
  }
  const supabase = {
    from() {
      return { select: () => query }
    },
  } as any

  await listTasksForUser(supabase, 'owner-1')

  assert.deepEqual(filters, [['user_id', 'owner-1']])
})

test('listTasksForUser rejects a missing owner before database access', async () => {
  let fromCalls = 0
  const supabase = {
    from() {
      fromCalls += 1
      throw new Error('database should not be reached')
    },
  } as any

  await assert.rejects(() => listTasksForUser(supabase, ''), /Unauthorized/)
  assert.equal(fromCalls, 0)
})
