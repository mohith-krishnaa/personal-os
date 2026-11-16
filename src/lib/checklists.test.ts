import test from 'node:test'
import assert from 'node:assert/strict'
import { createChecklistItem } from './checklists'

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
