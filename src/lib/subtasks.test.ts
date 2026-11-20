import test from 'node:test'
import assert from 'node:assert/strict'
import { createSubtask, listSubtasks } from './subtasks'
import { afterSubtaskCreated, afterSubtaskListLoadFailed } from './subtask-state'

const REQUEST_ID = '94000000-0000-4000-8000-000000000099'

function unreachableDatabase() {
  return { from: () => { throw new Error('database should not be reached') } } as any
}

function createLookupSupabase(responses: Array<{ table: string; data: unknown; error: unknown | null }>) {
  const pending = [...responses]
  const calls: string[] = []
  const supabase = {
    from(table: string) {
      calls.push(table)
      const response = pending.shift()
      assert.ok(response, `unexpected query for ${table}`)
      assert.equal(response.table, table)
      return {
        select() { return this },
        eq() { return this },
        single: async () => response,
        maybeSingle: async () => response,
      }
    },
  } as any
  return { supabase, calls }
}

function createSubtaskDatabase(projectStatus: string) {
  const requestFilters: Array<[string, string]> = []
  const parentFilters: Array<[string, string]> = []
  const projectFilters: Array<[string, string]> = []
  const inserts: Array<Record<string, unknown>> = []
  let taskReads = 0

  const supabase = {
    from(table: string) {
      if (table === 'tasks') {
        taskReads += 1
        if (taskReads === 1) {
          return {
            select(columns: string) {
              assert.equal(columns, '*')
              return this
            },
            eq(column: string, value: string) {
              requestFilters.push([column, value])
              return this
            },
            maybeSingle: async () => ({ data: null, error: null }),
          }
        }

        if (taskReads === 2) {
          return {
            select(columns: string) {
              assert.equal(columns, 'id,user_id,project_id')
              return this
            },
            eq(column: string, value: string) {
              parentFilters.push([column, value])
              return this
            },
            single: async () => ({
              data: { id: 'parent-1', user_id: 'owner-1', project_id: 'project-1' },
              error: null,
            }),
          }
        }

        return {
          upsert(values: Record<string, unknown>) {
            inserts.push(values)
            return {
              select() { return this },
              maybeSingle: async () => ({
                data: { id: 'subtask-1', ...values },
                error: null,
              }),
            }
          },
        }
      }

      if (table === 'projects') {
        return {
          select(columns: string) {
            assert.equal(columns, 'id,status')
            return this
          },
          eq(column: string, value: string) {
            projectFilters.push([column, value])
            return this
          },
          single: async () => ({
            data: { id: 'project-1', status: projectStatus },
            error: null,
          }),
        }
      }

      throw new Error(`Unexpected table: ${table}`)
    },
  } as any

  return { supabase, requestFilters, parentFilters, projectFilters, inserts }
}

test('rejects blank subtask titles before database access', async () => {
  await assert.rejects(
    () => createSubtask(unreachableDatabase(), 'user', 'parent', { client_request_id: REQUEST_ID, title: '   ' }),
    /Subtask title is required/,
  )
})

test('rejects overlong subtask titles before database access', async () => {
  await assert.rejects(
    () => createSubtask(unreachableDatabase(), 'user', 'parent', { client_request_id: REQUEST_ID, title: 'x'.repeat(241) }),
    /240 characters or fewer/,
  )
})

test('rejects a missing parent task id before database access', async () => {
  await assert.rejects(
    () => createSubtask(unreachableDatabase(), 'user', '', { client_request_id: REQUEST_ID, title: 'Valid title' }),
    /Parent task is required/,
  )
})

test('rejects non-positive estimated minutes before database access', async () => {
  for (const estimated_minutes of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    await assert.rejects(
      () => createSubtask(unreachableDatabase(), 'user', 'parent', { client_request_id: REQUEST_ID, title: 'Valid title', estimated_minutes }),
      /Estimated minutes must be greater than zero/,
    )
  }
})

