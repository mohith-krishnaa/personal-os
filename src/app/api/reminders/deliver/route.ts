import { createAdminClient } from '@/lib/supabase/admin'
import {
  createReminderDeliveryHandlers,
  getReminderWorkerSecret,
} from '@/lib/reminder-delivery-handler'

const handlers = createReminderDeliveryHandlers({
  getExpectedSecret: getReminderWorkerSecret,
  createAdminClient: () => {
    const client = createAdminClient()
    return {
      rpc: (functionName, args) => client.rpc(functionName as 'claim_due_reminders', args),
    }
  },
})

export const GET = handlers.GET
export const POST = handlers.POST
