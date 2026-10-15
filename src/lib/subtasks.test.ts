import test from 'node:test'
import assert from 'node:assert/strict'
import { createSubtask } from './subtasks'

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
