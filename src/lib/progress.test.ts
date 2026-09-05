import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { calculateStreak, progressPercent } from './progress'

describe('calculateStreak', () => {
  const today = new Date('2026-08-30T12:00:00Z')

  it('counts today and consecutive previous days', () => {
    assert.deepEqual(calculateStreak([
      { value: 1, occurred_on: '2026-08-28' },
      { value: 2, occurred_on: '2026-08-29' },
      { value: 1, occurred_on: '2026-08-30' },
    ], today), { current: 3, longest: 3, last_active_on: '2026-08-30' })
  })

  it('continues a streak when the latest entry was yesterday', () => {
    assert.equal(calculateStreak([
      { value: 1, occurred_on: '2026-08-28' },
      { value: 1, occurred_on: '2026-08-29' },
    ], today).current, 2)
  })

  it('breaks current streak after a gap but preserves longest streak', () => {
    assert.deepEqual(calculateStreak([
      { value: 1, occurred_on: '2026-08-26' },
      { value: 1, occurred_on: '2026-08-27' },
      { value: 1, occurred_on: '2026-08-30' },
    ], today), { current: 1, longest: 2, last_active_on: '2026-08-30' })
  })

  it('treats multiple entries on one day as one streak day', () => {
    assert.equal(calculateStreak([
      { value: 1, occurred_on: '2026-08-29' },
      { value: 2, occurred_on: '2026-08-29' },
      { value: 1, occurred_on: '2026-08-30' },
    ], today).current, 2)
  })
})

describe('progressPercent', () => {
  it('clamps progress between zero and one hundred', () => {
    assert.equal(progressPercent(25, 100), 25)
    assert.equal(progressPercent(150, 100), 100)
    assert.equal(progressPercent(-1, 100), 0)
    assert.equal(progressPercent(1, 0), 0)
  })
})
