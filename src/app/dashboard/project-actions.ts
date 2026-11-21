'use server'

import { revalidatePath } from 'next/cache'
import { createProject, updateProject } from '@/lib/projects'
import { createClient } from '@/lib/supabase/server'

export async function addProjectAction(input: { name: string; description?: string | null }) {
  const supabase = await createClient()
  const project = await createProject(supabase, input)
  revalidatePath('/dashboard')
  return project
}

export async function archiveProjectAction(id: string) {
  const supabase = await createClient()
  const project = await updateProject(supabase, id, { status: 'ARCHIVED' })
  revalidatePath('/dashboard')
  return project
}
