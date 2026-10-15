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
