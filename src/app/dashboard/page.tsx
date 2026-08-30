import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { listTasks } from '@/lib/tasks'
import { getGoalProgress } from '@/lib/progress-service'
import type { Task } from '@/types/task'
import TaskActions from './task-actions'
import TaskEditor from './task-editor'
import EditTask from './edit-task'
import TaskCalendar from './calendar'

function formatDate(value: string | null) { if (!value) return 'No due date'; return new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) }

export default async function DashboardPage() {
  const supabase = await createClient(); const { data: { user } } = await supabase.auth.getUser(); if (!user) redirect('/login')
  const tasks = await listTasks(); const completed = tasks.filter(t => t.status === 'COMPLETED').length; const overdue = tasks.filter(t => t.status !== 'COMPLETED' && t.due_at && new Date(t.due_at) < new Date()).length; const progress = tasks.length ? Math.round(completed / tasks.length * 100) : 0
  const { data: goals } = await supabase.from('goals').select('id, title, unit, target, created_at, updated_at').order('created_at', { ascending: false })
  const goalCards = await Promise.all((goals ?? []).map(async goal => ({ goal, progress: await getGoalProgress(supabase, goal.id) })))
  return <main style={{ maxWidth: 1100, margin: '0 auto', padding: '40px 20px' }}>
    <header style={{ display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center', marginBottom: 28 }}><div><div style={{ color: '#8b949e', fontSize: 13, letterSpacing: 1 }}>PERSONAL OS</div><h1 style={{ margin: '8px 0 4px', fontSize: 34 }}>Today</h1><p style={{ color: '#8b949e', margin: 0 }}>{user.email}</p></div><TaskEditor /></header>
    <section style={{ display: 'grid', gridTemplateColumns: '1fr 280px', gap: 18 }}><div style={{ border: '1px solid #24282f', borderRadius: 16, background: '#111419', padding: 22 }}><div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 18 }}><h2 style={{ margin: 0 }}>Tasks</h2><span style={{ color: '#8b949e' }}>{completed}/{tasks.length} complete</span></div>{tasks.length === 0 ? <p style={{ color: '#8b949e' }}>No tasks yet. Add the first thing you want to get done.</p> : tasks.map((task: Task) => <div key={task.id} style={{ padding: '15px 0', borderTop: '1px solid #24282f' }}><div style={{ display: 'flex', alignItems: 'center', gap: 14 }}><TaskActions mode="toggle" task={task} /><div style={{ flex: 1 }}><div style={{ textDecoration: task.status === 'COMPLETED' ? 'line-through' : 'none', color: task.status === 'COMPLETED' ? '#737b86' : '#f4f4f5' }}>{task.title}</div><small style={{ color: '#8b949e' }}>{task.priority} · {task.estimated_minutes ? `${task.estimated_minutes} min · ` : ''}{formatDate(task.due_at)}</small></div><EditTask task={task} /></div></div>)}</div><aside style={{ border: '1px solid #24282f', borderRadius: 16, background: '#111419', padding: 22 }}><h2 style={{ marginTop: 0 }}>Today</h2><div style={{ fontSize: 42, fontWeight: 700 }}>{progress}%</div><div style={{ height: 8, background: '#24282f', borderRadius: 99, overflow: 'hidden', marginTop: 12 }}><div style={{ width: `${progress}%`, height: '100%', background: '#f4f4f5' }} /></div><div style={{ marginTop: 22, color: '#8b949e' }}>{overdue} overdue · {tasks.length - completed} remaining</div></aside></section>
    <section style={{ marginTop: 18, border: '1px solid #24282f', borderRadius: 16, background: '#111419', padding: 22 }}><div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 18 }}><h2 style={{ margin: 0 }}>Goals & Streaks</h2><span style={{ color: '#8b949e' }}>{goalCards.length} goals</span></div>{goalCards.length === 0 ? <p style={{ color: '#8b949e' }}>No goals yet. Create a measurable goal to start tracking progress.</p> : goalCards.map(({ goal, progress: gp }) => <article key={goal.id} style={{ padding: '16px 0', borderTop: '1px solid #24282f' }}><div style={{ display: 'flex', justifyContent: 'space-between', gap: 16 }}><div><strong>{goal.title}</strong><div style={{ color: '#8b949e', marginTop: 4 }}>{gp.total} / {goal.target} {goal.unit}</div></div><div style={{ textAlign: 'right' }}><strong>{gp.percent}%</strong><div style={{ color: '#8b949e', marginTop: 4 }}>{gp.streak.current} day streak · {gp.streak.longest} best</div></div></div><div style={{ height: 7, background: '#24282f', borderRadius: 99, overflow: 'hidden', marginTop: 12 }}><div style={{ width: `${gp.percent}%`, height: '100%', background: '#f4f4f5' }} /></div></article>)}</section>
    <TaskCalendar tasks={tasks} />
  </main>
}
