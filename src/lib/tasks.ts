import { createClient } from '@/lib/supabase/server'
import { nextOccurrence, validateRecurrence } from '@/lib/recurrence'
import type { RecurrenceRule, Task, TaskPriority, TaskStatus } from '@/types/task'
import { listTasksForUser } from './task-queries'
import { assertTaskOrganizationLinks, canCreateTaskInProject, isInactiveProjectAssignmentError, isNewProjectAssignment, resolveTaskOrganizationLinks } from './task-relationships'

export async function getCurrentUser() {
  const supabase = await createClient()
  const { data, error } = await supabase.auth.getUser()
  if (error) throw error
  return data.user
}

export async function listTasks(projectId?: string | null): Promise<Task[]> {
  const supabase = await createClient()
  const { data, error } = await supabase.auth.getUser()
  if (error) throw error
  if (!data.user) throw new Error('Unauthorized')
  return listTasksForUser(supabase, data.user.id, projectId)
}

type RecurrenceInput = { recurrence_rule?: RecurrenceRule | null; recurrence_until?: string | null }
function validateRecurrenceInput(input: RecurrenceInput) {
  if (input.recurrence_rule) validateRecurrence(input.recurrence_rule)
  if (input.recurrence_until && Number.isNaN(Date.parse(input.recurrence_until))) throw new Error('Recurrence end date is invalid.')
}

export async function createTask(input: { title: string; priority?: TaskPriority; estimated_minutes?: number | null; due_at?: string | null; scheduled_start?: string | null; scheduled_end?: string | null; project_id?: string | null; parent_task_id?: string | null } & RecurrenceInput) {
  const supabase = await createClient()
  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  const user = userData.user
  if (!user) throw new Error('Unauthorized')
  const title = input.title.trim(); if (!title) throw new Error('Task title is required.')
  if (input.estimated_minutes != null && (!Number.isFinite(input.estimated_minutes) || input.estimated_minutes <= 0)) throw new Error('Estimated minutes must be greater than zero.')
  if (input.scheduled_start && input.scheduled_end && input.scheduled_end <= input.scheduled_start) throw new Error('Scheduled end must be after scheduled start.')
  validateRecurrenceInput(input)
  if (input.recurrence_rule && !input.due_at) throw new Error('Recurring tasks need a due date/time to calculate the next occurrence.')
  await assertTaskOrganizationLinks(supabase, user.id, {
    projectId: input.project_id ?? null,
    parentTaskId: input.parent_task_id ?? null,
  }, { requireActiveProject: true })
  const { data, error } = await supabase.from('tasks').insert({ user_id: user.id, project_id: input.project_id ?? null, parent_task_id: input.parent_task_id ?? null, title, priority: input.priority ?? 'MEDIUM', estimated_minutes: input.estimated_minutes ?? null, due_at: input.due_at ?? null, scheduled_start: input.scheduled_start ?? null, scheduled_end: input.scheduled_end ?? null, recurrence_rule: input.recurrence_rule ?? null, recurrence_until: input.recurrence_until ?? null }).select('*').single()
  if (error) throw error
  if (input.recurrence_rule) {
    const { data: linked, error: linkError } = await supabase.from('tasks').update({ recurrence_parent_id: data.id }).eq('id', data.id).eq('user_id', user.id).select('*').single()
    if (linkError) throw linkError
    data.recurrence_parent_id = linked.recurrence_parent_id
  }
  return data as Task
}

export type UpdateTaskInput = {
  title: string
  priority: TaskPriority
  estimated_minutes: number | null
  due_at: string | null
  scheduled_start: string | null
  scheduled_end: string | null
  project_id?: string | null
  parent_task_id?: string | null
  recurrence_rule?: RecurrenceRule | null
  recurrence_until?: string | null
}

export async function updateTaskForUser(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string,
  id: string,
  input: UpdateTaskInput,
) {
  if (!userId) throw new Error('Unauthorized')
  const title = input.title.trim(); if (!title) throw new Error('Task title is required.')
  if (input.estimated_minutes != null && (!Number.isFinite(input.estimated_minutes) || input.estimated_minutes <= 0)) throw new Error('Estimated minutes must be greater than zero.')
  if (input.scheduled_start && input.scheduled_end && input.scheduled_end <= input.scheduled_start) throw new Error('Scheduled end must be after scheduled start.')
  validateRecurrenceInput(input)
  if (input.recurrence_rule && !input.due_at) throw new Error('Recurring tasks need a due date/time to calculate the next occurrence.')
  if (input.project_id !== undefined || input.parent_task_id !== undefined) {
    const { data: currentTask, error: currentTaskError } = await supabase
      .from('tasks')
      .select('project_id,parent_task_id')
      .eq('id', id)
      .eq('user_id', userId)
      .single()
    if (currentTaskError) throw currentTaskError
    const links = resolveTaskOrganizationLinks(currentTask, input)
    await assertTaskOrganizationLinks(supabase, userId, { ...links, taskId: id }, {
      requireActiveProject: isNewProjectAssignment(currentTask.project_id, input.project_id),
    })
  }
  // Build an explicit update allowlist. Server-action arguments are runtime input;
  // spreading them could let extra properties overwrite protected task columns.
  const patch: Record<string, unknown> = {
    title,
    priority: input.priority,
    estimated_minutes: input.estimated_minutes,
    due_at: input.due_at,
    scheduled_start: input.scheduled_start,
    scheduled_end: input.scheduled_end,
    recurrence_rule: input.recurrence_rule ?? null,
    recurrence_until: input.recurrence_until ?? null,
    updated_at: new Date().toISOString(),
  }
  if (input.project_id !== undefined) patch.project_id = input.project_id
  if (input.parent_task_id !== undefined) patch.parent_task_id = input.parent_task_id
  const { data, error } = await supabase.from('tasks').update(patch).eq('id', id).eq('user_id', userId).select('*').single()
  if (error) throw error
  return data as Task
}

