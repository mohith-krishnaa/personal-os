export type ReminderDeliveryRpcClient = {
  rpc: (
    functionName: string,
    args: { p_limit: number },
  ) => PromiseLike<{
    data: Array<unknown> | null
    error: { message: string } | null
  }>
}

type ReminderDeliveryDependencies = {
  getExpectedSecret: () => string | undefined
  createAdminClient: () => ReminderDeliveryRpcClient
}

export function getReminderWorkerSecret(
  env: { REMINDER_WORKER_SECRET?: string; CRON_SECRET?: string } = process.env,
): string | undefined {
  return env.REMINDER_WORKER_SECRET || env.CRON_SECRET
}

export function createReminderDeliveryHandlers(dependencies: ReminderDeliveryDependencies) {
  async function deliver(request: Request): Promise<Response> {
    const expected = dependencies.getExpectedSecret()
    const supplied = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
    if (!expected || supplied !== expected) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 })
    }

    try {
      const { data: claimed, error } = await dependencies.createAdminClient().rpc(
        'claim_due_reminders',
        { p_limit: 100 },
      )

      if (error) return Response.json({ error: error.message }, { status: 500 })

      const delivered = claimed?.length ?? 0
      return Response.json({ delivered, checked: delivered })
    } catch {
      return Response.json({ error: 'Reminder delivery failed' }, { status: 500 })
    }
  }

  return { GET: deliver, POST: deliver }
}
