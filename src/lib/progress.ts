import type { ProgressEntry, Streak } from '@/types/progress'

export type { ProgressEntry, Streak } from '@/types/progress'

export function calculateStreak(entries: Pick<ProgressEntry, 'value' | 'occurred_on'>[], today = new Date()): Streak {
  const days = new Set(entries.map((entry) => entry.occurred_on.slice(0, 10)))
  const date = new Date(today)
  const todayKey = date.toISOString().slice(0, 10)
  const yesterday = new Date(date)
  yesterday.setUTCDate(yesterday.getUTCDate() - 1)
  const yesterdayKey = yesterday.toISOString().slice(0, 10)
  let cursor = days.has(todayKey) ? date : days.has(yesterdayKey) ? yesterday : null
  let current = 0
  while (cursor) {
    const key = cursor.toISOString().slice(0, 10)
    if (!days.has(key)) break
    current += 1
    const previous = new Date(cursor)
    previous.setUTCDate(previous.getUTCDate() - 1)
    cursor = previous
  }

  const sorted = [...days].sort()
  let longest = 0
  let run = 0
  let previousKey: string | null = null
  for (const key of sorted) {
    if (previousKey) {
      const previous = new Date(`${previousKey}T00:00:00Z`)
      const currentDate = new Date(`${key}T00:00:00Z`)
      const gap = Math.round((currentDate.getTime() - previous.getTime()) / 86400000)
      run = gap === 1 ? run + 1 : 1
    } else run = 1
    longest = Math.max(longest, run)
    previousKey = key
  }
  return { current, longest, last_active_on: sorted.at(-1) ?? null }
}

export function progressPercent(current: number, target: number) {
  if (target <= 0) return 0
  return Math.min(100, Math.max(0, Math.round((current / target) * 100)))
}
