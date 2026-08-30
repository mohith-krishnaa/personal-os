import { createClient } from '@/lib/supabase/server'
import { nextOccurrence, validateRecurrence } from '@/lib/recurrence'
import type { RecurrenceRule, Task, TaskPriority, TaskStatus } from '@/types/task'

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

type RecurrenceInput = { recurrence_rule?: RecurrenceRule | null; recurrence_until?: string | null }

function validateRecurrenceInput(input: RecurrenceInput) {
  if (input.recurrence_rule) validateRecurrence(input.recurrence_rule)
  if (input.recurrence_until && Number.isNaN(Date.parse(input.recurrence_until))) throw new Error('Recurrence end date is invalid.')
}

export async function createTask(input: { title: string; priority?: TaskPriority; estimated_minutes?: number | null; due_at?: string | null; scheduled_start?: string | null; scheduled_end?: string | null } & RecurrenceInput) {
  const supabase = await createClient(); const user = await getCurrentUser(); if (!user) throw new Error('Unauthorized')
  const title = input.title.trim(); if (!title) throw new Error('Task title is required.')
  if (input.estimated_minutes != null && (!Number.isFinite(input.estimated_minutes) || input.estimated_minutes <= 0)) throw new Error('Estimated minutes must be greater than zero.')
  if (input.scheduled_start && input.scheduled_end && input.scheduled_end <= input.scheduled_start) throw new Error('Scheduled end must be after scheduled start.')
  validateRecurrenceInput(input)
  if (input.recurrence_rule && !input.due_at) throw new Error('Recurring tasks need a due date/time to calculate the next occurrence.')
  const { data, error } = await supabase.from('tasks').insert({ user_id: user.id, title, priority: input.priority ?? 'MEDIUM', estimated_minutes: input.estimated_minutes ?? null, due_at: input.due_at ?? null, scheduled_start: input.scheduled_start ?? null, scheduled_end: input.scheduled_end ?? null, recurrence_rule: input.recurrence_rule ?? null, recurrence_until: input.recurrence_until ?? null }).select('*').single()
  if (error) throw error
  if (input.recurrence_rule) {
    const { data: linked, error: linkError } = await supabase.from('tasks').update({ recurrence_parent_id: data.id }).eq('id', data.id).eq('user_id', user.id).select('*').single()
    if (linkError) throw linkError
    data.recurrence_parent_id = linked.recurrence_parent_id
  }
  await supabase.from('activity_events').insert({ user_id: user.id, event_type: 'TASK_CREATED', entity_type: 'TASK', entity_id: data.id, metadata: { source: 'dashboard', recurring: Boolean(input.recurrence_rule) } })
  return data as Task
}

export async function updateTask(id: string, input: { title: string; priority: TaskPriority; estimated_minutes: number | null; due_at: string | null; scheduled_start: string | null; scheduled_end: string | null } & RecurrenceInput) {
  const supabase = await createClient(); const user = await getCurrentUser(); if (!user) throw new Error('Unauthorized')
  const title = input.title.trim(); if (!title) throw new Error('Task title is required.')
  if (input.estimated_minutes != null && (!Number.isFinite(input.estimated_minutes) || input.estimated_minutes <= 0)) throw new Error('Estimated minutes must be greater than zero.')
  if (input.scheduled_start && input.scheduled_end && input.scheduled_end <= input.scheduled_start) throw new Error('Scheduled end must be after scheduled start.')
  validateRecurrenceInput(input)
  if (input.recurrence_rule && !input.due_at) throw new Error('Recurring tasks need a due date/time to calculate the next occurrence.')
  const { data, error } = await supabase.from('tasks').update({ ...input, title, updated_at: new Date().toISOString() }).eq('id', id).eq('user_id', user.id).select('*').single()
  if (error) throw error
  await supabase.from('activity_events').insert({ user_id: user.id, event_type: 'TASK_UPDATED', entity_type: 'TASK', entity_id: id, metadata: { source: 'dashboard' } })
  return data as Task
}

export async function setTaskStatus(id: string, status: TaskStatus) {
  const supabase = await createClient(); const user = await getCurrentUser(); if (!user) throw new Error('Unauthorized')
  const { data: task, error: taskError } = await supabase.from('tasks').select('*').eq('id', id).eq('user_id', user.id).single()
  if (taskError) throw taskError

  const now = new Date().toISOString()
  const updateQuery = supabase.from('tasks').update({ status, completed_at: status === 'COMPLETED' ? now : null, updated_at: now }).eq('id', id).eq('user_id', user.id)
  const guardedQuery = status === 'COMPLETED' ? updateQuery.neq('status', 'COMPLETED') : updateQuery
  const { data, error } = await guardedQuery.select('*').maybeSingle()
  if (error) throw error

  // A second concurrent completion sees no row here. Return the already-completed task
  // instead of generating another recurrence occurrence.
  if (!data) {
    const { data: current, error: currentError } = await supabase.from('tasks').select('*').eq('id', id).eq('user_id', user.id).single()
    if (currentError) throw currentError
    return current as Task
  }

  if (status === 'COMPLETED' && task.recurrence_rule && task.due_at) {
    const nextDue = nextOccurrence(new Date(task.due_at), task.recurrence_rule as RecurrenceRule)
    if (!task.recurrence_until || nextDue <= new Date(task.recurrence_until)) {
      const duration = task.scheduled_start && task.scheduled_end ? new Date(task.scheduled_end).getTime() - new Date(task.scheduled_start).getTime() : null
      const nextStart = task.scheduled_start ? nextOccurrence(new Date(task.scheduled_start), task.recurrence_rule as RecurrenceRule) : null
      const nextEnd = nextStart && duration != null ? new Date(nextStart.getTime() + duration).toISOString() : null
      const { data: occurrence, error: occurrenceError } = await supabase.from('tasks').insert({ user_id: user.id, project_id: task.project_id, parent_task_id: task.parent_task_id, title: task.title, description: task.description, priority: task.priority, estimated_minutes: task.estimated_minutes, due_at: nextDue.toISOString(), scheduled_start: nextStart?.toISOString() ?? null, scheduled_end: nextEnd, recurrence_rule: task.recurrence_rule, recurrence_until: task.recurrence_until, recurrence_parent_id: task.recurrence_parent_id ?? task.id }).select('*').single()
      if (occurrenceError) throw occurrenceError
      await supabase.from('activity_events').insert({ user_id: user.id, event_type: 'TASK_RECURRENCE_GENERATED', entity_type: 'TASK', entity_id: occurrence.id, metadata: { source_task_id: task.id } })
    }
  }

  await supabase.from('activity_events').insert({ user_id: user.id, event_type: status === 'COMPLETED' ? 'TASK_COMPLETED' : 'TASK_STATUS_CHANGED', entity_type: 'TASK', entity_id: id, metadata: { status } })
  return data as Task
}
