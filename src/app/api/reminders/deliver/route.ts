import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request: Request) {
  const expected = process.env.REMINDER_WORKER_SECRET
  const supplied = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  if (!expected || supplied !== expected) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const supabase = await createClient()
  const now = new Date().toISOString()
  const { data: due, error } = await supabase
    .from('reminders')
    .select('id, user_id, task_id, remind_at, channel')
    .eq('enabled', true)
    .is('delivered_at', null)
    .lte('remind_at', now)
    .limit(100)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  let delivered = 0
  for (const reminder of due ?? []) {
    const { data: claimed, error: claimError } = await supabase
      .from('reminders')
      .update({ delivered_at: now, updated_at: now })
      .eq('id', reminder.id)
      .eq('enabled', true)
      .is('delivered_at', null)
      .select('id')
      .maybeSingle()

    if (claimError) return NextResponse.json({ error: claimError.message }, { status: 500 })
    if (!claimed) continue

    const { error: eventError } = await supabase.from('activity_events').insert({
      user_id: reminder.user_id,
      event_type: 'REMINDER_DELIVERED',
      entity_type: 'REMINDER',
      entity_id: reminder.id,
      metadata: { task_id: reminder.task_id, channel: reminder.channel },
    })
    if (eventError) return NextResponse.json({ error: eventError.message }, { status: 500 })
    delivered += 1
  }

  return NextResponse.json({ delivered, checked: due?.length ?? 0 })
}

export async function GET(request: Request) {
  return POST(request)
}
