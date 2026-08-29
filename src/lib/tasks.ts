import { createClient } from '@/lib/supabase/server'

export type Task = {
  id: string
  title: string
  description: string | null
  status: 'BACKLOG' | 'TODO' | 'IN_PROGRESS' | 'COMPLETED' | 'CANCELLED'
  priority: 'LOW' | 'MEDIUM' | 'HIGH'
  due_at: string | null
  estimated_minutes: number | null
  actual_minutes: number | null
  completed_at: string | null
  created_at: string
  updated_at: string
}

export async function getTasks() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data, error } = await supabase
    .from('tasks')
    .select('*')
    .order('due_at', { ascending: true, nullsFirst: false })
    .order('created_at', { ascending: false })

  if (error) throw error
  return data as Task[]
}

export async function createTask(input: Pick<Task, 'title'> & Partial<Pick<Task, 'description' | 'priority' | 'due_at' | 'estimated_minutes'>>) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data, error } = await supabase
    .from('tasks')
    .insert({ ...input, user_id: user.id })
    .select()
    .single()

  if (error) throw error

  await supabase.from('activity_events').insert({
    user_id: user.id,
    event_type: 'TASK_CREATED',
    entity_type: 'TASK',
    entity_id: data.id,
    metadata: { priority: data.priority },
  })

  return data as Task
}
