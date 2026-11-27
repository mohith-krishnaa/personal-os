export type ReviewPeriod = 'week' | 'month'

export type AnalyticsTask = {
  id: string
  status: string
  estimated_minutes: number | null
  actual_minutes: number | null
  completed_at: string | null
  created_at: string
}

export type AnalyticsProgressEntry = {
  value: number
  occurred_on: string
}

export type ReviewBounds = {
  start: Date
  end: Date
  previousStart: Date
  previousEnd: Date
  period: ReviewPeriod
}

export type ReviewBucket = {
  date: string
  label: string
  completed: number
  progress: number
}

export type AnalyticsReview = {
  period: ReviewPeriod
  start: string
  end: string
  buckets: ReviewBucket[]
  completed: number
  created: number
  progress: number
  plannedMinutes: number
  actualMinutes: number
  trackedTasks: number
  trackedPlannedMinutes: number
  trackedActualMinutes: number
  previousCompleted: number
  previousProgress: number
  previousCreated: number
}

const DAY_MS = 24 * 60 * 60 * 1000

function isoDay(date: Date) {
  return date.toISOString().slice(0, 10)
}

function startOfUtcDay(date: Date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()))
}

export function getReviewBounds(period: ReviewPeriod, reference = new Date()): ReviewBounds {
  const today = startOfUtcDay(reference)
  if (period === 'week') {
    const start = new Date(today.getTime() - ((today.getUTCDay() + 6) % 7) * DAY_MS)
    const end = new Date(start.getTime() + 7 * DAY_MS)
    return { period, start, end, previousStart: new Date(start.getTime() - 7 * DAY_MS), previousEnd: start }
  }

  const start = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1))
  const end = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 1))
  const previousStart = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() - 1, 1))
  return { period, start, end, previousStart, previousEnd: start }
}

export function buildAnalyticsReview(
  tasks: AnalyticsTask[],
  progressEntries: AnalyticsProgressEntry[],
  bounds: ReviewBounds,
): AnalyticsReview {
  const days = Math.round((bounds.end.getTime() - bounds.start.getTime()) / DAY_MS)
  const buckets: ReviewBucket[] = Array.from({ length: days }, (_, index) => {
    const date = new Date(bounds.start.getTime() + index * DAY_MS)
    return {
      date: isoDay(date),
      label: new Intl.DateTimeFormat('en-IN', { month: 'short', day: 'numeric', timeZone: 'UTC' }).format(date),
      completed: 0,
      progress: 0,
    }
  })
  const byDate = new Map(buckets.map(bucket => [bucket.date, bucket]))
  const inCurrent = (value: string) => value >= bounds.start.toISOString() && value < bounds.end.toISOString()
  const inPrevious = (value: string) => value >= bounds.previousStart.toISOString() && value < bounds.previousEnd.toISOString()

  let completed = 0
  let created = 0
  let plannedMinutes = 0
  let actualMinutes = 0
  let trackedTasks = 0
  let trackedPlannedMinutes = 0
  let trackedActualMinutes = 0
  let previousCompleted = 0
  let previousCreated = 0
  let previousProgress = 0
  let progress = 0

  for (const task of tasks) {
    if (task.status === 'COMPLETED' && task.completed_at) {
      if (inCurrent(task.completed_at)) {
        completed += 1
        const bucket = byDate.get(isoDay(new Date(task.completed_at)))
        if (bucket) bucket.completed += 1
        if (task.estimated_minutes != null && task.actual_minutes != null) {
          plannedMinutes += task.estimated_minutes
          actualMinutes += task.actual_minutes
          trackedTasks += 1
          trackedPlannedMinutes += task.estimated_minutes
          trackedActualMinutes += task.actual_minutes
        }
      } else if (inPrevious(task.completed_at)) previousCompleted += 1
    }
    if (inCurrent(task.created_at)) created += 1
    else if (inPrevious(task.created_at)) previousCreated += 1
  }

  for (const entry of progressEntries) {
    const bucket = byDate.get(entry.occurred_on)
    if (bucket) {
      progress += entry.value
      bucket.progress += entry.value
    } else if (entry.occurred_on >= isoDay(bounds.previousStart) && entry.occurred_on < isoDay(bounds.previousEnd)) {
      previousProgress += entry.value
    }
  }

  return {
    period: bounds.period,
    start: isoDay(bounds.start),
    end: isoDay(new Date(bounds.end.getTime() - DAY_MS)),
    buckets,
    completed,
    created,
    progress,
    plannedMinutes,
    actualMinutes,
    trackedTasks,
    trackedPlannedMinutes,
    trackedActualMinutes,
    previousCompleted,
    previousProgress,
    previousCreated,
  }
}

export function getAnalyticsInsights(review: AnalyticsReview) {
  const insights: string[] = []
  if (review.completed > review.previousCompleted) {
    insights.push(`You completed ${review.completed - review.previousCompleted} more task${review.completed - review.previousCompleted === 1 ? '' : 's'} than in the previous period.`)
  } else if (review.completed < review.previousCompleted) {
    insights.push(`You completed ${review.previousCompleted - review.completed} fewer task${review.previousCompleted - review.completed === 1 ? '' : 's'} than in the previous period.`)
  } else {
    insights.push('You completed the same number of tasks as in the previous period.')
  }

  if (review.trackedTasks >= 3 && review.trackedPlannedMinutes > 0) {
    const difference = Math.round((review.trackedActualMinutes / review.trackedPlannedMinutes - 1) * 100)
    if (difference > 10) insights.push(`Tracked work took ${difference}% longer than estimated.`)
    else if (difference < -10) insights.push(`Tracked work took ${Math.abs(difference)}% less time than estimated.`)
    else insights.push('Tracked work was close to your time estimates.')
  } else {
    insights.push('Record actual minutes on completed tasks to see how your estimates compare.')
  }

  if (review.progress > 0 || review.previousProgress > 0) {
    insights.push(review.progress > review.previousProgress
      ? 'Goal progress increased compared with the previous period.'
      : review.progress < review.previousProgress
        ? 'Goal progress was lower than in the previous period.'
        : 'Goal progress matched the previous period.')
  }
  return insights
}

