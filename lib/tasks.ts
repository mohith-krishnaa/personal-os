import { createClient } from '@/lib/supabase/client'
import type { Priority, Task, TaskStatus } from '@/types/task'

const supabase = createClient()

export async function listTasks(): Promise<Task[]> {
  const { data, error } = await supabase.from('tasks').select('*').order('due_at', { ascending: true, nullsFirst: false })
  if (error) throw error
  return (data ?? []) as Task[]
}

export async function createTask(input: {
  title: string
  description?: string
  priority?: Priority
  estimated_minutes?: number
  due_at?: string
}): Promise<Task> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('You must be signed in to create a task.')

  const { data, error } = await supabase.from('tasks').insert({
    user_id: user.id,
    title: input.title,
    description: input.description ?? null,
    priority: input.priority ?? 'MEDIUM',
    estimated_minutes: input.estimated_minutes ?? null,
    due_at: input.due_at ?? null,
  }).select().single()

  if (error) throw error

  await supabase.from('activity_events').insert({
    user_id: user.id,
    event_type: 'TASK_CREATED',
    entity_type: 'TASK',
    entity_id: data.id,
  })

  return data as Task
}

export async function updateTaskStatus(id: string, status: TaskStatus): Promise<Task> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('You must be signed in.')

  const completed = status === 'COMPLETED'
  const { data, error } = await supabase.from('tasks').update({
    status,
    completed_at: completed ? new Date().toISOString() : null,
  }).eq('id', id).select().single()

  if (error) throw error

  await supabase.from('activity_events').insert({
    user_id: user.id,
    event_type: completed ? 'TASK_COMPLETED' : 'TASK_STATUS_CHANGED',
    entity_type: 'TASK',
    entity_id: id,
    metadata: { status },
  })

  return data as Task
}

export async function deleteTask(id: string): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('You must be signed in.')
  const { error } = await supabase.from('tasks').delete().eq('id', id)
  if (error) throw error
  await supabase.from('activity_events').insert({
    user_id: user.id,
    event_type: 'TASK_DELETED',
    entity_type: 'TASK',
    entity_id: id,
  })
}
