'use client'

import { useState } from 'react'
import { createReminderAction } from './reminder-actions'

export default function ReminderEditor({ tasks }: { tasks: { id: string; title: string }[] }) {
  const [taskId, setTaskId] = useState(tasks[0]?.id ?? '')
  const [remindAt, setRemindAt] = useState('')
  const [timezone, setTimezone] = useState(() => Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)

  async function submit(event: React.FormEvent) {
    event.preventDefault(); setLoading(true); setError(''); setDone(false)
    try {
      await createReminderAction({ task_id: taskId, remind_at: new Date(remindAt).toISOString(), timezone, channel: 'IN_APP' })
      setRemindAt(''); setDone(true)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create reminder.')
    } finally { setLoading(false) }
  }

  if (!tasks.length) return <p style={{ color: '#8b949e' }}>Create a task before adding a reminder.</p>

  return <form onSubmit={submit} style={{ display: 'grid', gap: 10 }}>
    <select value={taskId} onChange={e => setTaskId(e.target.value)} aria-label="Reminder task" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 9 }}>
      {tasks.map(task => <option key={task.id} value={task.id}>{task.title}</option>)}
    </select>
    <input type="datetime-local" value={remindAt} onChange={e => setRemindAt(e.target.value)} required aria-label="Reminder time" />
    <input value={timezone} onChange={e => setTimezone(e.target.value)} placeholder="Timezone, e.g. Asia/Kolkata" aria-label="Reminder timezone" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 9 }} />
    {error && <div role="alert" style={{ color: '#ff7b72', fontSize: 13 }}>{error}</div>}
    {done && <div role="status" style={{ color: '#8b949e', fontSize: 13 }}>Reminder scheduled.</div>}
    <button disabled={loading || !remindAt || !taskId} style={{ background: '#f4f4f5', color: '#090a0c', border: 0, borderRadius: 9, padding: '9px 13px', fontWeight: 700 }}>{loading ? 'Saving…' : 'Schedule reminder'}</button>
  </form>
}
