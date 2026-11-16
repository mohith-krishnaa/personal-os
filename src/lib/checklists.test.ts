import test from 'node:test'
import assert from 'node:assert/strict'
import { createChecklistItem, deleteChecklistItem, listChecklistItems, setChecklistItemCompleted } from './checklists'

test('rejects blank checklist titles before database access', async () => {
  const supabase = { from: () => { throw new Error('database should not be reached') } } as any
  await assert.rejects(() => createChecklistItem(supabase, 'user', 'task', '   '), /Checklist item title is required/)
})

test('rejects overlong checklist titles before database access', async () => {
  const supabase = { from: () => { throw new Error('database should not be reached') } } as any
  await assert.rejects(() => createChecklistItem(supabase, 'user', 'task', 'x'.repeat(241)), /240 characters or fewer/)
})

test('rejects invalid checklist positions before database access', async () => {
  const supabase = { from: () => { throw new Error('database should not be reached') } } as any
  await assert.rejects(() => createChecklistItem(supabase, 'user', 'task', 'Step', -1), /non-negative integer/)
})

import { afterChecklistItemCreated } from './checklist-state'

test('keeps checklist items in server list order after a create on a loaded list', () => {
  const earlier = { id: 'a', position: 0, created_at: '2026-01-01T00:00:00.000Z' }
  const later = { id: 'b', position: 0, created_at: '2026-01-03T00:00:00.000Z' }
  const created = { id: 'c', position: 0, created_at: '2026-01-02T00:00:00.000Z' }

  const result = afterChecklistItemCreated([later, earlier], created, true)

  assert.deepEqual(result.items.map(item => item.id), ['a', 'c', 'b'])
  assert.equal(result.shouldReload, false)
})

test('requests a canonical reload after creating into a list that failed to load', () => {
  const created = { id: 'created', position: 0, created_at: '2026-01-02T00:00:00.000Z' }
  const result = afterChecklistItemCreated([], created, false)

  assert.deepEqual(result.items, [created])
  assert.equal(result.shouldReload, true)
})

test('retains locally created checklist items while a failed list remains incomplete', () => {
  const first = { id: 'first', position: 1, created_at: '2026-01-01T00:00:00.000Z' }
  const second = { id: 'second', position: 0, created_at: '2026-01-02T00:00:00.000Z' }
  const result = afterChecklistItemCreated([first], second, false)

  assert.deepEqual(result.items.map(item => item.id), ['second', 'first'])
  assert.equal(result.shouldReload, true)
})


test('lists checklist items only after verifying task ownership and applies owner/task filters', async () => {
  const taskFilters: Array<[string, string]> = []
  const itemFilters: Array<[string, string]> = []
  const orderCalls: Array<[string, { ascending: boolean }]> = []
  const items = [{ id: 'item-1', user_id: 'owner-1', task_id: 'task-1', title: 'First step' }]
  let fromCalls = 0

  const supabase = {
    from(table: string) {
      fromCalls += 1
      if (table === 'tasks') {
        return {
          select(columns: string) {
            assert.equal(columns, 'id')
            return this
          },
          eq(column: string, value: string) {
            taskFilters.push([column, value])
            return this
          },
          single: async () => ({ data: { id: 'task-1' }, error: null }),
        }
      }

      assert.equal(table, 'checklist_items')
      return {
        select(columns: string) {
          assert.equal(columns, '*')
          return this
        },
        eq(column: string, value: string) {
          itemFilters.push([column, value])
          return this
        },
        order(column: string, options: { ascending: boolean }) {
          orderCalls.push([column, options])
          return orderCalls.length === 2
            ? Promise.resolve({ data: items, error: null })
            : this
        },
      }
    },
  } as any

  const result = await listChecklistItems(supabase, 'owner-1', 'task-1')

  assert.equal(fromCalls, 2)
  assert.deepEqual(taskFilters, [['id', 'task-1'], ['user_id', 'owner-1']])
  assert.deepEqual(itemFilters, [['user_id', 'owner-1'], ['task_id', 'task-1']])
  assert.deepEqual(orderCalls, [
    ['position', { ascending: true }],
    ['created_at', { ascending: true }],
  ])
  assert.deepEqual(result, items)
})

test('does not query checklist items when the task belongs to another owner', async () => {
  const tables: string[] = []
  const supabase = {
    from(table: string) {
      tables.push(table)
      return {
        select() { return this },
        eq() { return this },
        single: async () => ({ data: null, error: { message: 'not found' } }),
      }
    },
  } as any

  await assert.rejects(
    () => listChecklistItems(supabase, 'owner-1', 'foreign-task'),
    /Task not found/,
  )
  assert.deepEqual(tables, ['tasks'])
})

test('createChecklistItem derives the inserted owner from its trusted service argument after task validation', async () => {
  const inserted: Record<string, unknown>[] = []
  const tables: string[] = []
  const supabase = {
    from(table: string) {
      tables.push(table)
      if (table === 'tasks') {
        return {
          select() { return this },
          eq() { return this },
          single: async () => ({ data: { id: 'task-1' }, error: null }),
        }
      }

      return {
        insert(values: Record<string, unknown>) {
          inserted.push(values)
          return this
        },
        select() { return this },
        single: async () => ({
          data: { id: 'item-1', user_id: 'owner-1', task_id: 'task-1', title: 'Step', position: 2 },
          error: null,
        }),
      }
    },
  } as any

  await createChecklistItem(supabase, 'owner-1', 'task-1', ' Step ', 2)

  assert.deepEqual(tables, ['tasks', 'checklist_items'])
  assert.deepEqual(inserted, [{
    user_id: 'owner-1',
    task_id: 'task-1',
    title: 'Step',
    position: 2,
  }])
})

test('checklist completion and deletion mutations are constrained by item id and owner', async () => {
  const updateFilters: Array<[string, string]> = []
  const deleteFilters: Array<[string, string]> = []
  const supabase = {
    from(table: string) {
      assert.equal(table, 'checklist_items')
      return {
        update(values: Record<string, unknown>) {
          assert.equal(values.is_completed, true)
          return {
            eq(column: string, value: string) {
              updateFilters.push([column, value])
              return this
            },
            select() {
              return this
            },
            single: async () => ({
              data: { id: 'item-1', user_id: 'owner-1', is_completed: true },
              error: null,
            }),
          }
        },
        delete() {
          return {
            eq(column: string, value: string) {
              deleteFilters.push([column, value])
              return deleteFilters.length === 2
                ? Promise.resolve({ error: null })
                : this
            },
          }
        },
      }
    },
  } as any

  await setChecklistItemCompleted(supabase, 'owner-1', 'item-1', true)
  await deleteChecklistItem(supabase, 'owner-1', 'item-1')

  assert.deepEqual(updateFilters, [['id', 'item-1'], ['user_id', 'owner-1']])
  assert.deepEqual(deleteFilters, [['id', 'item-1'], ['user_id', 'owner-1']])
})
