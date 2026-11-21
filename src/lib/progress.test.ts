import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { calculateStreak, getGoalProgressPresentation, hasUsableGoalMetrics, progressPercent } from './progress'

describe('hasUsableGoalMetrics', () => {
  it('accepts a non-empty unit and finite positive target', () => {
    assert.equal(hasUsableGoalMetrics({ unit: ' pages ', target: 10 }), true)
  })

  it('rejects missing, blank, or invalid measurement metadata', () => {
    assert.equal(hasUsableGoalMetrics({ unit: null, target: 10 }), false)
    assert.equal(hasUsableGoalMetrics({ unit: '   ', target: 10 }), false)
    assert.equal(hasUsableGoalMetrics({ unit: 'pages', target: null }), false)
    assert.equal(hasUsableGoalMetrics({ unit: 'pages', target: 0 }), false)
    assert.equal(hasUsableGoalMetrics({ unit: 'pages', target: -1 }), false)
    assert.equal(hasUsableGoalMetrics({ unit: 'pages', target: Number.NaN }), false)
    assert.equal(hasUsableGoalMetrics({ unit: 'pages', target: Number.POSITIVE_INFINITY }), false)
  })
})

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

describe('getGoalProgressPresentation', () => {
  it('shows legacy history without inventing a unit, target, or percentage', () => {
    assert.deepEqual(getGoalProgressPresentation({ unit: null, target: null }, 3, 0), {
      kind: 'historical',
      totalLabel: 'Historical total: 3 (unit unavailable)',
      statusLabel: 'Target not set · Unit unavailable',
    })
  })

  it('preserves an available unit when only the target is missing', () => {
    assert.deepEqual(getGoalProgressPresentation({ unit: 'pages', target: null }, 3, 0), {
      kind: 'historical',
      totalLabel: 'Historical total: 3 pages',
      statusLabel: 'Target not set',
    })
  })

  it('explains when the measurement unit is unavailable', () => {
    assert.deepEqual(getGoalProgressPresentation({ unit: '   ', target: 10 }, 3, 0), {
      kind: 'historical',
      totalLabel: 'Historical total: 3 (unit unavailable)',
      statusLabel: 'Unit unavailable',
    })
  })

  it('shows totals, units, and percentages only for usable metrics', () => {
    assert.deepEqual(getGoalProgressPresentation({ unit: ' pages ', target: 10 }, 3, 30), {
      kind: 'measurable',
      totalLabel: '3 / 10 pages',
      percentLabel: '30%',
      percent: 30,
    })
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
