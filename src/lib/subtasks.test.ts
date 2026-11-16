import test from 'node:test'
import assert from 'node:assert/strict'
import { createSubtask, listSubtasks } from './subtasks'
import { afterSubtaskCreated } from './subtask-state'

function unreachableDatabase() {
  return { from: () => { throw new Error('database should not be reached') } } as any
}

test('rejects blank subtask titles before database access', async () => {
  await assert.rejects(
    () => createSubtask(unreachableDatabase(), 'user', 'parent', { title: '   ' }),
    /Subtask title is required/,
  )
})

test('rejects overlong subtask titles before database access', async () => {
  await assert.rejects(
    () => createSubtask(unreachableDatabase(), 'user', 'parent', { title: 'x'.repeat(241) }),
    /240 characters or fewer/,
  )
})

test('rejects a missing parent task id before database access', async () => {
  await assert.rejects(
    () => createSubtask(unreachableDatabase(), 'user', '', { title: 'Valid title' }),
    /Parent task is required/,
  )
})

test('rejects non-positive estimated minutes before database access', async () => {
  for (const estimated_minutes of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    await assert.rejects(
      () => createSubtask(unreachableDatabase(), 'user', 'parent', { title: 'Valid title', estimated_minutes }),
      /Estimated minutes must be greater than zero/,
    )
  }
})

test('rejects a project that differs from the parent project before insert', async () => {
  const supabase = {
    from(table: string) {
      if (table !== 'tasks') throw new Error('project lookup should not be reached')
      return {
        select() {
          return {
            eq() {
              return {
                eq() {
                  return {
                    single: async () => ({
                      data: { id: 'parent', user_id: 'user', project_id: 'parent-project' },
                      error: null,
                    }),
                  }
                },
              }
            },
          }
        },
        insert() {
          throw new Error('task insert should not be reached')
        },
      }
    },
  } as any

  await assert.rejects(
    () => createSubtask(supabase, 'user', 'parent', { title: 'Valid title', project_id: 'other-project' }),
    /same project as its parent/,
  )
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

test('does not list children when the parent does not belong to the requested owner', async () => {
  let fromCalls = 0
  const supabase = {
    from() {
      fromCalls += 1
      return {
        select() { return this },
        eq() { return this },
        single: async () => ({ data: null, error: { message: 'not found' } }),
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
