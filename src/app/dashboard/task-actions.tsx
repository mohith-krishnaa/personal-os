'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/browser'
import type { Task } from '@/types/task'

export default function TaskActions({ mode, task }: { mode: 'add' | 'toggle'; task?: Task }) {
  const [title, setTitle] = useState('')
  const [loading, setLoading] = useState(false)

  async function addTask() {
    if (!title.trim()) return
    setLoading(true)
    const supabase = createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { window.location.href = '/login'; return }
    const { data, error } = await supabase.from('tasks').insert({ user_id: user.id, title: title.trim(), priority: 'MEDIUM' }).select('id').single()
    if (!error && data) {
      await supabase.from('activity_events').insert({ user_id: user.id, event_type: 'TASK_CREATED', entity_type: 'TASK', entity_id: data.id, metadata: { source: 'dashboard' } })
      window.location.reload()
    }
    setLoading(false)
  }

  async function toggleTask() {
    if (!task) return
    setLoading(true)
    const supabase = createClient()
    const next = task.status === 'COMPLETED' ? 'TODO' : 'COMPLETED'
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { window.location.href = '/login'; return }
    const { error } = await supabase.from('tasks').update({ status: next, completed_at: next === 'COMPLETED' ? new Date().toISOString() : null }).eq('id', task.id).eq('user_id', user.id)
    if (!error) {
      await supabase.from('activity_events').insert({ user_id: user.id, event_type: next === 'COMPLETED' ? 'TASK_COMPLETED' : 'TASK_STATUS_CHANGED', entity_type: 'TASK', entity_id: task.id, metadata: { status: next, source: 'dashboard' } })
      window.location.reload()
    }
    setLoading(false)
  }

  if (mode === 'toggle') return <button aria-label={task?.status === 'COMPLETED' ? 'Mark incomplete' : 'Mark complete'} disabled={loading} onClick={toggleTask} style={{ width: 30, height: 30, borderRadius: 9, border: '1px solid #3a404a', background: 'transparent', color: '#f4f4f5' }}>{task?.status === 'COMPLETED' ? '✓' : '○'}</button>

  return <form onSubmit={(event) => { event.preventDefault(); void addTask() }} style={{ display: 'flex', gap: 8 }}>
    <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="New task…" aria-label="New task" style={{ width: 210, background: '#111419', color: '#f4f4f5', border: '1px solid #24282f', borderRadius: 10, padding: '10px 12px' }} />
    <button disabled={loading || !title.trim()} style={{ background: '#f4f4f5', color: '#090a0c', border: 0, borderRadius: 10, padding: '10px 14px', fontWeight: 600 }}>{loading ? '…' : 'Add'}</button>
  </form>
}
