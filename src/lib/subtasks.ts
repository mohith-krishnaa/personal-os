import type { SupabaseClient } from '@supabase/supabase-js'
import type { Task } from '@/types/task'

export type SubtaskInput = {
  title: string
  project_id?: string | null
  priority?: Task['priority']
  due_at?: string | null
  estimated_minutes?: number | null
}

function assertValidTitle(title: string) {
  const value = title.trim()
  if (!value) throw new Error('Subtask title is required.')
  return value
}

async function assertParentOwnership(supabase: SupabaseClient, userId: string, parentTaskId: string) {
  const { data: parent, error } = await supabase.from('tasks').select('id,user_id,project_id').eq('id', parentTaskId).eq('user_id', userId).single()
  if (error || !parent) throw new Error('Parent task not found.')
  return parent as Pick<Task, 'id' | 'user_id' | 'project_id'>
}

async function assertProjectOwnership(supabase: SupabaseClient, userId: string, projectId: string | null | undefined) {
  if (!projectId) return
  const { data, error } = await supabase.from('projects').select('id').eq('id', projectId).eq('user_id', userId).single()
  if (error || !data) throw new Error('Project not found.')
}

export async function createSubtask(supabase: SupabaseClient, userId: string, parentTaskId: string, input: SubtaskInput) {
  if (!parentTaskId) throw new Error('Parent task is required.')
  const parent = await assertParentOwnership(supabase, userId, parentTaskId)
  const projectId = input.project_id ?? parent.project_id
  await assertProjectOwnership(supabase, userId, projectId)
  const title = assertValidTitle(input.title)
  if (input.estimated_minutes != null && (!Number.isFinite(input.estimated_minutes) || input.estimated_minutes <= 0)) throw new Error('Estimated minutes must be greater than zero.')

  const { data, error } = await supabase.from('tasks').insert({
    user_id: userId,
    parent_task_id: parentTaskId,
    project_id: projectId,
    title,
    priority: input.priority ?? 'MEDIUM',
    due_at: input.due_at ?? null,
    estimated_minutes: input.estimated_minutes ?? null,
  }).select('*').single()
  if (error) throw error
  return data as Task
}

export async function listSubtasks(supabase: SupabaseClient, userId: string, parentTaskId: string) {
  await assertParentOwnership(supabase, userId, parentTaskId)
  const { data, error } = await supabase.from('tasks').select('*').eq('user_id', userId).eq('parent_task_id', parentTaskId).order('created_at', { ascending: true })
  if (error) throw error
  return (data ?? []) as Task[]
}
