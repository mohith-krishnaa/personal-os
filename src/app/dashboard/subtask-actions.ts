'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { createSubtask } from '@/lib/subtasks'

export async function addSubtaskAction(parentTaskId: string, input: { title: string; project_id?: string | null }) {
  const supabase = await createClient()
  const { data: { user }, error } = await supabase.auth.getUser()
  if (error || !user) throw new Error('Authentication required')
  const subtask = await createSubtask(supabase, user.id, parentTaskId, input)
  revalidatePath('/dashboard')
  return subtask
}
