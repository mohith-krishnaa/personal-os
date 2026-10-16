'use client'

import { useState } from 'react'
import type { ChecklistItem } from '@/types/checklist'
import { addChecklistItemAction, listChecklistItemsAction, removeChecklistItemAction, toggleChecklistItemAction } from './checklist-actions'

export default function ChecklistManager({ taskId }: { taskId: string }) {
  const [open, setOpen] = useState(false)
  const [items, setItems] = useState<ChecklistItem[]>([])
  const [title, setTitle] = useState('')
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  async function toggleOpen() {
    if (open) { setOpen(false); return }
    setOpen(true)
    setLoading(true)
    setError('')
    try { setItems(await listChecklistItemsAction(taskId)) }
    catch (err) { setError(err instanceof Error ? err.message : 'Could not load checklist.') }
    finally { setLoading(false) }
  }

  async function addItem() {
    if (!title.trim()) return
    setSaving(true); setError('')
    try {
      const item = await addChecklistItemAction(taskId, title)
      setItems(current => [...current, item].sort((a, b) => a.position - b.position))
      setTitle('')
    } catch (err) { setError(err instanceof Error ? err.message : 'Could not add checklist item.') }
    finally { setSaving(false) }
  }

  async function toggleItem(item: ChecklistItem) {
    setError('')
    try {
      const updated = await toggleChecklistItemAction(item.id, !item.is_completed)
      setItems(current => current.map(value => value.id === updated.id ? updated : value))
    } catch (err) { setError(err instanceof Error ? err.message : 'Could not update checklist item.') }
  }

  async function removeItem(id: string) {
    setError('')
    try {
      await removeChecklistItemAction(id)
      setItems(current => current.filter(item => item.id !== id))
    } catch (err) { setError(err instanceof Error ? err.message : 'Could not delete checklist item.') }
  }

  return <div style={{ marginTop: 5 }}>
    <button type="button" onClick={() => void toggleOpen()} style={{ background: 'transparent', color: '#8b949e', border: 0, padding: 0, fontSize: 12 }}>{open ? '− checklist' : '+ checklist'}</button>
    {open && <div style={{ marginTop: 8, padding: 10, border: '1px solid #303640', borderRadius: 9 }}>
      {loading ? <div style={{ color: '#8b949e', fontSize: 12 }}>Loading checklist…</div> : items.length === 0 ? <div style={{ color: '#8b949e', fontSize: 12 }}>No checklist items yet.</div> : items.map(item => <div key={item.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 0' }}>
        <input type="checkbox" checked={item.is_completed} onChange={() => void toggleItem(item)} aria-label={`Complete ${item.title}`} />
        <span style={{ flex: 1, color: item.is_completed ? '#737b86' : '#f4f4f5', textDecoration: item.is_completed ? 'line-through' : 'none', fontSize: 13 }}>{item.title}</span>
        <button type="button" onClick={() => void removeItem(item.id)} aria-label={`Delete ${item.title}`} style={{ background: 'transparent', color: '#8b949e', border: 0 }}>×</button>
      </div>)}
      <form onSubmit={event => { event.preventDefault(); void addItem() }} style={{ display: 'flex', gap: 6, marginTop: 8 }}>
        <input value={title} onChange={event => setTitle(event.target.value)} maxLength={240} placeholder="Add a checklist step" aria-label="Checklist item title" style={{ minWidth: 0, flex: 1, background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 7, padding: 7 }} />
        <button type="submit" disabled={saving || !title.trim()}>{saving ? '…' : 'Add'}</button>
      </form>
      {error && <div role="alert" style={{ color: '#ff7b72', fontSize: 12, marginTop: 6 }}>{error}</div>}
    </div>}
  </div>
}
