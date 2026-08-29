import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { listTasks } from '@/lib/tasks'
import type { Task } from '@/types/task'
import TaskActions from './task-actions'

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const tasks = await listTasks()
  const completed = tasks.filter((task) => task.status === 'COMPLETED').length
  const progress = tasks.length ? Math.round((completed / tasks.length) * 100) : 0

  return (
    <main style={{ maxWidth: 1100, margin: '0 auto', padding: '40px 20px' }}>
      <header style={{ display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center', marginBottom: 28 }}>
        <div>
          <div style={{ color: '#8b949e', fontSize: 13, letterSpacing: 1 }}>PERSONAL OS</div>
          <h1 style={{ margin: '8px 0 4px', fontSize: 34 }}>Today</h1>
          <p style={{ color: '#8b949e', margin: 0 }}>{user.email}</p>
        </div>
        <TaskActions mode="add" />
      </header>

      <section style={{ display: 'grid', gridTemplateColumns: '1fr 280px', gap: 18 }}>
        <div style={{ border: '1px solid #24282f', borderRadius: 16, background: '#111419', padding: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 18 }}>
            <h2 style={{ margin: 0 }}>Tasks</h2>
            <span style={{ color: '#8b949e' }}>{completed}/{tasks.length} complete</span>
          </div>
          {tasks.length === 0 ? (
            <p style={{ color: '#8b949e' }}>No tasks yet. Add the first thing you want to get done.</p>
          ) : tasks.map((task: Task) => (
            <div key={task.id} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '15px 0', borderTop: '1px solid #24282f' }}>
              <TaskActions mode="toggle" task={task} />
              <div style={{ flex: 1 }}>
                <div style={{ textDecoration: task.status === 'COMPLETED' ? 'line-through' : 'none', color: task.status === 'COMPLETED' ? '#737b86' : '#f4f4f5' }}>{task.title}</div>
                <small style={{ color: '#8b949e' }}>{task.priority} priority{task.estimated_minutes ? ` · ${task.estimated_minutes} min` : ''}</small>
              </div>
            </div>
          ))}
        </div>

        <aside style={{ border: '1px solid #24282f', borderRadius: 16, background: '#111419', padding: 22 }}>
          <h2 style={{ marginTop: 0 }}>Progress</h2>
          <div style={{ fontSize: 42, fontWeight: 700 }}>{progress}%</div>
          <div style={{ height: 8, background: '#24282f', borderRadius: 99, overflow: 'hidden', marginTop: 12 }}>
            <div style={{ width: `${progress}%`, height: '100%', background: '#f4f4f5' }} />
          </div>
          <p style={{ color: '#8b949e', lineHeight: 1.5 }}>This is calculated from your real task data. AI insights will be added after the core workflow is stable.</p>
        </aside>
      </section>
    </main>
  )
}
