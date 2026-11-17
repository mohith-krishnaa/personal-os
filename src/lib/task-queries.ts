import type { SupabaseClient } from '@supabase/supabase-js'
import type { Task } from '@/types/task'

export async function listTasksForUser(
  supabase: SupabaseClient,
  userId: string,
  projectId?: string | null,
): Promise<Task[]> {
  if (!userId) throw new Error('Unauthorized')

  let query = supabase.from('tasks').select('*').eq('user_id', userId)
  if (projectId) query = query.eq('project_id', projectId)

  const { data, error } = await query
    .order('due_at', { ascending: true, nullsFirst: false })
    .order('created_at', { ascending: false })

  if (error) throw error
  return (data ?? []) as Task[]
}
