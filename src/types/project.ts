export type ProjectStatus = 'ACTIVE' | 'COMPLETED' | 'ARCHIVED'
export type ProjectStatusUpdate = Exclude<ProjectStatus, 'COMPLETED'>

export type Project = {
  id: string
  user_id: string
  name: string
  description: string | null
  status: ProjectStatus
  created_at: string
  updated_at: string
}
