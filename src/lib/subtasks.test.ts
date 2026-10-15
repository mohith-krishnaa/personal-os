import test from 'node:test'
import assert from 'node:assert/strict'
import { createSubtask } from './subtasks'

test('rejects blank subtask titles before database access', async () => {
  const supabase = { from: () => { throw new Error('database should not be reached') } } as any
  await assert.rejects(() => createSubtask(supabase, 'user', 'parent', { title: '   ' }), /Subtask title is required/)
})

test('rejects overlong subtask titles before database access', async () => {
  const supabase = { from: () => { throw new Error('database should not be reached') } } as any
  await assert.rejects(() => createSubtask(supabase, 'user', 'parent', { title: 'x'.repeat(241) }), /240 characters or fewer/)
})
