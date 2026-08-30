export type Goal = {
  id: string
  user_id: string
  title: string
  unit: string
  target: number
  created_at: string
  updated_at: string
}

export type ProgressEntry = {
  id?: string
  goal_id?: string
  user_id?: string
  value: number
  occurred_on: string
  created_at?: string
}

export type Streak = {
  current: number
  longest: number
  last_active_on: string | null
}
