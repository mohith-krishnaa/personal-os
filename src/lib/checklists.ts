import type { SupabaseClient } from '@supabase/supabase-js'
import type { ChecklistItem } from '@/types/checklist'

function validateTitle(title: string) {
  const value = title.trim()
  if (!value) throw new Error('Checklist item title is required.')
  if (value.length > 240) throw new Error('Checklist item title must be 240 characters or fewer.')
  return value
}

async function assertTaskOwnership(supabase: SupabaseClient, userId: string, taskId: string) {
  const { data, error } = await supabase.from('tasks').select('id').eq('id', taskId).eq('user_id', userId).single()
  if (error || !data) throw new Error('Task not found.')
}

export async function listChecklistItems(supabase: SupabaseClient, userId: string, taskId: string) {
  await assertTaskOwnership(supabase, userId, taskId)
  const { data, error } = await supabase.from('task_checklist_items').select('*').eq('user_id', userId).eq('task_id', taskId).order('position', { ascending: true }).order('created_at', { ascending: true })
  if (error) throw error
  return (data ?? []) as ChecklistItem[]
}

export async function createChecklistItem(supabase: SupabaseClient, userId: string, taskId: string, title: string, position = 0) {
  await assertTaskOwnership(supabase, userId, taskId)
  const value = validateTitle(title)
  if (!Number.isInteger(position) || position < 0) throw new Error('Checklist position must be a non-negative integer.')
  const { data, error } = await supabase.from('task_checklist_items').insert({ user_id: userId, task_id: taskId, title: value, position }).select('*').single()
  if (error) throw error
  return data as ChecklistItem
}

export async function setChecklistItemCompleted(supabase: SupabaseClient, userId: string, id: string, isCompleted: boolean) {
  const { data, error } = await supabase.from('task_checklist_items').update({ is_completed: isCompleted, updated_at: new Date().toISOString() }).eq('id', id).eq('user_id', userId).select('*').single()
  if (error) throw error
  return data as ChecklistItem
}

export async function deleteChecklistItem(supabase: SupabaseClient, userId: string, id: string) {
  const { error } = await supabase.from('task_checklist_items').delete().eq('id', id).eq('user_id', userId)
  if (error) throw error
}
