'use client'

import { useState } from 'react'
import type { RecurrenceRule, TaskPriority } from '@/types/task'
import { addTaskAction } from './actions'

type Frequency = 'NONE' | 'DAILY' | 'WEEKLY' | 'MONTHLY'

const weekdayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

export default function TaskEditor() {
  const [open, setOpen] = useState(false)
  const [title, setTitle] = useState('')
  const [priority, setPriority] = useState<TaskPriority>('MEDIUM')
  const [minutes, setMinutes] = useState('')
  const [dueAt, setDueAt] = useState('')
  const [frequency, setFrequency] = useState<Frequency>('NONE')
  const [interval, setInterval] = useState('1')
  const [weekdays, setWeekdays] = useState<number[]>([])
  const [monthDay, setMonthDay] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  function toggleWeekday(day: number) {
    setWeekdays(current => current.includes(day) ? current.filter(value => value !== day) : [...current, day].sort((a, b) => a - b))
  }

  function buildRecurrence(): RecurrenceRule | null {
    if (frequency === 'NONE') return null
    const parsedInterval = Number(interval)
    if (!Number.isInteger(parsedInterval) || parsedInterval < 1) throw new Error('Recurrence interval must be a positive integer.')
    if (!dueAt) throw new Error('Recurring tasks need a due date/time.')

    if (frequency === 'DAILY') return { frequency: 'DAILY', interval: parsedInterval }
    if (frequency === 'MONTHLY') {
      const day = Number(monthDay || dueAt.slice(8, 10))
      return { frequency: 'MONTHLY', interval: parsedInterval, dayOfMonth: day, anchorDayOfMonth: day }
    }

    const selected = weekdays.length ? weekdays : [new Date(dueAt).getDay()]
    return {
      frequency: 'WEEKLY',
      interval: parsedInterval,
      weekdays: selected,
      anchorDate: new Date(dueAt).toISOString(),
    }
  }

  async function submit() {
    if (!title.trim()) return
    setLoading(true); setError('')
    try {
      await addTaskAction({
        title,
        priority,
        estimated_minutes: minutes ? Number(minutes) : null,
        due_at: dueAt ? new Date(dueAt).toISOString() : null,
        recurrence_rule: buildRecurrence(),
      })
      setTitle(''); setMinutes(''); setDueAt(''); setPriority('MEDIUM'); setFrequency('NONE'); setInterval('1'); setWeekdays([]); setMonthDay(''); setOpen(false)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create task.')
    } finally { setLoading(false) }
  }

  if (!open) return <button onClick={() => setOpen(true)} style={{ background: '#f4f4f5', color: '#090a0c', border: 0, borderRadius: 10, padding: '10px 14px', fontWeight: 700 }}>+ New task</button>

  return <form onSubmit={(e) => { e.preventDefault(); void submit() }} style={{ display: 'grid', gap: 10, padding: 16, border: '1px solid #303640', borderRadius: 14, background: '#111419' }}>
    <input autoFocus value={title} onChange={e => setTitle(e.target.value)} placeholder="What needs to be done?" aria-label="Task title" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 10 }} />
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
      <select value={priority} onChange={e => setPriority(e.target.value as TaskPriority)} aria-label="Priority" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 9 }}><option value="LOW">Low</option><option value="MEDIUM">Medium</option><option value="HIGH">High</option></select>
      <input type="number" min="1" value={minutes} onChange={e => setMinutes(e.target.value)} placeholder="Minutes" aria-label="Estimated minutes" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 9 }} />
      <input type="datetime-local" value={dueAt} onChange={e => setDueAt(e.target.value)} aria-label="Due date" />
    </div>

    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
      <select value={frequency} onChange={e => setFrequency(e.target.value as Frequency)} aria-label="Repeat" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 9 }}>
        <option value="NONE">Does not repeat</option>
        <option value="DAILY">Daily</option>
        <option value="WEEKLY">Weekly</option>
        <option value="MONTHLY">Monthly</option>
      </select>
      {frequency !== 'NONE' && <input type="number" min="1" value={interval} onChange={e => setInterval(e.target.value)} aria-label="Repeat interval" placeholder="Every" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 9 }} />}
    </div>

    {frequency === 'WEEKLY' && <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }} aria-label="Repeat weekdays">
      {weekdayLabels.map((label, day) => <button key={label} type="button" aria-pressed={weekdays.includes(day)} onClick={() => toggleWeekday(day)} style={{ background: weekdays.includes(day) ? '#f4f4f5' : '#0b0d10', color: weekdays.includes(day) ? '#090a0c' : '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: '7px 9px' }}>{label}</button>)}
    </div>}

    {frequency === 'MONTHLY' && <input type="number" min="1" max="31" value={monthDay} onChange={e => setMonthDay(e.target.value)} placeholder="Day of month (defaults to due date)" aria-label="Day of month" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 9 }} />}

    {error && <div role="alert" style={{ color: '#ff7b72', fontSize: 13 }}>{error}</div>}
    <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}><button type="button" onClick={() => setOpen(false)} style={{ background: 'transparent', color: '#8b949e', border: '1px solid #303640', borderRadius: 9, padding: '9px 13px' }}>Cancel</button><button disabled={loading || !title.trim()} style={{ background: '#f4f4f5', color: '#090a0c', border: 0, borderRadius: 9, padding: '9px 13px', fontWeight: 700 }}>{loading ? 'Saving…' : 'Create task'}</button></div>
  </form>
}
