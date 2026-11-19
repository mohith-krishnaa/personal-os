import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { createGoal, logProgress, summarizeGoalProgress } from './progress-service'

describe('createGoal', () => {
  it('requires a non-empty unit and a finite positive target before database access', async () => {
    let fromCalls = 0
    const supabase = {
      from() {
        fromCalls += 1
        throw new Error('database should not be reached')
      },
    } as any

    await assert.rejects(
      () => createGoal(supabase, 'owner-1', { title: 'Read', unit: '   ', target: 10 }),
      /Invalid goal/,
    )
    await assert.rejects(
      () => createGoal(supabase, 'owner-1', { title: 'Read', unit: 'pages', target: 0 }),
      /Invalid goal/,
    )
    await assert.rejects(
      () => createGoal(supabase, 'owner-1', { title: 'Read', unit: 'pages', target: Number.NaN }),
      /Invalid goal/,
    )
    assert.equal(fromCalls, 0)
  })

  it('stores the authenticated owner with a valid measurable goal', async () => {
    let inserted: Record<string, unknown> | undefined
    const supabase = {
      from(table: string) {
        assert.equal(table, 'goals')
        return {
          insert(values: Record<string, unknown>) {
            inserted = values
            return {
              select() { return this },
              single: async () => ({ data: { id: 'goal-1', ...values }, error: null }),
            }
          },
        }
      },
    } as any

    const goal = await createGoal(supabase, 'owner-1', { title: 'Read', unit: 'pages', target: 10 })

    assert.equal(inserted?.user_id, 'owner-1')
    assert.equal(goal.id, 'goal-1')
  })
})

describe('logProgress', () => {
  it('checks goal ownership and measurement metadata before inserting progress', async () => {
    const filters: Array<[string, string]> = []
    let inserted: Record<string, unknown> | undefined
    const supabase = {
      from(table: string) {
        if (table === 'goals') {
          return {
            select(columns: string) {
              assert.equal(columns, 'id, unit, target')
              return {
                eq(column: string, value: string) {
                  filters.push([column, value])
                  return this
                },
                maybeSingle: async () => ({
                  data: { id: 'goal-1', unit: 'pages', target: 10 },
                  error: null,
                }),
              }
            },
          }
        }

        assert.equal(table, 'progress_entries')
        return {
          insert(values: Record<string, unknown>) {
            inserted = values
            return {
              select() { return this },
              single: async () => ({ data: { id: 'entry-1', ...values }, error: null }),
            }
          },
        }
      },
    } as any

    const entry = await logProgress(supabase, 'owner-1', {
      goalId: 'goal-1',
      value: 2,
      occurredOn: '2026-11-20',
    })

    assert.deepEqual(filters, [['id', 'goal-1'], ['user_id', 'owner-1']])
    assert.deepEqual(inserted, {
      goal_id: 'goal-1',
      user_id: 'owner-1',
      value: 2,
      occurred_on: '2026-11-20',
    })
    assert.equal(entry.id, 'entry-1')
  })

  it('rejects legacy goals without measurement metadata before inserting progress', async () => {
    let progressInsertCalls = 0
    const supabase = {
      from(table: string) {
        if (table === 'goals') {
          return {
            select() {
              return {
                eq() { return this },
                maybeSingle: async () => ({
                  data: { id: 'legacy-goal', unit: null, target: null },
                  error: null,
                }),
              }
            },
          }
        }

        assert.equal(table, 'progress_entries')
        progressInsertCalls += 1
        throw new Error('progress insert should not be reached')
      },
    } as any

    await assert.rejects(
      () => logProgress(supabase, 'owner-1', {
        goalId: 'legacy-goal',
        value: 1,
        occurredOn: '2026-11-20',
      }),
      /not configured for progress tracking/,
    )
    assert.equal(progressInsertCalls, 0)
  })

  it('rejects missing or non-owned goals without attempting a progress insert', async () => {
    let progressInsertCalls = 0
    const supabase = {
      from(table: string) {
        if (table === 'goals') {
          return {
            select() {
              return {
                eq() { return this },
                maybeSingle: async () => ({ data: null, error: null }),
              }
            },
          }
        }

        assert.equal(table, 'progress_entries')
        progressInsertCalls += 1
        throw new Error('progress insert should not be reached')
      },
    } as any

    await assert.rejects(
      () => logProgress(supabase, 'owner-1', {
        goalId: 'foreign-or-missing',
        value: 1,
        occurredOn: '2026-11-20',
      }),
      /Goal not found/,
    )
    assert.equal(progressInsertCalls, 0)
  })
})

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
