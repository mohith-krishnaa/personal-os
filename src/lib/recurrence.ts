export type RecurrenceRule =
  | { frequency: 'DAILY'; interval: number }
  | { frequency: 'WEEKLY'; interval: number; weekdays: number[] }
  | { frequency: 'MONTHLY'; interval: number; dayOfMonth: number }

function daysInMonth(year: number, month: number) { return new Date(Date.UTC(year, month + 1, 0)).getUTCDate() }

export function nextOccurrence(from: Date, rule: RecurrenceRule): Date {
  const date = new Date(from)
  if (rule.frequency === 'DAILY') { date.setUTCDate(date.getUTCDate() + rule.interval); return date }
  if (rule.frequency === 'MONTHLY') {
    const targetMonth = date.getUTCMonth() + rule.interval
    const target = new Date(Date.UTC(date.getUTCFullYear(), targetMonth, 1, date.getUTCHours(), date.getUTCMinutes(), date.getUTCSeconds(), date.getUTCMilliseconds()))
    target.setUTCDate(Math.min(rule.dayOfMonth, daysInMonth(target.getUTCFullYear(), target.getUTCMonth())))
    return target
  }
  const wanted = new Set(rule.weekdays)
  for (let i = 1; i <= 7 * rule.interval; i += 1) {
    date.setUTCDate(date.getUTCDate() + 1)
    if (wanted.has(date.getUTCDay())) return date
  }
  return date
}

export function validateRecurrence(rule: RecurrenceRule) {
  if (!Number.isInteger(rule.interval) || rule.interval < 1) throw new Error('Recurrence interval must be a positive integer.')
  if (rule.frequency === 'WEEKLY') {
    if (!rule.weekdays.length || rule.weekdays.some(day => !Number.isInteger(day) || day < 0 || day > 6)) throw new Error('Weekly recurrence needs valid weekdays.')
  }
  if (rule.frequency === 'MONTHLY' && (!Number.isInteger(rule.dayOfMonth) || rule.dayOfMonth < 1 || rule.dayOfMonth > 31)) throw new Error('Monthly recurrence needs a day from 1 to 31.')
}
