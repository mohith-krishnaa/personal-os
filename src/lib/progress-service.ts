import type { SupabaseClient } from '@supabase/supabase-js'
import { calculateStreak, progressPercent } from './progress'
import type { Goal, ProgressEntry, Streak } from '@/types/progress'

export async function createGoal(supabase: SupabaseClient, userId: string, input: { title: string; unit: string; target: number }) {
  if (!userId || !input.title.trim() || !input.unit.trim() || !Number.isFinite(input.target) || input.target <= 0) throw new Error('Invalid goal')
  const { data, error } = await supabase.from('goals').insert({ ...input, user_id: userId }).select('*').single()
  if (error) throw error
  return data as Goal
}

export async function logProgress(supabase: SupabaseClient, userId: string, input: { goalId: string; value: number; occurredOn: string }) {
  if (!userId || !input.goalId || !Number.isFinite(input.value) || input.value <= 0 || !/^\d{4}-\d{2}-\d{2}$/.test(input.occurredOn)) throw new Error('Invalid progress entry')
  const { data, error } = await supabase.from('progress_entries').insert({ goal_id: input.goalId, user_id: userId, value: input.value, occurred_on: input.occurredOn }).select('*').single()
  if (error) throw error
  return data as ProgressEntry
}

export function summarizeGoalProgress(goal: Pick<Goal, 'target'>, entries: ProgressEntry[]) {
  const total = entries.reduce((sum, entry) => sum + Number(entry.value), 0)
  return { entries, total, percent: progressPercent(total, Number(goal.target)), streak: calculateStreak(entries) }
}

export async function getGoalsWithProgress(supabase: SupabaseClient) {
  const { data: goals, error: goalsError } = await supabase.from('goals').select('id, user_id, title, unit, target, created_at, updated_at').order('created_at', { ascending: false })
  if (goalsError) throw goalsError
  if (!goals?.length) return []
  const { data: entries, error: entriesError } = await supabase.from('progress_entries').select('id, goal_id, user_id, value, occurred_on, created_at').in('goal_id', goals.map(goal => goal.id)).order('occurred_on', { ascending: false })
  if (entriesError) throw entriesError
  const grouped = new Map<string, ProgressEntry[]>()
  for (const entry of (entries ?? []) as ProgressEntry[]) grouped.set(entry.goal_id!, [...(grouped.get(entry.goal_id!) ?? []), entry])
  return goals.map(goal => ({ goal: goal as Goal, progress: summarizeGoalProgress(goal, grouped.get(goal.id) ?? []) }))
}
