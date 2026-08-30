import { createClient } from '@/lib/supabase/server'
import type { CreateReminderInput, Reminder } from '@/types/reminder'
import { getCurrentUser } from '@/lib/tasks'

export function validateReminderInput(input: CreateReminderInput) {
  if (!input.task_id) throw new Error('Task is required.')
  if (Number.isNaN(Date.parse(input.remind_at))) throw new Error('Reminder time is invalid.')
  if (new Date(input.remind_at).getTime() <= Date.now()) throw new Error('Reminder time must be in the future.')
  if (input.timezone && input.timezone.trim().length > 100) throw new Error('Timezone is invalid.')
  if (input.channel && input.channel !== 'IN_APP') throw new Error('Unsupported reminder channel.')
}

export async function createReminder(input: CreateReminderInput): Promise<Reminder> {
  validateReminderInput(input)
  const supabase = await createClient()
  const user = await getCurrentUser()
  if (!user) throw new Error('Unauthorized')

  const { data: task, error: taskError } = await supabase
    .from('tasks')
    .select('id')
    .eq('id', input.task_id)
    .eq('user_id', user.id)
    .single()
  if (taskError) throw taskError

  const { data, error } = await supabase
    .from('reminders')
    .insert({
      user_id: user.id,
      task_id: task.id,
      remind_at: new Date(input.remind_at).toISOString(),
      timezone: input.timezone?.trim() || 'UTC',
      channel: input.channel || 'IN_APP',
    })
    .select('*')
    .single()
  if (error) throw error
  return data as Reminder
}

export async function listUpcomingReminders(): Promise<Reminder[]> {
  const supabase = await createClient()
  const user = await getCurrentUser()
  if (!user) throw new Error('Unauthorized')
  const { data, error } = await supabase
    .from('reminders')
    .select('*')
    .eq('user_id', user.id)
    .eq('enabled', true)
    .is('delivered_at', null)
    .gte('remind_at', new Date().toISOString())
    .order('remind_at', { ascending: true })
    .limit(100)
  if (error) throw error
  return (data ?? []) as Reminder[]
}
