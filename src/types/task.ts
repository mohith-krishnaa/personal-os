export type TaskStatus =
  | 'BACKLOG'
  | 'TODO'
  | 'IN_PROGRESS'
  | 'COMPLETED'
  | 'CANCELLED'

export type TaskPriority = 'LOW' | 'MEDIUM' | 'HIGH'

export type RecurrenceRule =
  | { frequency: 'DAILY'; interval: number }
  | { frequency: 'WEEKLY'; interval: number; weekdays: number[]; anchorDate: string }
  | { frequency: 'MONTHLY'; interval: number; dayOfMonth: number; anchorDayOfMonth?: number }

export type Task = {
  id: string
  user_id: string
  project_id: string | null
  parent_task_id: string | null
  recurrence_parent_id: string | null
  recurrence_rule: RecurrenceRule | null
  recurrence_until: string | null
  title: string
  description: string | null
  status: TaskStatus
  priority: TaskPriority
  due_at: string | null
  scheduled_start: string | null
  scheduled_end: string | null
  estimated_minutes: number | null
  actual_minutes: number | null
  completed_at: string | null
  created_at: string
  updated_at: string
}
