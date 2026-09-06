'use client'

import { useState } from 'react'
import { addProjectAction, archiveProjectAction } from './project-actions'
import type { Project } from '@/types/project'

export default function ProjectManager({ projects }: { projects: Project[] }) {
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)

  async function create() {
    setError(''); setSaving(true)
    try {
      await addProjectAction({ name, description })
      setName(''); setDescription('')
    } catch (err) { setError(err instanceof Error ? err.message : 'Could not create project.') }
    finally { setSaving(false) }
  }

  async function archive(id: string) {
    setError('')
    try { await archiveProjectAction(id) }
    catch (err) { setError(err instanceof Error ? err.message : 'Could not archive project.') }
  }

  return <section style={{ marginTop: 18, border: '1px solid #24282f', borderRadius: 16, background: '#111419', padding: 22 }}>
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, alignItems: 'center' }}><h2 style={{ margin: 0 }}>Projects</h2><span style={{ color: '#8b949e' }}>{projects.filter(p => p.status === 'ACTIVE').length} active</span></div>
    <div style={{ display: 'grid', gap: 8, marginTop: 16 }}><input value={name} onChange={e => setName(e.target.value)} placeholder="Project name" aria-label="Project name" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 10 }} /><input value={description} onChange={e => setDescription(e.target.value)} placeholder="Description (optional)" aria-label="Project description" style={{ background: '#0b0d10', color: '#f4f4f5', border: '1px solid #303640', borderRadius: 9, padding: 10 }} /><button type="button" disabled={saving || !name.trim()} onClick={() => void create()} style={{ justifySelf: 'start', background: '#f4f4f5', color: '#090a0c', border: 0, borderRadius: 9, padding: '9px 13px', fontWeight: 700 }}>{saving ? 'Creating…' : 'Create project'}</button></div>
    {error && <div role="alert" style={{ color: '#ff7b72', fontSize: 13, marginTop: 10 }}>{error}</div>}
    <div style={{ marginTop: 16 }}>{projects.filter(p => p.status === 'ACTIVE').map(project => <div key={project.id} style={{ display: 'flex', justifyContent: 'space-between', gap: 12, padding: '12px 0', borderTop: '1px solid #24282f' }}><div><strong>{project.name}</strong>{project.description && <div style={{ color: '#8b949e', marginTop: 3 }}>{project.description}</div>}</div><button type="button" onClick={() => void archive(project.id)} style={{ background: 'transparent', color: '#8b949e', border: '1px solid #303640', borderRadius: 9, padding: '7px 10px' }}>Archive</button></div>)}</div>
  </section>
}
