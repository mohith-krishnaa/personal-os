import type { SupabaseClient } from '@supabase/supabase-js'

export type TaskOrganizationLinks = {
  projectId?: string | null
  parentTaskId?: string | null
  taskId?: string
}

export function canCreateTaskInProject(status: string | null | undefined) {
  return status === 'ACTIVE'
}

export function isNewProjectAssignment(
  currentProjectId: string | null,
  requestedProjectId: string | null | undefined,
) {
  return requestedProjectId !== undefined
    && requestedProjectId !== null
    && requestedProjectId !== currentProjectId
}

export function isInactiveProjectAssignmentError(error: unknown) {
  if (!error || typeof error !== 'object') return false
  const candidate = error as { code?: unknown; message?: unknown }
  return candidate.code === '23514'
    && candidate.message === 'Tasks can only be linked to active projects.'
}

/**
 * Preserve real lookup failures (especially SQLSTATE 42501) instead of
 * disguising them as an owner-scoped not-found result. PostgREST PGRST116 is
 * the expected zero-row result for the single-row subtask lookups; callers
 * still convert a missing visible row into their generic not-found message.
 */
export function throwIfUnexpectedLookupError(error: unknown) {
  if (!error) return
  if (typeof error === 'object' && 'code' in error && error.code === 'PGRST116') return
  throw error
}

export function resolveTaskOrganizationLinks(
  current: { project_id: string | null; parent_task_id: string | null },
  patch: { project_id?: string | null; parent_task_id?: string | null },
) {
  return {
    projectId: patch.project_id !== undefined ? patch.project_id : current.project_id,
    parentTaskId: patch.parent_task_id !== undefined ? patch.parent_task_id : current.parent_task_id,
  }
}

/**
 * Preflight task links against the authenticated owner before a task write.
 * The database trigger remains authoritative for races and direct PostgREST writes.
 */
export async function assertTaskOrganizationLinks(
  supabase: SupabaseClient,
  userId: string,
  links: TaskOrganizationLinks,
  options: { requireActiveProject?: boolean } = {},
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

    throwIfUnexpectedLookupError(parentError)
    if (!parent) throw new Error('Parent task not found.')
    if ((parent.project_id ?? null) !== projectId) {
      throw new Error('Subtask must belong to the same project as its parent.')
    }
  }

  if (projectId !== null) {
    if (options.requireActiveProject) {
      const { data: project, error: projectError } = await supabase
        .from('projects')
        .select('id,status')
        .eq('id', projectId)
        .eq('user_id', userId)
        .maybeSingle()

      throwIfUnexpectedLookupError(projectError)
      if (!project) throw new Error('Project not found.')
      if (!canCreateTaskInProject(project.status)) {
        throw new Error('Tasks can only be linked to active projects.')
      }
    } else {
      const { data: project, error: projectError } = await supabase
        .from('projects')
        .select('id')
        .eq('id', projectId)
        .eq('user_id', userId)
        .maybeSingle()

      throwIfUnexpectedLookupError(projectError)
      if (!project) throw new Error('Project not found.')
    }
  }
}
