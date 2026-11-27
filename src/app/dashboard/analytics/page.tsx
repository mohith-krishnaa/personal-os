import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { buildAnalyticsReview, getAnalyticsInsights, getReviewBounds, type AnalyticsTask, type ReviewPeriod } from '@/lib/analytics'
import type { CSSProperties } from 'react'

export const dynamic = 'force-dynamic'

function minutes(value: number) {
  const hours = Math.floor(value / 60)
  const remainder = value % 60
  return hours ? `${hours}h ${remainder}m` : `${remainder}m`
}

function cardStyle(): CSSProperties {
  return { border: '1px solid #24282f', borderRadius: 16, background: '#111419', padding: 22 }
}

export default async function AnalyticsPage({ searchParams }: { searchParams?: Promise<{ period?: string }> }) {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY) redirect('/login')
  const period: ReviewPeriod = (await searchParams)?.period === 'month' ? 'month' : 'week'
  const bounds = getReviewBounds(period)
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [completedResult, createdResult, progressResult, goalsResult] = await Promise.all([
    supabase.from('tasks').select('id,status,estimated_minutes,actual_minutes,completed_at,created_at')
      .eq('status', 'COMPLETED').gte('completed_at', bounds.previousStart.toISOString()).lt('completed_at', bounds.end.toISOString()),
    supabase.from('tasks').select('id,created_at')
      .gte('created_at', bounds.previousStart.toISOString()).lt('created_at', bounds.end.toISOString()),
    supabase.from('progress_entries').select('goal_id,value,occurred_on')
      .gte('occurred_on', bounds.previousStart.toISOString().slice(0, 10)).lt('occurred_on', bounds.end.toISOString().slice(0, 10)),
    supabase.from('goals').select('id,title,unit'),
  ])
  if (completedResult.error) throw completedResult.error
  if (createdResult.error) throw createdResult.error
  if (progressResult.error) throw progressResult.error
  if (goalsResult.error) throw goalsResult.error

  const tasksById = new Map<string, AnalyticsTask>()
  for (const task of createdResult.data ?? []) {
    tasksById.set(task.id, { id: task.id, status: 'TODO', estimated_minutes: null, actual_minutes: null, completed_at: null, created_at: task.created_at })
  }
  for (const task of completedResult.data ?? []) {
    tasksById.set(task.id, task as AnalyticsTask)
  }
  const goalsById = new Map((goalsResult.data ?? []).map(goal => [goal.id, goal]))
  const progressEntries = (progressResult.data ?? []).flatMap(entry => {
    const goal = goalsById.get(entry.goal_id)
    return goal ? [{ ...entry, goal_id: entry.goal_id, goal_title: goal.title, unit: goal.unit, value: Number(entry.value) }] : []
  })
  const review = buildAnalyticsReview([...tasksById.values()], progressEntries, bounds)
  const insights = getAnalyticsInsights(review)
  const peak = Math.max(1, ...review.buckets.map(bucket => bucket.completed))
  const periodLabel = period === 'week' ? 'This week' : 'This month'

  return <main style={{ maxWidth: 1100, margin: '0 auto', padding: '40px 20px', color: '#f4f4f5' }}>
    <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 20, marginBottom: 24 }}>
      <div><Link href="/dashboard" style={{ color: '#8b949e', textDecoration: 'none' }}>← Dashboard</Link><div style={{ color: '#8b949e', fontSize: 13, letterSpacing: 1, marginTop: 12 }}>PERSONAL OS · REVIEW</div><h1 style={{ margin: '8px 0 4px', fontSize: 34 }}>Analytics</h1><p style={{ color: '#8b949e', margin: 0 }}>{review.start} – {review.end} · Dates use UTC</p></div>
      <nav aria-label="Review period" style={{ display: 'flex', gap: 8 }}><Link href="/dashboard/analytics?period=week" aria-current={period === 'week' ? 'page' : undefined} style={{ border: '1px solid #303640', borderRadius: 9, padding: '9px 13px', color: '#f4f4f5', textDecoration: 'none', background: period === 'week' ? '#303640' : 'transparent' }}>Week</Link><Link href="/dashboard/analytics?period=month" aria-current={period === 'month' ? 'page' : undefined} style={{ border: '1px solid #303640', borderRadius: 9, padding: '9px 13px', color: '#f4f4f5', textDecoration: 'none', background: period === 'month' ? '#303640' : 'transparent' }}>Month</Link></nav>
    </header>

    <section aria-label={`${periodLabel} summary`} style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(180px,1fr))', gap: 14 }}>
      <article style={cardStyle()}><div style={{ color: '#8b949e' }}>Tasks completed</div><strong style={{ display: 'block', fontSize: 32, marginTop: 10 }}>{review.completed}</strong><small style={{ color: '#8b949e' }}>Previous period: {review.previousCompleted}</small></article>
      <article style={cardStyle()}><div style={{ color: '#8b949e' }}>Tasks created</div><strong style={{ display: 'block', fontSize: 32, marginTop: 10 }}>{review.created}</strong><small style={{ color: '#8b949e' }}>Previous period: {review.previousCreated}</small></article>
      <article style={cardStyle()}><div style={{ color: '#8b949e' }}>Goal progress entries</div><strong style={{ display: 'block', fontSize: 32, marginTop: 10 }}>{review.progress}</strong><small style={{ color: '#8b949e' }}>Previous period: {review.previousProgress}</small></article>
      <article style={cardStyle()}><div style={{ color: '#8b949e' }}>Planned · actual</div><strong style={{ display: 'block', fontSize: 25, marginTop: 14 }}>{minutes(review.plannedMinutes)} · {minutes(review.actualMinutes)}</strong><small style={{ color: '#8b949e' }}>Actual time on {review.trackedTasks} estimated task{review.trackedTasks === 1 ? '' : 's'}</small></article>
    </section>

    <section style={{ ...cardStyle(), marginTop: 16 }}><h2 style={{ marginTop: 0 }}>{periodLabel} activity</h2><div style={{ overflowX: 'auto' }}><div style={{ display: 'grid', gridTemplateColumns: `repeat(${review.buckets.length}, minmax(38px, 1fr))`, minWidth: period === 'month' ? 860 : undefined, gap: 8, alignItems: 'end' }}>
      {review.buckets.map(bucket => <div key={bucket.date} style={{ textAlign: 'center' }}><div aria-label={`${bucket.completed} tasks completed on ${bucket.date}`} title={`${bucket.completed} tasks completed`} style={{ height: 130, display: 'flex', alignItems: 'end', justifyContent: 'center', background: '#0b0d10', borderRadius: 8, padding: 8 }}><div style={{ width: '100%', height: `${Math.max(bucket.completed ? 8 : 0, bucket.completed / peak * 100)}%`, borderRadius: 5, background: '#7dd3fc', minHeight: bucket.completed ? 8 : 0 }} /></div><small style={{ display: 'block', color: '#8b949e', marginTop: 7 }}>{bucket.label}</small><small>{bucket.completed} · {bucket.progress}</small></div>)}
    </div></div><p style={{ color: '#8b949e', marginBottom: 0 }}>Each day shows completed tasks · goal progress entries.</p></section>

    <section style={{ ...cardStyle(), marginTop: 16 }}><h2 style={{ marginTop: 0 }}>Goal progress this period</h2>{review.progressByGoal.length === 0 ? <p style={{ color: '#8b949e', marginBottom: 0 }}>No goal progress entries were logged.</p> : <div>{review.progressByGoal.map(goal => <div key={goal.goalId} style={{ display: 'flex', justifyContent: 'space-between', gap: 16, padding: '12px 0', borderTop: '1px solid #24282f' }}><strong>{goal.title}</strong><span>{goal.value} {goal.unit} · {goal.entries} entr{goal.entries === 1 ? 'y' : 'ies'}</span></div>)}</div>}</section>
    <section style={{ ...cardStyle(), marginTop: 16 }}><h2 style={{ marginTop: 0 }}>Review notes</h2><ul style={{ marginBottom: 0, paddingLeft: 22, color: '#d1d5db' }}>{insights.map(note => <li key={note} style={{ margin: '10px 0' }}>{note}</li>)}</ul></section>
  </main>
}