test('creates a subtask only after owner-scoped ACTIVE-project preflight', async () => {
  const { supabase, requestFilters, parentFilters, projectFilters, inserts } = createSubtaskDatabase('ACTIVE')

  const result = await createSubtask(supabase, 'owner-1', 'parent-1', { client_request_id: REQUEST_ID, title: 'Child task' })

  assert.equal(result.id, 'subtask-1')
  assert.deepEqual(requestFilters, [['user_id', 'owner-1'], ['client_request_id', REQUEST_ID]])
  assert.deepEqual(parentFilters, [['id', 'parent-1'], ['user_id', 'owner-1']])
  assert.deepEqual(projectFilters, [['id', 'project-1'], ['user_id', 'owner-1']])
  assert.equal(inserts.length, 1)
  const { client_request_id, client_request_hash, ...insertedValues } = inserts[0]
  assert.equal(client_request_id, REQUEST_ID)
  assert.match(String(client_request_hash), /^[0-9a-f]{64}$/)
  assert.deepEqual(insertedValues, {
    user_id: 'owner-1',
    parent_task_id: 'parent-1',
    project_id: 'project-1',
    title: 'Child task',
    priority: 'MEDIUM',
    due_at: null,
    estimated_minutes: null,
  })
})

test('createSubtask preserves parent database authorization errors', async () => {
  const databaseError = { code: '42501', message: 'permission denied for table tasks' }
  const { supabase } = createLookupSupabase([
    { table: 'tasks', data: null, error: null },
    { table: 'tasks', data: null, error: databaseError },
  ])

  await assert.rejects(
    () => createSubtask(supabase, 'owner-1', 'parent-1', { client_request_id: REQUEST_ID, title: 'Child task' }),
    error => error instanceof Error && error.message === 'You are not authorized to access the requested task or project.' && (error as Error & { code?: string }).code === '42501',
  )
})

test('createSubtask preserves project database authorization errors', async () => {
  const databaseError = { code: '42501', message: 'permission denied for table projects' }
  const { supabase } = createLookupSupabase([
    { table: 'tasks', data: null, error: null },
    { table: 'tasks', data: { id: 'parent-1', user_id: 'owner-1', project_id: 'project-1' }, error: null },
    { table: 'projects', data: null, error: databaseError },
  ])

  await assert.rejects(
    () => createSubtask(supabase, 'owner-1', 'parent-1', { client_request_id: REQUEST_ID, title: 'Child task' }),
    error => error instanceof Error && error.message === 'You are not authorized to access the requested task or project.' && (error as Error & { code?: string }).code === '42501',
  )
})

test('createSubtask maps a PostgREST zero-row parent result to the owner-safe not-found message', async () => {
  const { supabase } = createLookupSupabase([
    { table: 'tasks', data: null, error: null },
    { table: 'tasks', data: null, error: { code: 'PGRST116', message: 'JSON object requested, no rows returned' } },
  ])

  await assert.rejects(
    () => createSubtask(supabase, 'owner-1', 'foreign-parent', { client_request_id: REQUEST_ID, title: 'Child task' }),
    /Parent task not found/,
  )
})

for (const status of ['COMPLETED', 'ARCHIVED']) {
  test(`rejects new subtasks under ${status} projects before task insertion`, async () => {
    const { supabase, projectFilters, inserts } = createSubtaskDatabase(status)

    await assert.rejects(
      () => createSubtask(supabase, 'owner-1', 'parent-1', { client_request_id: REQUEST_ID, title: 'Child task' }),
      /Tasks can only be linked to active projects/,
    )

    assert.deepEqual(projectFilters, [['id', 'project-1'], ['user_id', 'owner-1']])
    assert.equal(inserts.length, 0)
  })
}

test('rejects a project that differs from the parent project before insert', async () => {
  const { supabase, calls } = createLookupSupabase([
    { table: 'tasks', data: null, error: null },
    { table: 'tasks', data: { id: 'parent', user_id: 'user', project_id: 'parent-project' }, error: null },
  ])

  await assert.rejects(
    () => createSubtask(supabase, 'user', 'parent', { client_request_id: REQUEST_ID, title: 'Valid title', project_id: 'other-project' }),
    /same project as its parent/,
  )
  assert.deepEqual(calls, ['tasks', 'tasks'])
})

