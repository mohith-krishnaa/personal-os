'use client'

import { useState } from 'react'
import { addSubtaskAction, listSubtasksAction } from './subtask-actions'
import { toggleTaskAction } from './actions'
import type { Task } from '@/types/task'
import { afterSubtaskCreated } from '@/lib/subtask-state'

export default function SubtaskManager({ task }: { task: Task }) {
  const [title, setTitle] = useState('')
  const [items, setItems] = useState<Task[]>([])
  const [open, setOpen] = useState(false)
  const [loaded, setLoaded] = useState(false)
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [updatingId, setUpdatingId] = useState<string | null>(null)
  const [error, setError] = useState('')

  async function loadSubtasks() {
    setLoading(true)
    setError('')
    try {
      setItems(await listSubtasksAction(task.id))
      setLoaded(true)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load subtasks.')
    } finally {
      setLoading(false)
    }
  }

  async function toggleOpen() {
    if (open) {
      setOpen(false)
      return
    }
    setOpen(true)
    if (!loaded) await loadSubtasks()
  }

  async function add() {
    const value = title.trim()
    if (!value || loading) return
    setSaving(true)
    setError('')
    try {
      const subtask = await addSubtaskAction(task.id, { title: value, project_id: task.project_id })
      const next = afterSubtaskCreated(items, subtask, loaded)
      setItems(next.items)
      setLoaded(!next.shouldReload)
      setTitle('')
      if (next.shouldReload) await loadSubtasks()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create subtask.')
    } finally {
      setSaving(false)
    }
  }

  async function toggle(subtask: Task) {
    setUpdatingId(subtask.id)
    setError('')
    try {
      const updated = await toggleTaskAction(subtask.id, subtask.status)
      setItems(current => current.map(item => item.id === updated.id ? updated : item))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not update subtask.')
    } finally {
      setUpdatingId(null)
    }
  }

  return <div style={{ marginTop: 5 }}>
    <button type="button" onClick={() => void toggleOpen()} style={{ background: 'transparent', color: '#8b949e', border: 0, padding: 0, fontSize: 12 }}>{open ? '− subtasks' : `+ subtasks${loaded ? ` (${items.length})` : ''}`}</button>
    {open && <div style={{ marginTop: 8, padding: 10, border: '1px solid #303640', borderRadius: 9 }}>
      {loading ? <div style={{ color: '#8b949e', fontSize: 12 }}>Loading subtasks…</div> : items.length === 0 ? <div style={{ color: '#8b949e', fontSize: 12 }}>No subtasks yet.</div> : items.map(subtask => <div key={subtask.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 0' }}>
        <button
          type="button"
          disabled={updatingId === subtask.id}
          aria-label={subtask.status === 'COMPLETED' ? `Mark ${subtask.title} incomplete` : `Mark ${subtask.title} complete`}
          onClick={() => void toggle(subtask)}
          style={{ width: 24, height: 24, borderRadius: 7, border: '1px solid #3a404a', background: 'transparent', color: '#f4f4f5' }}
        >
          {updatingId === subtask.id ? '…' : subtask.status === 'COMPLETED' ? '✓' : '○'}
        </button>
        <span style={{ flex: 1, color: subtask.status === 'COMPLETED' ? '#737b86' : '#f4f4f5', textDecoration: subtask.status === 'COMPLETED' ? 'line-through' : 'none', fontSize: 13 }}>{subtask.title}</span>
      </div>)}
      {error && <div role="alert" style={{ color: '#ff7b72', fontSize: 12, marginTop: 6 }}>{error} <button type="button" onClick={() => void loadSubtasks()} disabled={loading} style={{ marginLeft: 6 }}>Retry</button></div>}
      <form onSubmit={event => { event.preventDefault(); void add() }} style={{ display: 'flex', gap: 6, marginTop: 8 }}>
        <input autoFocus value={title} onChange={event => setTitle(event.target.value)} maxLength={240} placeholder="Subtask" aria-label={`Subtask for ${task.title}`} style={{ minWidth: 0, flex: 1, background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 7, padding: 7 }} />
        <button type="submit" disabled={saving || loading || !title.trim()}>{saving ? '…' : 'Add'}</button>
        <button type="button" onClick={() => setOpen(false)}>Close</button>
      </form>
    </div>}
  </div>
}
