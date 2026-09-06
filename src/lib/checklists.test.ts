import test from 'node:test'
import assert from 'node:assert/strict'
import { createChecklistItem } from './checklists'

test('rejects invalid checklist positions after task validation', async () => {
  const supabase = { from: () => ({ select: () => ({ eq: () => ({ eq: () => ({ single: async () => ({ data: { id: 'task' }, error: null }) }) }) }) }) } as any
  await assert.rejects(() => createChecklistItem(supabase, 'user', 'task', 'Step', -1), /non-negative integer/)
})
