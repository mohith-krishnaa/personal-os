'use client'

import { useState } from 'react'
import type { TaskPriority } from '@/types/task'
import { addTaskAction } from './actions'

export default function TaskEditor() {
  const [open, setOpen] = useState(false)
  const [title, setTitle] = useState('')
  const [priority, setPriority] = useState<TaskPriority>('MEDIUM')
  const [minutes, setMinutes] = useState('')
  const [dueAt, setDueAt] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function submit() {
    if (!title.trim()) return
    setLoading(true); setError('')
    try {
      await addTaskAction({
        title,
        priority,
        estimated_minutes: minutes ? Number(minutes) : null,
        due_at: dueAt ? new Date(dueAt).toISOString() : null,
      })
      setTitle(''); setMinutes(''); setDueAt(''); setPriority('MEDIUM'); setOpen(false)
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
      <input type="datetime-local" value={dueAt} onChange={e => setDueAt(e.target.value)} aria-label="Due date" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 9 }} />
    </div>
    {error && <div role="alert" style={{ color: '#ff7b72', fontSize: 13 }}>{error}</div>}
    <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}><button type="button" onClick={() => setOpen(false)} style={{ background: 'transparent', color: '#8b949e', border: '1px solid #303640', borderRadius: 9, padding: '9px 13px' }}>Cancel</button><button disabled={loading || !title.trim()} style={{ background: '#f4f4f5', color: '#090a0c', border: 0, borderRadius: 9, padding: '9px 13px', fontWeight: 700 }}>{loading ? 'Saving…' : 'Create task'}</button></div>
  </form>
}
