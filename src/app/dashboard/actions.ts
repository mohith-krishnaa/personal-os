'use server'

import { revalidatePath } from 'next/cache'
import { createTask, setTaskStatus, updateTask } from '@/lib/tasks'
import type { RecurrenceRule, TaskPriority, TaskStatus } from '@/types/task'

type TaskInput = {
  title: string
  priority?: TaskPriority
  estimated_minutes?: number | null
  due_at?: string | null
  scheduled_start?: string | null
  scheduled_end?: string | null
  recurrence_rule?: RecurrenceRule | null
  recurrence_until?: string | null
}

export async function addTaskAction(input: TaskInput) {
  const task = await createTask(input)
  revalidatePath('/dashboard')
  return task
}

export async function updateTaskAction(id: string, input: TaskInput & { priority: TaskPriority; estimated_minutes: number | null; due_at: string | null; scheduled_start: string | null; scheduled_end: string | null }) {
  const task = await updateTask(id, input)
  revalidatePath('/dashboard')
  return task
}

export async function toggleTaskAction(id: string, currentStatus: TaskStatus) {
  const nextStatus: TaskStatus = currentStatus === 'COMPLETED' ? 'TODO' : 'COMPLETED'
  const task = await setTaskStatus(id, nextStatus)
  revalidatePath('/dashboard')
  return task
}
