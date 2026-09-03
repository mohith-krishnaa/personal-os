import assert from 'node:assert/strict'
import test from 'node:test'
import { validateReminderInput } from './reminders'

test('rejects reminders without a task', () => {
  assert.throws(() => validateReminderInput({ task_id: '', remind_at: '2099-01-01T09:00:00Z' }))
})

test('rejects unsupported channels', () => {
  assert.throws(() => validateReminderInput({ task_id: 'task-1', remind_at: '2099-01-01T09:00:00Z', channel: 'PUSH' as never }))
})

test('accepts a future in-app reminder', () => {
  assert.doesNotThrow(() => validateReminderInput({ task_id: 'task-1', remind_at: '2099-01-01T09:00:00Z', timezone: 'Asia/Kolkata', channel: 'IN_APP' }))
})
