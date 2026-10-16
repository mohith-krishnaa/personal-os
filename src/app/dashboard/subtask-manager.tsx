'use client'

import { useState } from 'react'
import { addSubtaskAction } from './subtask-actions'
import type { Task } from '@/types/task'

export default function SubtaskManager({ task }: { task: Task }) {
  const [title, setTitle] = useState('')
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  async function add() {
    setSaving(true); setError('')
    try {
      await addSubtaskAction(task.id, { title, project_id: task.project_id })
      setTitle(''); setOpen(false)
    } catch (err) { setError(err instanceof Error ? err.message : 'Could not create subtask.') }
    finally { setSaving(false) }
  }

  if (!open) return <button type="button" onClick={() => setOpen(true)} style={{ background: 'transparent', color: '#8b949e', border: 0, padding: 0, fontSize: 12 }}>+ subtask</button>
  return <div style={{ marginTop: 8 }}><div style={{ display: 'flex', gap: 6 }}><input autoFocus value={title} onChange={e => setTitle(e.target.value)} placeholder="Subtask" aria-label={`Subtask for ${task.title}`} style={{ minWidth: 0, flex: 1, background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 7, padding: 7 }} /><button type="button" disabled={saving || !title.trim()} onClick={() => void add()}>{saving ? '…' : 'Add'}</button><button type="button" onClick={() => setOpen(false)}>Cancel</button></div>{error && <div role="alert" style={{ color: '#ff7b72', fontSize: 12 }}>{error}</div>}</div>
}
