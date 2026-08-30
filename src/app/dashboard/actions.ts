'use server'

import { revalidatePath } from 'next/cache'
import { createTask, setTaskStatus, updateTask } from '@/lib/tasks'
import type { TaskPriority, TaskStatus } from '@/types/task'

export async function addTaskAction(input: { title: string; priority?: TaskPriority; estimated_minutes?: number | null; due_at?: string | null; scheduled_start?: string | null; scheduled_end?: string | null }) {
  const task = await createTask(input)
  revalidatePath('/dashboard')
  return task
}

export async function updateTaskAction(id: string, input: { title: string; priority: TaskPriority; estimated_minutes: number | null; due_at: string | null; scheduled_start: string | null; scheduled_end: string | null }) {
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
