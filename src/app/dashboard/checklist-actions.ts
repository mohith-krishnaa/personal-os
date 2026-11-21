'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { createChecklistItem, deleteChecklistItem, listChecklistItems, setChecklistItemCompleted } from '@/lib/checklists'

async function getAuthenticatedContext() {
  const supabase = await createClient()
  const { data: { user }, error } = await supabase.auth.getUser()
  if (error || !user) throw new Error('Authentication required')
  return { supabase, user }
}

export async function listChecklistItemsAction(taskId: string) {
  const { supabase, user } = await getAuthenticatedContext()
  return listChecklistItems(supabase, user.id, taskId)
}

export async function addChecklistItemAction(taskId: string, title: string) {
  const { supabase, user } = await getAuthenticatedContext()
  const item = await createChecklistItem(supabase, user.id, taskId, title)
  revalidatePath('/dashboard')
  return item
}

export async function toggleChecklistItemAction(id: string, isCompleted: boolean) {
  const { supabase, user } = await getAuthenticatedContext()
  const item = await setChecklistItemCompleted(supabase, user.id, id, isCompleted)
  revalidatePath('/dashboard')
  return item
}

export async function removeChecklistItemAction(id: string) {
  const { supabase, user } = await getAuthenticatedContext()
  await deleteChecklistItem(supabase, user.id, id)
  revalidatePath('/dashboard')
}