test('lists subtasks scoped to the requested owner and parent task', async () => {
  const parentFilters: Array<[string, string]> = []
  const childFilters: Array<[string, string]> = []
  const orderCalls: Array<[string, { ascending: boolean }]> = []
  const children = [{ id: 'child-1', user_id: 'owner-1', parent_task_id: 'parent-1', title: 'First child' }]
  let fromCalls = 0

  const supabase = {
    from(table: string) {
      assert.equal(table, 'tasks')
      fromCalls += 1
      if (fromCalls === 1) {
        const query = {
          select(columns: string) {
            assert.equal(columns, 'id,user_id,project_id')
            return this
          },
          eq(column: string, value: string) {
            parentFilters.push([column, value])
            return this
          },
          single: async () => ({
            data: { id: 'parent-1', user_id: 'owner-1', project_id: null },
            error: null,
          }),
        }
        return query
      }

      const query = {
        select(columns: string) {
          assert.equal(columns, '*')
          return this
        },
        eq(column: string, value: string) {
          childFilters.push([column, value])
          return this
        },
        order(column: string, options: { ascending: boolean }) {
          orderCalls.push([column, options])
          return orderCalls.length === 1 ? Promise.resolve({ data: children, error: null }) : this
        },
      }
      return query
    },
  } as any

  const result = await listSubtasks(supabase, 'owner-1', 'parent-1')

  assert.deepEqual(parentFilters, [['id', 'parent-1'], ['user_id', 'owner-1']])
  assert.deepEqual(childFilters, [['user_id', 'owner-1'], ['parent_task_id', 'parent-1']])
  assert.deepEqual(orderCalls, [['created_at', { ascending: true }]])
  assert.deepEqual(result, children)
})

test('listSubtasks preserves parent database authorization errors', async () => {
  const databaseError = { code: '42501', message: 'permission denied for table tasks' }
  const { supabase, calls } = createLookupSupabase([
    { table: 'tasks', data: null, error: databaseError },
  ])

  await assert.rejects(
    () => listSubtasks(supabase, 'owner-1', 'parent-1'),
    error => error instanceof Error && error.message === 'You are not authorized to access the requested task or project.' && (error as Error & { code?: string }).code === '42501',
  )
  assert.deepEqual(calls, ['tasks'])
})

test('does not list children when the parent does not belong to the requested owner', async () => {
  let fromCalls = 0
  const supabase = {
    from() {
      fromCalls += 1
      return {
        select() { return this },
        eq() { return this },
        single: async () => ({ data: null, error: { code: 'PGRST116', message: 'JSON object requested, no rows returned' } }),
      }
    },
  } as any

  await assert.rejects(() => listSubtasks(supabase, 'owner-1', 'foreign-parent'), /Parent task not found/)
  assert.equal(fromCalls, 1)
})


test('marks a previously incomplete subtask list for refresh after creation', () => {
  const pending = [{ id: 'pending-local' }]
  const created = { id: 'created' }

  assert.deepEqual(afterSubtaskCreated(pending, created, false), {
    items: [...pending, created],
    shouldReload: true,
  })
})

test('appends to a loaded subtask list without requiring another read', () => {
  const existing = [{ id: 'existing' }]
  const created = { id: 'created' }

  assert.deepEqual(afterSubtaskCreated(existing, created, true), {
    items: [...existing, created],
    shouldReload: false,
  })
})
 
test('marks a subtask list incomplete after a failed refresh and retries canonical loading after the next create', () => {
  const existing = [{ id: 'existing' }]
  const created = { id: 'created' }
  const failed = afterSubtaskListLoadFailed(existing)

  assert.deepEqual(failed, { items: existing, listLoaded: false })
  assert.deepEqual(afterSubtaskCreated(failed.items, created, failed.listLoaded), {
    items: [...existing, created],
    shouldReload: true,
  })
})
