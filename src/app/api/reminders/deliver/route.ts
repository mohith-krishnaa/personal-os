import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'

async function deliver(request: Request) {
  const expected = process.env.REMINDER_WORKER_SECRET || process.env.CRON_SECRET
  const supplied = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  if (!expected || supplied !== expected) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const supabase = createAdminClient()
  const { data: claimed, error } = await supabase.rpc('claim_due_reminders', {
    p_limit: 100,
  })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const delivered = claimed?.length ?? 0
  return NextResponse.json({ delivered, checked: delivered })
}

export async function GET(request: Request) { return deliver(request) }
export async function POST(request: Request) { return deliver(request) }
