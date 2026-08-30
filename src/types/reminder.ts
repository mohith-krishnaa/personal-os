export type ReminderChannel = 'IN_APP'

export type Reminder = {
  id: string
  user_id: string
  task_id: string
  remind_at: string
  timezone: string
  channel: ReminderChannel
  enabled: boolean
  delivered_at: string | null
  created_at: string
  updated_at: string
}

export type CreateReminderInput = {
  task_id: string
  remind_at: string
  timezone?: string
  channel?: ReminderChannel
}
