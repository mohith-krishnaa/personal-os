import type { SupabaseClient } from '@supabase/supabase-js'
import { calculateStreak, progressPercent } from './progress'
import type { Goal, ProgressEntry, Streak } from '@/types/progress'

export async function createGoal(
  supabase: SupabaseClient,
  input: { title: string; unit: string; target: number },
) {
  if (!input.title.trim() || !input.unit.trim() || !Number.isFinite(input.target) || input.target <= 0) {
    throw new Error('Invalid goal')
  }
  const { data, error } = await supabase.from('goals').insert(input).select('*').single()
  if (error) throw error
  return data as Goal
}

export async function logProgress(
  supabase: SupabaseClient,
  input: { goalId: string; value: number; occurredOn: string },
) {
  if (!input.goalId || !Number.isFinite(input.value) || input.value <= 0 || !/^\d{4}-\d{2}-\d{2}$/.test(input.occurredOn)) {
    throw new Error('Invalid progress entry')
  }
  const { data: goal, error: goalError } = await supabase.from('goals').select('id').eq('id', input.goalId).single()
  if (goalError || !goal) throw new Error('Goal not found')
  const { data, error } = await supabase.from('progress_entries').insert({ goal_id: input.goalId, value: input.value, occurred_on: input.occurredOn }).select('*').single()
  if (error) throw error
  return data as ProgressEntry
}

export async function getGoalProgress(supabase: SupabaseClient, goalId: string): Promise<{ entries: ProgressEntry[]; total: number; percent: number; streak: Streak }> {
  const { data: goal, error: goalError } = await supabase.from('goals').select('target').eq('id', goalId).single()
  if (goalError || !goal) throw new Error('Goal not found')
  const { data, error } = await supabase.from('progress_entries').select('id, goal_id, user_id, value, occurred_on, created_at').eq('goal_id', goalId).order('occurred_on', { ascending: false })
  if (error) throw error
  const entries = (data ?? []) as ProgressEntry[]
  const total = entries.reduce((sum, entry) => sum + Number(entry.value), 0)
  return { entries, total, percent: progressPercent(total, Number(goal.target)), streak: calculateStreak(entries) }
}
