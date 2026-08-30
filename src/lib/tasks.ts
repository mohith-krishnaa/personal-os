import { createClient } from '@/lib/supabase/server'
import type { Task, TaskPriority, TaskStatus } from '@/types/task'

export async function getCurrentUser() {
  const supabase = await createClient()
  const { data, error } = await supabase.auth.getUser()
  if (error) throw error
  return data.user
}

export async function listTasks(): Promise<Task[]> {
  const supabase = await createClient()
  const user = await getCurrentUser()
  if (!user) throw new Error('Unauthorized')
  const { data, error } = await supabase.from('tasks').select('*').order('due_at', { ascending: true, nullsFirst: false }).order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as Task[]
}

export async function createTask(input: { title: string; priority?: TaskPriority; estimated_minutes?: number | null; due_at?: string | null; scheduled_start?: string | null; scheduled_end?: string | null }) {
  const supabase = await createClient(); const user = await getCurrentUser(); if (!user) throw new Error('Unauthorized')
  const title = input.title.trim(); if (!title) throw new Error('Task title is required.')
  if (input.estimated_minutes != null && (!Number.isFinite(input.estimated_minutes) || input.estimated_minutes <= 0)) throw new Error('Estimated minutes must be greater than zero.')
  if (input.scheduled_start && input.scheduled_end && input.scheduled_end <= input.scheduled_start) throw new Error('Scheduled end must be after scheduled start.')
  const { data, error } = await supabase.from('tasks').insert({ user_id: user.id, title, priority: input.priority ?? 'MEDIUM', estimated_minutes: input.estimated_minutes ?? null, due_at: input.due_at ?? null, scheduled_start: input.scheduled_start ?? null, scheduled_end: input.scheduled_end ?? null }).select('*').single()
  if (error) throw error
  await supabase.from('activity_events').insert({ user_id: user.id, event_type: 'TASK_CREATED', entity_type: 'TASK', entity_id: data.id, metadata: { source: 'dashboard' } })
  return data as Task
}

export async function updateTask(id: string, input: { title: string; priority: TaskPriority; estimated_minutes: number | null; due_at: string | null; scheduled_start: string | null; scheduled_end: string | null }) {
  const supabase = await createClient(); const user = await getCurrentUser(); if (!user) throw new Error('Unauthorized')
  const title = input.title.trim(); if (!title) throw new Error('Task title is required.')
  if (input.estimated_minutes != null && (!Number.isFinite(input.estimated_minutes) || input.estimated_minutes <= 0)) throw new Error('Estimated minutes must be greater than zero.')
  if (input.scheduled_start && input.scheduled_end && input.scheduled_end <= input.scheduled_start) throw new Error('Scheduled end must be after scheduled start.')
  const { data, error } = await supabase.from('tasks').update({ ...input, title, updated_at: new Date().toISOString() }).eq('id', id).eq('user_id', user.id).select('*').single()
  if (error) throw error
  await supabase.from('activity_events').insert({ user_id: user.id, event_type: 'TASK_UPDATED', entity_type: 'TASK', entity_id: id, metadata: { source: 'dashboard' } })
  return data as Task
}

export async function setTaskStatus(id: string, status: TaskStatus) {
  const supabase = await createClient(); const user = await getCurrentUser(); if (!user) throw new Error('Unauthorized')
  const { data, error } = await supabase.from('tasks').update({ status, completed_at: status === 'COMPLETED' ? new Date().toISOString() : null, updated_at: new Date().toISOString() }).eq('id', id).eq('user_id', user.id).select('*').single()
  if (error) throw error
  await supabase.from('activity_events').insert({ user_id: user.id, event_type: status === 'COMPLETED' ? 'TASK_COMPLETED' : 'TASK_STATUS_CHANGED', entity_type: 'TASK', entity_id: id, metadata: { status } })
  return data as Task
}
