import test from 'node:test'
import assert from 'node:assert/strict'
import { createSubtask } from './subtasks'

test('rejects blank subtask titles before database access', async () => {
  const supabase = { from: () => { throw new Error('database should not be reached') } } as any
  await assert.rejects(() => createSubtask(supabase, 'user', 'parent', { title: '   ' }), /Parent task not found|database should not be reached/)
})
