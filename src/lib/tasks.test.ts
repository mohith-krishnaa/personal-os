import test from 'node:test'
import assert from 'node:assert/strict'
import { listTasksForUser } from './task-queries'
import { assertTaskOrganizationLinks, resolveTaskOrganizationLinks } from './task-relationships'

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


function createRelationshipSupabase(
  responses: Array<{ table: string; data: unknown; error: unknown | null }>,
) {
  const calls: Array<{ table: string; columns?: string; filters: Array<[string, string]> }> = []
  const pending = [...responses]
  const supabase = {
    from(table: string) {
      const call = { table, filters: [] as Array<[string, string]>, columns: undefined as string | undefined }
      calls.push(call)
      const response = pending.shift()
      assert.ok(response, `unexpected query for ${table}`)
      assert.equal(response.table, table)
      const query = {
        select(columns: string) {
          call.columns = columns
          return this
        },
        eq(column: string, value: string) {
          call.filters.push([column, value])
          return this
        },
        maybeSingle() {
          return Promise.resolve({ data: response.data, error: response.error })
        },
      }
      return query
    },
  } as any
  return { supabase, calls }
}

test('task link preflight verifies parent and project ownership for the same owner', async () => {
  const { supabase, calls } = createRelationshipSupabase([
    { table: 'tasks', data: { id: 'parent-1', user_id: 'owner-1', project_id: 'project-1' }, error: null },
    { table: 'projects', data: { id: 'project-1' }, error: null },
  ])

  await assertTaskOrganizationLinks(supabase, 'owner-1', {
    projectId: 'project-1',
    parentTaskId: 'parent-1',
  })

  assert.deepEqual(calls, [
    { table: 'tasks', columns: 'id,user_id,project_id', filters: [['id', 'parent-1'], ['user_id', 'owner-1']] },
    { table: 'projects', columns: 'id', filters: [['id', 'project-1'], ['user_id', 'owner-1']] },
  ])
})

test('task link preflight rejects a parent not owned by the caller', async () => {
  const { supabase, calls } = createRelationshipSupabase([
    { table: 'tasks', data: null, error: null },
  ])

  await assert.rejects(
    () => assertTaskOrganizationLinks(supabase, 'owner-1', { parentTaskId: 'foreign-parent' }),
    /Parent task not found/,
  )
  assert.equal(calls.length, 1)
})

test('task link preflight rejects a parent in a different project', async () => {
  const { supabase, calls } = createRelationshipSupabase([
    { table: 'tasks', data: { id: 'parent-1', user_id: 'owner-1', project_id: 'project-1' }, error: null },
  ])

  await assert.rejects(
    () => assertTaskOrganizationLinks(supabase, 'owner-1', {
      projectId: 'project-2',
      parentTaskId: 'parent-1',
    }),
    /same project as its parent/,
  )
  assert.equal(calls.length, 1)
})

test('task link preflight rejects a project not owned by the caller', async () => {
  const { supabase, calls } = createRelationshipSupabase([
    { table: 'projects', data: null, error: null },
  ])

  await assert.rejects(
    () => assertTaskOrganizationLinks(supabase, 'owner-1', { projectId: 'foreign-project' }),
    /Project not found/,
  )
  assert.deepEqual(calls[0].filters, [['id', 'foreign-project'], ['user_id', 'owner-1']])
})

test('task link preflight rejects direct self-parenting before database access', async () => {
  const { supabase, calls } = createRelationshipSupabase([])

  await assert.rejects(
    () => assertTaskOrganizationLinks(supabase, 'owner-1', {
      parentTaskId: 'task-1',
      taskId: 'task-1',
    }),
    /cannot be its own parent/,
  )
  assert.equal(calls.length, 0)
})

test('task link preflight rejects a missing owner before database access', async () => {
  const { supabase, calls } = createRelationshipSupabase([])

  await assert.rejects(
    () => assertTaskOrganizationLinks(supabase, '', { projectId: 'project-1' }),
    /Unauthorized/,
  )
  assert.equal(calls.length, 0)
})


test('partial task relationship updates preserve the omitted existing link', () => {
  const links = resolveTaskOrganizationLinks(
    { project_id: 'project-1', parent_task_id: 'parent-1' },
    { parent_task_id: 'parent-2' },
  )

  assert.deepEqual(links, {
    projectId: 'project-1',
    parentTaskId: 'parent-2',
  })
})

test('explicit null clears a task relationship without clearing the omitted link', () => {
  const links = resolveTaskOrganizationLinks(
    { project_id: 'project-1', parent_task_id: 'parent-1' },
    { parent_task_id: null },
  )

  assert.deepEqual(links, {
    projectId: 'project-1',
    parentTaskId: null,
  })
})
