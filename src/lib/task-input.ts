import type { TaskPriority } from '@/types/task'

export type CreateTaskInput = {
  title: string
  priority?: TaskPriority
  estimated_minutes?: number | null
  due_at?: string | null
  scheduled_start?: string | null
  scheduled_end?: string | null
}

export function normalizeTaskInput(input: CreateTaskInput): CreateTaskInput {
  const title = input.title.trim()
  if (!title) throw new Error('Task title is required.')
  if (input.estimated_minutes != null && (!Number.isFinite(input.estimated_minutes) || input.estimated_minutes <= 0)) {
    throw new Error('Estimated minutes must be greater than zero.')
  }
  if (input.scheduled_start && input.scheduled_end && input.scheduled_end <= input.scheduled_start) {
    throw new Error('Scheduled end must be after scheduled start.')
  }
  return { ...input, title }
}
