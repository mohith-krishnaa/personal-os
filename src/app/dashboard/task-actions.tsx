'use client'

import { useId, useRef, useState } from 'react'
import type { Task } from '@/types/task'
import { addTaskAction, toggleTaskAction } from './actions'
import {
  completeClientRequestState,
  getClientRequestState,
  getClientRequestStorage,
  type PendingClientRequest,
} from '@/lib/client-request-id'

export default function TaskActions({ mode, task }: { mode: 'add' | 'toggle'; task?: Task }) {
  const requestRef = useRef<PendingClientRequest>(null)
  const requestStorageKey = 'personal-os:task-create:' + useId()
  const [title, setTitle] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function addTask() {
    const value = title.trim()
    if (!value || loading) return
    const payload = { title: value }
    const storage = getClientRequestStorage()
    const request = await getClientRequestState(
      requestRef.current,
      payload,
      () => globalThis.crypto.randomUUID(),
      storage,
      requestStorageKey,
    )
    requestRef.current = request
    setLoading(true)
    setError('')
    try {
      await addTaskAction({ ...payload, client_request_id: request.id })
      completeClientRequestState(request, storage, requestStorageKey)
      requestRef.current = null
      setTitle('')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not add task.')
    } finally {
      setLoading(false)
    }
  }

  async function toggleTask() {
    if (!task) return
    setLoading(true)
    setError('')
    try {
      await toggleTaskAction(task.id, task.status)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not update task.')
    } finally {
      setLoading(false)
    }
  }

  if (mode === 'toggle') return (
    <div>
      <button aria-label={task?.status === 'COMPLETED' ? 'Mark incomplete' : 'Mark complete'} disabled={loading} onClick={() => void toggleTask()} style={{ width: 30, height: 30, borderRadius: 9, border: '1px solid #3a404a', background: 'transparent', color: '#f4f4f5' }}>
        {loading ? '…' : task?.status === 'COMPLETED' ? '✓' : '○'}
      </button>
      {error && <span role="alert" style={{ display: 'block', color: '#ff7b72', fontSize: 12 }}>{error}</span>}
    </div>
  )

  return (
    <div>
      <form onSubmit={(event) => { event.preventDefault(); void addTask() }} style={{ display: 'flex', gap: 8 }}>
        <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="New task…" aria-label="New task" style={{ width: 210, background: '#111419', color: '#f4f4f5', border: '1px solid #24282f', borderRadius: 10, padding: '10px 12px' }} />
        <button disabled={loading || !title.trim()} style={{ background: '#f4f4f5', color: '#090a0c', border: 0, borderRadius: 10, padding: '10px 14px', fontWeight: 600 }}>{loading ? '…' : 'Add'}</button>
      </form>
      {error && <p role="alert" style={{ color: '#ff7b72', fontSize: 12 }}>{error}</p>}
    </div>
  )
}
