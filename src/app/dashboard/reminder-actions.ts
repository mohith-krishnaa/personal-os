'use server'

import { revalidatePath } from 'next/cache'
import { createReminder } from '@/lib/reminders'
import type { CreateReminderInput } from '@/types/reminder'

export async function createReminderAction(input: CreateReminderInput) {
  const reminder = await createReminder(input)
  revalidatePath('/dashboard')
  return reminder
}
