import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { summarizeGoalProgress } from './progress-service'

describe('summarizeGoalProgress', () => {
  it('keeps legacy goals readable when progress metrics are not configured', () => {
    assert.deepEqual(summarizeGoalProgress({ target: null }, []), {
      entries: [],
      total: 0,
      percent: 0,
      streak: { current: 0, longest: 0, last_active_on: null },
    })
  })

  it('calculates progress for configured measurable goals', () => {
    assert.equal(summarizeGoalProgress({ target: 20 }, [
      { value: 5, occurred_on: '2026-11-16' },
      { value: 5, occurred_on: '2026-11-17' },
    ]).percent, 50)
  })
})
