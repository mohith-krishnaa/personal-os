'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { createGoal, logProgress } from '@/lib/progress-service'

export async function createGoalAction(formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')
  await createGoal(supabase, user.id, {
    title: String(formData.get('title') ?? ''),
    unit: String(formData.get('unit') ?? ''),
    target: Number(formData.get('target')),
  })
  revalidatePath('/dashboard')
}

export async function logProgressAction(formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')
  await logProgress(supabase, user.id, {
    goalId: String(formData.get('goalId') ?? ''),
    value: Number(formData.get('value')),
    occurredOn: String(formData.get('occurredOn') ?? ''),
  })
  revalidatePath('/dashboard')
}
