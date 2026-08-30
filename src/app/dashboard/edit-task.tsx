'use client'

import { useState } from 'react'
import type { Task, TaskPriority } from '@/types/task'
import { updateTaskAction } from './actions'

function localValue(value: string | null) {
  if (!value) return ''
  const date = new Date(value)
  const offset = date.getTimezoneOffset() * 60000
  return new Date(date.getTime() - offset).toISOString().slice(0, 16)
}

export default function EditTask({ task }: { task: Task }) {
  const [open, setOpen] = useState(false)
  const [title, setTitle] = useState(task.title)
  const [priority, setPriority] = useState<TaskPriority>(task.priority)
  const [minutes, setMinutes] = useState(task.estimated_minutes?.toString() ?? '')
  const [dueAt, setDueAt] = useState(localValue(task.due_at))
  const [start, setStart] = useState(localValue(task.scheduled_start))
  const [end, setEnd] = useState(localValue(task.scheduled_end))
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)

  async function save() {
    setSaving(true); setError('')
    try {
      await updateTaskAction(task.id, { title, priority, estimated_minutes: minutes ? Number(minutes) : null, due_at: dueAt ? new Date(dueAt).toISOString() : null, scheduled_start: start ? new Date(start).toISOString() : null, scheduled_end: end ? new Date(end).toISOString() : null })
      setOpen(false)
    } catch (err) { setError(err instanceof Error ? err.message : 'Could not update task.') }
    finally { setSaving(false) }
  }

  if (!open) return <button onClick={() => setOpen(true)} aria-label={`Edit ${task.title}`} style={{ background: 'transparent', color: '#8b949e', border: '1px solid #303640', borderRadius: 8, padding: '5px 8px' }}>Edit</button>
  return <div style={{ display: 'grid', gap: 8, padding: 12, border: '1px solid #303640', borderRadius: 12, background: '#0d1014', marginTop: 8 }}>
    <input value={title} onChange={e => setTitle(e.target.value)} aria-label="Task title" style={{ background: '#111419', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 8, padding: 8 }} />
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
      <select value={priority} onChange={e => setPriority(e.target.value as TaskPriority)} aria-label="Priority" style={{ background: '#111419', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 8, padding: 8 }}><option value="LOW">Low</option><option value="MEDIUM">Medium</option><option value="HIGH">High</option></select>
      <input type="number" min="1" value={minutes} onChange={e => setMinutes(e.target.value)} placeholder="Minutes" aria-label="Estimated minutes" style={{ background: '#111419', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 8, padding: 8 }} />
      <input type="datetime-local" value={dueAt} onChange={e => setDueAt(e.target.value)} aria-label="Due date" style={{ background: '#111419', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 8, padding: 8 }} />
      <input type="datetime-local" value={start} onChange={e => setStart(e.target.value)} aria-label="Scheduled start" style={{ background: '#111419', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 8, padding: 8 }} />
      <input type="datetime-local" value={end} onChange={e => setEnd(e.target.value)} aria-label="Scheduled end" style={{ background: '#111419', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 8, padding: 8 }} />
    </div>
    {error && <div role="alert" style={{ color: '#ff7b72', fontSize: 12 }}>{error}</div>}
    <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}><button type="button" onClick={() => setOpen(false)} style={{ background: 'transparent', color: '#8b949e', border: '1px solid #303640', borderRadius: 8, padding: 8 }}>Cancel</button><button onClick={() => void save()} disabled={saving || !title.trim()} style={{ background: '#f4f4f5', color: '#090a0c', border: 0, borderRadius: 8, padding: 8, fontWeight: 700 }}>{saving ? 'Saving…' : 'Save'}</button></div>
  </div>
}