export async function updateTask(id: string, input: UpdateTaskInput) {
  const supabase = await createClient()
  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  const user = userData.user
  if (!user) throw new Error('Unauthorized')
  return updateTaskForUser(supabase, user.id, id, input)
}

async function getExistingOccurrence(supabase: Awaited<ReturnType<typeof createClient>>, userId: string, parentId: string, dueAt: string) {
  const { data, error } = await supabase.from('tasks').select('*').eq('user_id', userId).eq('recurrence_parent_id', parentId).eq('due_at', dueAt).limit(1).maybeSingle()
  if (error) throw error
  return data as Task | null
}

export async function setTaskStatusForUser(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string,
  id: string,
  status: TaskStatus,
) {
  if (!userId) throw new Error('Unauthorized')
  const { data: task, error: taskError } = await supabase.from('tasks').select('*').eq('id', id).eq('user_id', userId).single()
  if (taskError) throw taskError
  if (!task) throw new Error('Task not found.')

  const now = new Date().toISOString()
  const updateQuery = supabase.from('tasks').update({ status, completed_at: status === 'COMPLETED' ? now : null, updated_at: now }).eq('id', id).eq('user_id', userId)
  const guardedQuery = status === 'COMPLETED' ? updateQuery.neq('status', 'COMPLETED') : updateQuery
  const { data, error } = await guardedQuery.select('*').maybeSingle()
  if (error) throw error

  // A repeated COMPLETED request must still retry occurrence generation if the
  // prior occurrence INSERT rolled back with its activity event.
  let currentTask = data as Task | null
  if (!currentTask) {
    const { data: current, error: currentError } = await supabase.from('tasks').select('*').eq('id', id).eq('user_id', userId).single()
    if (currentError) throw currentError
    currentTask = current as Task
  }

  if (status === 'COMPLETED' && currentTask.recurrence_rule && currentTask.due_at) {
    let projectCanReceiveTasks = !currentTask.project_id
    if (currentTask.project_id) {
      const { data: project, error: projectError } = await supabase
        .from('projects')
        .select('status')
        .eq('id', currentTask.project_id)
        .eq('user_id', userId)
        .maybeSingle()
      if (projectError) throw projectError
      projectCanReceiveTasks = canCreateTaskInProject(project?.status)
    }

    // Archiving/completing a project preserves existing tasks but ends automatic
    // recurrence creation for that project.
    if (projectCanReceiveTasks) {
      const nextDue = nextOccurrence(new Date(currentTask.due_at), currentTask.recurrence_rule as RecurrenceRule)
      if (!currentTask.recurrence_until || nextDue <= new Date(currentTask.recurrence_until)) {
        const duration = currentTask.scheduled_start && currentTask.scheduled_end ? new Date(currentTask.scheduled_end).getTime() - new Date(currentTask.scheduled_start).getTime() : null
        const nextStart = currentTask.scheduled_start ? nextOccurrence(new Date(currentTask.scheduled_start), currentTask.recurrence_rule as RecurrenceRule) : null
        const nextEnd = nextStart && duration != null ? new Date(nextStart.getTime() + duration).toISOString() : null
        const nextParentId = currentTask.recurrence_parent_id ?? currentTask.id
        const { error: occurrenceError } = await supabase.from('tasks').insert({
          user_id: userId,
          project_id: currentTask.project_id,
          parent_task_id: currentTask.parent_task_id,
          title: currentTask.title,
          description: currentTask.description,
          priority: currentTask.priority,
          estimated_minutes: currentTask.estimated_minutes,
          due_at: nextDue.toISOString(),
          scheduled_start: nextStart?.toISOString() ?? null,
          scheduled_end: nextEnd,
          recurrence_rule: currentTask.recurrence_rule,
          recurrence_until: currentTask.recurrence_until,
          recurrence_parent_id: nextParentId,
        }).select('*').single()
        if (occurrenceError) {
          if (isInactiveProjectAssignmentError(occurrenceError)) {
            // A concurrent project archive/completion won the race after the read.
            // The task is already completed; intentionally stop the recurrence.
          } else if (occurrenceError.code !== '23505') {
            throw occurrenceError
          } else {
            const existing = await getExistingOccurrence(supabase, userId, nextParentId, nextDue.toISOString())
            if (!existing) throw occurrenceError
          }
        }
      }
    }
  }
  return currentTask
}

export async function setTaskStatus(id: string, status: TaskStatus) {
  const supabase = await createClient()
  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  const user = userData.user
  if (!user) throw new Error('Unauthorized')
  return setTaskStatusForUser(supabase, user.id, id, status)
}
