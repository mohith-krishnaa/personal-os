export type TaskStatus = 'BACKLOG' | 'TODO' | 'IN_PROGRESS' | 'COMPLETED' | 'CANCELLED'
export type Priority = 'LOW' | 'MEDIUM' | 'HIGH'

export interface Task {
  id: string
  user_id: string
  project_id: string | null
  parent_task_id: string | null
  title: string
  description: string | null
  status: TaskStatus
  priority: Priority
  due_at: string | null
  scheduled_start: string | null
  scheduled_end: string | null
  estimated_minutes: number | null
  actual_minutes: number | null
  completed_at: string | null
  created_at: string
  updated_at: string
}
