import test from 'node:test'
import assert from 'node:assert/strict'
import { listTasksForUser } from './task-queries'
import { setTaskStatusForUser, updateTaskForUser, type UpdateTaskInput } from './tasks'
import { assertTaskOrganizationLinks, canCreateTaskInProject, isInactiveProjectAssignmentError, isNewProjectAssignment, resolveTaskOrganizationLinks } from './task-relationships'

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

test('task link preflight preserves parent database authorization errors', async () => {
  const databaseError = { code: '42501', message: 'permission denied for table tasks' }
  const { supabase } = createRelationshipSupabase([
    { table: 'tasks', data: null, error: databaseError },
  ])

  await assert.rejects(
    () => assertTaskOrganizationLinks(supabase, 'owner-1', { parentTaskId: 'parent-1' }),
    error => error instanceof Error && error.message === 'You are not authorized to access the requested task or project.' && (error as Error & { code?: string }).code === '42501',
  )
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

test('task link preflight preserves project database authorization errors', async () => {
  const databaseError = { code: '42501', message: 'permission denied for table projects' }
  const { supabase } = createRelationshipSupabase([
    { table: 'projects', data: null, error: databaseError },
  ])

  await assert.rejects(
    () => assertTaskOrganizationLinks(supabase, 'owner-1', { projectId: 'project-1' }),
    error => error instanceof Error && error.message === 'You are not authorized to access the requested task or project.' && (error as Error & { code?: string }).code === '42501',
  )
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


test('only ACTIVE projects accept new tasks', () => {
  assert.equal(canCreateTaskInProject('ACTIVE'), true)
  assert.equal(canCreateTaskInProject('COMPLETED'), false)
  assert.equal(canCreateTaskInProject('ARCHIVED'), false)
  assert.equal(canCreateTaskInProject(null), false)
})

test('new project assignment detection preserves unchanged or cleared legacy links', () => {
  assert.equal(isNewProjectAssignment('archived-project', 'archived-project'), false)
  assert.equal(isNewProjectAssignment('active-project', 'archived-project'), true)
  assert.equal(isNewProjectAssignment(null, 'active-project'), true)
  assert.equal(isNewProjectAssignment('archived-project', null), false)
  assert.equal(isNewProjectAssignment('archived-project', undefined), false)
})

test('inactive-project race handling only matches the dedicated database constraint', () => {
  assert.equal(isInactiveProjectAssignmentError({
    code: '23514',
    message: 'Tasks can only be linked to active projects.',
  }), true)
  assert.equal(isInactiveProjectAssignmentError({ code: '23514', message: 'Other check failed.' }), false)
  assert.equal(isInactiveProjectAssignmentError({ code: '42501', message: 'Tasks can only be linked to active projects.' }), false)
})

test('task link preflight accepts a new assignment to an ACTIVE project', async () => {
  const { supabase, calls } = createRelationshipSupabase([
    { table: 'projects', data: { id: 'project-1', status: 'ACTIVE' }, error: null },
  ])

  await assertTaskOrganizationLinks(supabase, 'owner-1', { projectId: 'project-1' }, { requireActiveProject: true })

  assert.deepEqual(calls, [
    { table: 'projects', columns: 'id,status', filters: [['id', 'project-1'], ['user_id', 'owner-1']] },
  ])
})

for (const status of ['COMPLETED', 'ARCHIVED']) {
  test(`task link preflight rejects new assignments to ${status} projects`, async () => {
    const { supabase, calls } = createRelationshipSupabase([
      { table: 'projects', data: { id: 'project-1', status }, error: null },
    ])

    await assert.rejects(
      () => assertTaskOrganizationLinks(supabase, 'owner-1', { projectId: 'project-1' }, { requireActiveProject: true }),
      /Tasks can only be linked to active projects/,
    )
    assert.equal(calls.length, 1)
  })
}

test('task link preflight preserves an existing archived-project relationship', async () => {
  const { supabase, calls } = createRelationshipSupabase([
    { table: 'projects', data: { id: 'archived-project' }, error: null },
  ])

  await assertTaskOrganizationLinks(supabase, 'owner-1', { projectId: 'archived-project' })

  assert.deepEqual(calls, [
    { table: 'projects', columns: 'id', filters: [['id', 'archived-project'], ['user_id', 'owner-1']] },
  ])
})


type UpdateTaskPlan = {
  table: string
  action: 'select' | 'update' | 'insert'
  data?: unknown
  error?: unknown
}

function createUpdateTaskSupabase(plans: UpdateTaskPlan[]) {
  const calls: Array<{
    table: string
    action?: 'select' | 'update' | 'insert'
    columns?: string
    payload?: Record<string, unknown>
    filters: Array<[string, string]>
  }> = []

  function finish(call: (typeof calls)[number]) {
    const plan = plans.shift()
    assert.ok(plan, `unexpected ${call.action} query for ${call.table}`)
    assert.equal(plan.table, call.table)
    assert.equal(plan.action, call.action)
    return { data: plan.data ?? null, error: ('error' in plan ? plan.error : null) ?? null }
  }

  const supabase = {
    from(table: string) {
      const call: (typeof calls)[number] = { table, filters: [] }
      calls.push(call)
      return {
        select(columns: string) {
          if (!call.action) call.action = 'select'
          call.columns = columns
          return this
        },
        update(payload: Record<string, unknown>) {
          call.action = 'update'
          call.payload = payload
          return this
        },
        insert(payload: Record<string, unknown>) {
          call.action = 'insert'
          call.payload = payload
          return Promise.resolve(finish(call))
        },
        eq(column: string, value: string) {
          call.filters.push([column, value])
          return this
        },
        single() {
          return Promise.resolve(finish(call))
        },
        maybeSingle() {
          return Promise.resolve(finish(call))
        },
      }
    },
  } as any

  return { supabase, calls, remainingPlans: () => plans.length }
}

function validTaskUpdate(): UpdateTaskInput {
  return {
    title: '  Updated task  ',
    priority: 'HIGH',
    estimated_minutes: 45,
    due_at: null,
    scheduled_start: null,
    scheduled_end: null,
  }
}

test('setTaskStatusForUser retries a missing recurrence occurrence when completion was already committed', async () => {
  const task = {
    id: 'task-recurring', user_id: 'owner-1', project_id: null, parent_task_id: null,
    recurrence_parent_id: 'task-recurring', recurrence_rule: { frequency: 'DAILY', interval: 1 },
    recurrence_until: null, due_at: '2099-01-01T09:00:00.000Z', scheduled_start: null,
    scheduled_end: null, title: 'Recurring', description: null, status: 'COMPLETED',
    priority: 'MEDIUM', estimated_minutes: null, actual_minutes: null,
    completed_at: '2099-01-01T10:00:00.000Z', created_at: '2098-01-01T00:00:00.000Z',
    updated_at: '2099-01-01T10:00:00.000Z',
  }
  const calls: Array<{ table: string; action?: string; payload?: Record<string, unknown>; filters: Array<[string, string]> }> = []
  const plans = [
    { table: 'tasks', action: 'select', data: task },
    { table: 'tasks', action: 'update', data: null },
    { table: 'tasks', action: 'select', data: task },
    { table: 'tasks', action: 'insert', data: { ...task, id: 'occurrence-1', due_at: '2099-01-02T09:00:00.000Z' } },
  ]
  const supabase = {
    from(table: string) {
      const call = { table, filters: [] as Array<[string, string]>, action: undefined as string | undefined, payload: undefined as Record<string, unknown> | undefined }
      calls.push(call)
      return {
        select() { if (!call.action) call.action = 'select'; return this },
        update(payload: Record<string, unknown>) { call.action = 'update'; call.payload = payload; return this },
        insert(payload: Record<string, unknown>) { call.action = 'insert'; call.payload = payload; return this },
        eq(column: string, value: string) { call.filters.push([column, value]); return this },
        neq() { return this },
        single() { const plan = plans.shift(); assert.ok(plan); assert.equal(plan.table, table); assert.equal(plan.action, call.action); return Promise.resolve({ data: plan.data ?? null, error: ('error' in plan ? plan.error : null) ?? null }) },
        maybeSingle() { const plan = plans.shift(); assert.ok(plan); assert.equal(plan.table, table); assert.equal(plan.action, call.action); return Promise.resolve({ data: plan.data ?? null, error: ('error' in plan ? plan.error : null) ?? null }) },
      }
    },
  } as any

  const result = await setTaskStatusForUser(supabase, 'owner-1', 'task-recurring', 'COMPLETED')

  assert.equal(result.id, 'task-recurring')
  assert.equal(calls.length, 4)
  assert.equal(calls[3].payload?.recurrence_parent_id, 'task-recurring')
  assert.equal(calls[3].payload?.due_at, '2099-01-02T09:00:00.000Z')
  assert.equal(plans.length, 0)
})

test('updateTaskForUser rejects a missing owner before database access', async () => {
  let fromCalls = 0
  const supabase = {
    from() {
      fromCalls += 1
      throw new Error('database should not be reached')
    },
  } as any

  await assert.rejects(
    () => updateTaskForUser(supabase, '', 'task-1', validTaskUpdate()),
    /Unauthorized/,
  )
  assert.equal(fromCalls, 0)
})

test('updateTaskForUser leaves omitted relationships untouched and enforces its update allowlist', async () => {
  const { supabase, calls, remainingPlans } = createUpdateTaskSupabase([
    { table: 'tasks', action: 'update', data: { id: 'task-1', user_id: 'owner-1' } },
  ])
  const input = {
    ...validTaskUpdate(),
    id: 'attacker-task',
    user_id: 'attacker',
    status: 'COMPLETED',
    created_at: 'spoofed',
    recurrence_parent_id: 'attacker-parent',
  } as UpdateTaskInput & Record<string, unknown>

  await updateTaskForUser(supabase, 'owner-1', 'task-1', input)

  assert.deepEqual(calls[0].filters, [['id', 'task-1'], ['user_id', 'owner-1']])
  assert.deepEqual(Object.keys(calls[0].payload ?? {}).sort(), [
    'due_at',
    'estimated_minutes',
    'priority',
    'recurrence_rule',
    'recurrence_until',
    'scheduled_end',
    'scheduled_start',
    'title',
    'updated_at',
  ])
  assert.equal(calls[0].payload?.title, 'Updated task')
  assert.equal(calls[0].payload?.project_id, undefined)
  assert.equal(calls[0].payload?.parent_task_id, undefined)
  assert.equal(calls[0].payload?.user_id, undefined)
  assert.equal(calls[0].payload?.status, undefined)
  assert.equal(calls[0].payload?.recurrence_parent_id, undefined)
  assert.equal(typeof calls[0].payload?.updated_at, 'string')
  assert.equal(remainingPlans(), 0)
})

test('updateTaskForUser validates a parent change while preserving an omitted project link', async () => {
  const { supabase, calls, remainingPlans } = createUpdateTaskSupabase([
    { table: 'tasks', action: 'select', data: { project_id: 'project-1', parent_task_id: 'old-parent' } },
    { table: 'tasks', action: 'select', data: { id: 'new-parent', user_id: 'owner-1', project_id: 'project-1' } },
    { table: 'projects', action: 'select', data: { id: 'project-1' } },
    { table: 'tasks', action: 'update', data: { id: 'task-1', parent_task_id: 'new-parent' } },
  ])

  await updateTaskForUser(supabase, 'owner-1', 'task-1', {
    ...validTaskUpdate(),
    parent_task_id: 'new-parent',
  })

  assert.deepEqual(calls[0].filters, [['id', 'task-1'], ['user_id', 'owner-1']])
  assert.equal(calls[0].columns, 'project_id,parent_task_id')
  assert.deepEqual(calls[1].filters, [['id', 'new-parent'], ['user_id', 'owner-1']])
  assert.deepEqual(calls[2].filters, [['id', 'project-1'], ['user_id', 'owner-1']])
  assert.deepEqual(calls[3].filters, [['id', 'task-1'], ['user_id', 'owner-1']])
  assert.equal(calls[3].payload?.parent_task_id, 'new-parent')
  assert.equal(calls[3].payload?.project_id, undefined)
  assert.equal(remainingPlans(), 0)
})

test('updateTaskForUser treats an explicit null parent as a clear while preserving the omitted project', async () => {
  const { supabase, calls, remainingPlans } = createUpdateTaskSupabase([
    { table: 'tasks', action: 'select', data: { project_id: 'project-1', parent_task_id: 'old-parent' } },
    { table: 'projects', action: 'select', data: { id: 'project-1' } },
    { table: 'tasks', action: 'update', data: { id: 'task-1', project_id: 'project-1', parent_task_id: null } },
  ])

  await updateTaskForUser(supabase, 'owner-1', 'task-1', {
    ...validTaskUpdate(),
    parent_task_id: null,
  })

  assert.deepEqual(calls[0].filters, [['id', 'task-1'], ['user_id', 'owner-1']])
  assert.deepEqual(calls[1].filters, [['id', 'project-1'], ['user_id', 'owner-1']])
  assert.equal(calls[2].payload?.parent_task_id, null)
  assert.equal(calls[2].payload?.project_id, undefined)
  assert.equal(remainingPlans(), 0)
})

test('updateTaskForUser treats an explicit null project as a clear when the parent is omitted', async () => {
  const { supabase, calls, remainingPlans } = createUpdateTaskSupabase([
    { table: 'tasks', action: 'select', data: { project_id: 'project-1', parent_task_id: null } },
    { table: 'tasks', action: 'update', data: { id: 'task-1', project_id: null, parent_task_id: null } },
  ])

  await updateTaskForUser(supabase, 'owner-1', 'task-1', {
    ...validTaskUpdate(),
    project_id: null,
  })

  assert.deepEqual(calls[0].filters, [['id', 'task-1'], ['user_id', 'owner-1']])
  assert.equal(calls[1].payload?.project_id, null)
  assert.equal(calls[1].payload?.parent_task_id, undefined)
  assert.equal(remainingPlans(), 0)
})

test('updateTaskForUser requires an ACTIVE owner project before a new project assignment', async () => {
  const { supabase, calls, remainingPlans } = createUpdateTaskSupabase([
    { table: 'tasks', action: 'select', data: { project_id: null, parent_task_id: null } },
    { table: 'projects', action: 'select', data: { id: 'project-2', status: 'ACTIVE' } },
    { table: 'tasks', action: 'update', data: { id: 'task-1', project_id: 'project-2' } },
  ])

  await updateTaskForUser(supabase, 'owner-1', 'task-1', {
    ...validTaskUpdate(),
    project_id: 'project-2',
  })

  assert.equal(calls[1].columns, 'id,status')
  assert.deepEqual(calls[1].filters, [['id', 'project-2'], ['user_id', 'owner-1']])
  assert.equal(calls[2].payload?.project_id, 'project-2')
  assert.equal(remainingPlans(), 0)
})

test('updateTaskForUser rejects an ARCHIVED project before mutating task relationships', async () => {
  const originalTask = { project_id: null, parent_task_id: null }
  const { supabase, calls, remainingPlans } = createUpdateTaskSupabase([
    { table: 'tasks', action: 'select', data: originalTask },
    { table: 'projects', action: 'select', data: { id: 'archived-project', status: 'ARCHIVED' } },
  ])

  await assert.rejects(
    () => updateTaskForUser(supabase, 'owner-1', 'task-1', {
      ...validTaskUpdate(),
      project_id: 'archived-project',
    }),
    /Tasks can only be linked to active projects/,
  )

  assert.equal(calls.length, 2)
  assert.equal(calls.some(call => call.action === 'update'), false)
  assert.equal(calls.some(call => call.action === 'insert'), false)
  assert.deepEqual(originalTask, { project_id: null, parent_task_id: null })
  assert.equal(remainingPlans(), 0)
})
