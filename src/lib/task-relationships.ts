import type { SupabaseClient } from '@supabase/supabase-js'

export type TaskOrganizationLinks = {
  projectId?: string | null
  parentTaskId?: string | null
  taskId?: string
}

/**
 * Preflight task links against the authenticated owner before a task write.
 * Database constraints/triggers remain authoritative for races and indirect cycles.
 */
export async function assertTaskOrganizationLinks(
  supabase: SupabaseClient,
  userId: string,
  links: TaskOrganizationLinks,
) {
  if (!userId) throw new Error('Unauthorized')

  const projectId = links.projectId ?? null
  const parentTaskId = links.parentTaskId ?? null

  if (parentTaskId !== null) {
    if (links.taskId && parentTaskId === links.taskId) {
      throw new Error('A task cannot be its own parent.')
    }

    const { data: parent, error: parentError } = await supabase
      .from('tasks')
      .select('id,user_id,project_id')
      .eq('id', parentTaskId)
      .eq('user_id', userId)
      .maybeSingle()

    if (parentError || !parent) throw new Error('Parent task not found.')
    if ((parent.project_id ?? null) !== projectId) {
      throw new Error('Subtask must belong to the same project as its parent.')
    }
  }

  if (projectId !== null) {
    const { data: project, error: projectError } = await supabase
      .from('projects')
      .select('id')
      .eq('id', projectId)
      .eq('user_id', userId)
      .maybeSingle()

    if (projectError || !project) throw new Error('Project not found.')
  }
}
