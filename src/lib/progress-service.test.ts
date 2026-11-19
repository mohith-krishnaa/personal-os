import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { createGoal, getGoalsWithProgress, logProgress, summarizeGoalProgress } from './progress-service'

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
  it('rejects an invalid date format before database access', async () => {
    let fromCalls = 0
    const supabase = {
      from() {
        fromCalls += 1
        throw new Error('database should not be reached')
      },
    } as any

    await assert.rejects(
      () => logProgress(supabase, 'owner-1', {
        goalId: 'goal-1',
        value: 1,
        occurredOn: 'not-a-date',
      }),
      /Invalid progress entry/,
    )
    assert.equal(fromCalls, 0)
  })

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

function createGoalsWithProgressClient(
  goalsResult: { data: any[] | null; error: Error | null },
  entriesResult: { data: any[] | null; error: Error | null } = { data: [], error: null },
) {
  const calls: string[] = []
  const client = {
    from(table: string) {
      if (table === 'goals') {
        return {
          select(columns: string) {
            calls.push(`goals.select:${columns}`)
            return {
              order(column: string, options: { ascending: boolean }) {
                calls.push(`goals.order:${column}:${options.ascending}`)
                return Promise.resolve(goalsResult)
              },
            }
          },
        }
      }

      assert.equal(table, 'progress_entries')
      return {
        select(columns: string) {
          calls.push(`progress_entries.select:${columns}`)
          return {
            in(column: string, values: string[]) {
              calls.push(`progress_entries.in:${column}:${values.join(',')}`)
              return {
                order(orderColumn: string, options: { ascending: boolean }) {
                  calls.push(`progress_entries.order:${orderColumn}:${options.ascending}`)
                  return Promise.resolve(entriesResult)
                },
              }
            },
          }
        },
      }
    },
  }

  return { client: client as any, calls }
}

describe('getGoalsWithProgress', () => {
  it('retains legacy goals and groups their historical entries without inventing metrics', async () => {
    const goals = [
      {
        id: 'legacy-goal',
        user_id: 'owner-1',
        title: 'Legacy goal',
        unit: null,
        target: null,
        created_at: '2026-01-02T00:00:00Z',
        updated_at: '2026-01-02T00:00:00Z',
      },
      {
        id: 'measurable-goal',
        user_id: 'owner-1',
        title: 'Measurable goal',
        unit: 'pages',
        target: 10,
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-01T00:00:00Z',
      },
    ]
    const entries = [
      { id: 'legacy-entry-2', goal_id: 'legacy-goal', user_id: 'owner-1', value: 2, occurred_on: '2026-01-02', created_at: '2026-01-02T12:00:00Z' },
      { id: 'measurable-entry', goal_id: 'measurable-goal', user_id: 'owner-1', value: 5, occurred_on: '2026-02-01', created_at: '2026-02-01T12:00:00Z' },
      { id: 'legacy-entry-1', goal_id: 'legacy-goal', user_id: 'owner-1', value: 1, occurred_on: '2026-01-01', created_at: '2026-01-01T12:00:00Z' },
    ]
    const { client, calls } = createGoalsWithProgressClient(
      { data: goals, error: null },
      { data: entries, error: null },
    )

    const result = await getGoalsWithProgress(client)

    assert.deepEqual(result.map(({ goal }) => goal.id), ['legacy-goal', 'measurable-goal'])
    assert.equal(result[0].goal.unit, null)
    assert.equal(result[0].goal.target, null)
    assert.deepEqual(result[0].progress.entries.map(entry => entry.id), ['legacy-entry-2', 'legacy-entry-1'])
    assert.equal(result[0].progress.total, 3)
    assert.equal(result[0].progress.percent, 0)
    assert.equal(result[0].progress.streak.longest, 2)
    assert.deepEqual(result[1].progress.entries.map(entry => entry.id), ['measurable-entry'])
    assert.equal(result[1].progress.total, 5)
    assert.equal(result[1].progress.percent, 50)
    assert.ok(calls.includes('progress_entries.in:goal_id:legacy-goal,measurable-goal'))
    assert.ok(calls.includes('progress_entries.order:occurred_on:false'))
  })

  it('returns no goals without querying progress entries', async () => {
    const { client, calls } = createGoalsWithProgressClient({ data: [], error: null })

    assert.deepEqual(await getGoalsWithProgress(client), [])
    assert.equal(calls.some(call => call.startsWith('progress_entries.')), false)
  })

  it('returns empty progress for legacy goals when the entries query returns no rows', async () => {
    const goal = {
      id: 'legacy-goal',
      user_id: 'owner-1',
      title: 'Legacy goal',
      unit: null,
      target: null,
      created_at: '2026-01-02T00:00:00Z',
      updated_at: '2026-01-02T00:00:00Z',
    }
    const { client } = createGoalsWithProgressClient(
      { data: [goal], error: null },
      { data: null, error: null },
    )

    const [result] = await getGoalsWithProgress(client)

    assert.equal(result.goal.id, 'legacy-goal')
    assert.deepEqual(result.progress.entries, [])
    assert.equal(result.progress.total, 0)
    assert.equal(result.progress.percent, 0)
    assert.equal(result.progress.streak.longest, 0)
  })

  it('propagates goal query errors instead of presenting an empty dashboard', async () => {
    const queryError = new Error('goals read failed')
    const { client, calls } = createGoalsWithProgressClient({ data: null, error: queryError })

    await assert.rejects(
      () => getGoalsWithProgress(client),
      error => error === queryError,
    )
    assert.equal(calls.some(call => call.startsWith('progress_entries.')), false)
  })

  it('propagates progress-entry query errors instead of silently dropping history', async () => {
    const queryError = new Error('progress entries read failed')
    const { client } = createGoalsWithProgressClient(
      { data: [{ id: 'goal-1', user_id: 'owner-1', title: 'Goal', unit: null, target: null, created_at: '2026-01-01', updated_at: '2026-01-01' }], error: null },
      { data: null, error: queryError },
    )

    await assert.rejects(
      () => getGoalsWithProgress(client),
      error => error === queryError,
    )
  })
})
