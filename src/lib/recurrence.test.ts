import assert from 'node:assert/strict'
import test from 'node:test'
import { nextOccurrence, validateRecurrence } from './recurrence'

test('daily recurrence advances by the configured interval', () => {
  const next = nextOccurrence(new Date('2026-01-01T09:00:00Z'), { frequency: 'DAILY', interval: 3 })
  assert.equal(next.toISOString(), '2026-01-04T09:00:00.000Z')
})

test('weekly recurrence advances to another selected weekday in the same cycle', () => {
  const next = nextOccurrence(new Date('2026-01-05T09:00:00Z'), {
    frequency: 'WEEKLY',
    interval: 1,
    weekdays: [1, 3],
    anchorDate: '2026-01-05T09:00:00Z',
  })
  assert.equal(next.toISOString(), '2026-01-07T09:00:00.000Z')
})

test('weekly interval is anchored to the recurrence cycle', () => {
  const next = nextOccurrence(new Date('2026-01-07T09:00:00Z'), {
    frequency: 'WEEKLY',
    interval: 2,
    weekdays: [1, 3],
    anchorDate: '2026-01-05T09:00:00Z',
  })
  assert.equal(next.toISOString(), '2026-01-19T09:00:00.000Z')
})

test('monthly recurrence clamps day 31 to shorter months', () => {
  const next = nextOccurrence(new Date('2026-01-31T09:00:00Z'), {
    frequency: 'MONTHLY',
    interval: 1,
    dayOfMonth: 31,
  })
  assert.equal(next.toISOString(), '2026-02-28T09:00:00.000Z')
})

test('invalid weekly rules are rejected', () => {
  assert.throws(() => validateRecurrence({
    frequency: 'WEEKLY',
    interval: 1,
    weekdays: [],
    anchorDate: '2026-01-05T09:00:00Z',
  }))
})
