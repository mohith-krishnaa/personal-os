'use server'

import { revalidatePath } from 'next/cache'
import { createTask, setTaskStatus } from '@/lib/tasks'
import type { TaskStatus } from '@/types/task'

export async function addTaskAction(title: string) {
  const task = await createTask({ title })
  revalidatePath('/dashboard')
  return task
}

export async function toggleTaskAction(id: string, currentStatus: TaskStatus) {
  const nextStatus: TaskStatus = currentStatus === 'COMPLETED' ? 'TODO' : 'COMPLETED'
  const task = await setTaskStatus(id, nextStatus)
  revalidatePath('/dashboard')
  return task
}
