import { describe, expect, it } from 'vitest'
import { calculateStreak, progressPercent } from './progress'

describe('calculateStreak', () => {
  const today = new Date('2026-08-30T12:00:00Z')

  it('counts today and consecutive previous days', () => {
    expect(calculateStreak([
      { value: 1, occurred_on: '2026-08-28' },
      { value: 2, occurred_on: '2026-08-29' },
      { value: 1, occurred_on: '2026-08-30' },
    ], today)).toMatchObject({ current: 3, longest: 3, last_active_on: '2026-08-30' })
  })

  it('continues a streak when the latest entry was yesterday', () => {
    expect(calculateStreak([
      { value: 1, occurred_on: '2026-08-28' },
      { value: 1, occurred_on: '2026-08-29' },
    ], today).current).toBe(2)
  })

  it('breaks current streak after a gap but preserves longest streak', () => {
    expect(calculateStreak([
      { value: 1, occurred_on: '2026-08-26' },
      { value: 1, occurred_on: '2026-08-27' },
      { value: 1, occurred_on: '2026-08-30' },
    ], today)).toMatchObject({ current: 1, longest: 2 })
  })

  it('treats multiple entries on one day as one streak day', () => {
    expect(calculateStreak([
      { value: 1, occurred_on: '2026-08-29' },
      { value: 2, occurred_on: '2026-08-29' },
      { value: 1, occurred_on: '2026-08-30' },
    ], today).current).toBe(2)
  })
})

describe('progressPercent', () => {
  it('clamps progress between zero and one hundred', () => {
    expect(progressPercent(25, 100)).toBe(25)
    expect(progressPercent(150, 100)).toBe(100)
    expect(progressPercent(-1, 100)).toBe(0)
    expect(progressPercent(1, 0)).toBe(0)
  })
})
