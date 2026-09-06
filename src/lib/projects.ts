import type { SupabaseClient } from '@supabase/supabase-js'
import type { Project, ProjectStatus } from '@/types/project'
import { validateProjectName } from './project-validation'

export async function listProjects(supabase: SupabaseClient, status?: ProjectStatus) {
  let query = supabase.from('projects').select('id,user_id,name,description,status,created_at,updated_at').order('created_at', { ascending: false })
  if (status) query = query.eq('status', status)
  const { data, error } = await query
  if (error) throw error
  return (data ?? []) as Project[]
}

export async function createProject(supabase: SupabaseClient, input: { name: string; description?: string | null }) {
  const validation = validateProjectName(input.name)
  if (validation) throw new Error(validation)
  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError || !userData.user) throw new Error('Authentication required')
  const { data, error } = await supabase.from('projects').insert({ user_id: userData.user.id, name: input.name.trim(), description: input.description?.trim() || null }).select('*').single()
  if (error) throw error
  return data as Project
}

export async function updateProject(supabase: SupabaseClient, id: string, input: { name?: string; description?: string | null; status?: ProjectStatus }) {
  if (!id) throw new Error('Project id is required')
  if (input.name !== undefined) {
    const validation = validateProjectName(input.name)
    if (validation) throw new Error(validation)
  }
  const patch: Record<string, unknown> = {}
  if (input.name !== undefined) patch.name = input.name.trim()
  if (input.description !== undefined) patch.description = input.description?.trim() || null
  if (input.status !== undefined) patch.status = input.status
  if (!Object.keys(patch).length) throw new Error('No project changes supplied')
  patch.updated_at = new Date().toISOString()
  const { data, error } = await supabase.from('projects').update(patch).eq('id', id).select('*').single()
  if (error) throw error
  return data as Project
}
