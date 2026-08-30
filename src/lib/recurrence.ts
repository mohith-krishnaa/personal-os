export type RecurrenceRule =
  | { frequency: 'DAILY'; interval: number }
  | { frequency: 'WEEKLY'; interval: number; weekdays: number[]; anchorDate: string }
  | { frequency: 'MONTHLY'; interval: number; dayOfMonth: number; anchorDayOfMonth?: number }

function daysInMonth(year: number, month: number) {
  return new Date(Date.UTC(year, month + 1, 0)).getUTCDate()
}

function startOfUtcWeek(date: Date) {
  const start = new Date(date)
  start.setUTCHours(0, 0, 0, 0)
  start.setUTCDate(start.getUTCDate() - start.getUTCDay())
  return start
}

function weeksFromAnchor(date: Date, anchorDate: Date) {
  const diff = startOfUtcWeek(date).getTime() - startOfUtcWeek(anchorDate).getTime()
  return Math.floor(diff / (7 * 24 * 60 * 60 * 1000))
}

export function nextOccurrence(from: Date, rule: RecurrenceRule): Date {
  const date = new Date(from)

  if (rule.frequency === 'DAILY') {
    date.setUTCDate(date.getUTCDate() + rule.interval)
    return date
  }

  if (rule.frequency === 'MONTHLY') {
    const targetMonth = date.getUTCMonth() + rule.interval
    const target = new Date(Date.UTC(
      date.getUTCFullYear(),
      targetMonth,
      1,
      date.getUTCHours(),
      date.getUTCMinutes(),
      date.getUTCSeconds(),
      date.getUTCMilliseconds(),
    ))
    const anchorDay = rule.anchorDayOfMonth ?? rule.dayOfMonth
    target.setUTCDate(Math.min(anchorDay, daysInMonth(target.getUTCFullYear(), target.getUTCMonth())))
    return target
  }

  const anchorDate = new Date(rule.anchorDate)
  if (Number.isNaN(anchorDate.getTime())) throw new Error('Weekly recurrence anchor date is invalid.')

  const wanted = new Set(rule.weekdays)
  for (let i = 1; i <= 7 * (rule.interval + 1); i += 1) {
    date.setUTCDate(date.getUTCDate() + 1)
    if (!wanted.has(date.getUTCDay())) continue

    const weekIndex = weeksFromAnchor(date, anchorDate)
    if (weekIndex >= 0 && weekIndex % rule.interval === 0) return date
  }

  throw new Error('Could not calculate the next weekly occurrence.')
}

export function validateRecurrence(rule: RecurrenceRule) {
  if (!Number.isInteger(rule.interval) || rule.interval < 1) {
    throw new Error('Recurrence interval must be a positive integer.')
  }

  if (rule.frequency === 'WEEKLY') {
    if (!rule.weekdays.length || rule.weekdays.some(day => !Number.isInteger(day) || day < 0 || day > 6)) {
      throw new Error('Weekly recurrence needs valid weekdays.')
    }
    if (Number.isNaN(Date.parse(rule.anchorDate))) {
      throw new Error('Weekly recurrence needs a valid anchor date.')
    }
  }

  if (rule.frequency === 'MONTHLY') {
    if (!Number.isInteger(rule.dayOfMonth) || rule.dayOfMonth < 1 || rule.dayOfMonth > 31) {
      throw new Error('Monthly recurrence needs a day from 1 to 31.')
    }
    if (rule.anchorDayOfMonth != null && (!Number.isInteger(rule.anchorDayOfMonth) || rule.anchorDayOfMonth < 1 || rule.anchorDayOfMonth > 31)) {
      throw new Error('Monthly recurrence anchor day must be from 1 to 31.')
    }
  }
}
