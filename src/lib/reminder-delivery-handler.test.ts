import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createReminderDeliveryHandlers,
  getReminderWorkerSecret,
} from './reminder-delivery-handler'

type RpcResult = {
  data: Array<{ id: string }> | null
  error: { message: string } | null
}

function createHarness(
  expectedSecret: string | undefined = 'test-worker-secret',
  result: RpcResult = { data: [{ id: 'reminder-1' }, { id: 'reminder-2' }], error: null },
  rejectedError?: Error,
) {
  let adminClientCreations = 0
  const rpcCalls: Array<{ functionName: string; args: { p_limit: number } }> = []

  const handlers = createReminderDeliveryHandlers({
    getExpectedSecret: () => expectedSecret,
    createAdminClient: () => {
      adminClientCreations += 1
      return {
        rpc: async (functionName, args) => {
          rpcCalls.push({ functionName, args })
          if (rejectedError) throw rejectedError
          return result
        },
      }
    },
  })

  return { handlers, rpcCalls, get adminClientCreations() { return adminClientCreations } }
}

function makeRequest(method: 'GET' | 'POST', authorization?: string) {
  const headers = new Headers()
  if (authorization !== undefined) headers.set('authorization', authorization)
  return new Request('https://personal-os.test/api/reminders/deliver', { method, headers })
}

test('worker secret resolver prefers REMINDER_WORKER_SECRET and falls back to CRON_SECRET', () => {
  assert.equal(
    getReminderWorkerSecret({
      REMINDER_WORKER_SECRET: 'primary-test-secret',
      CRON_SECRET: 'fallback-test-secret',
    }),
    'primary-test-secret',
  )
  assert.equal(getReminderWorkerSecret({ CRON_SECRET: 'fallback-test-secret' }), 'fallback-test-secret')
  assert.equal(getReminderWorkerSecret({}), undefined)
})

for (const method of ['GET', 'POST'] as const) {
  test(`${method} rejects requests when no worker secret is configured`, async () => {
    const harness = createHarness(undefined)
    const response = await harness.handlers[method](makeRequest(method, 'Bearer test-worker-secret'))

    assert.equal(response.status, 401)
    assert.deepEqual(await response.json(), { error: 'Unauthorized' })
    assert.equal(harness.adminClientCreations, 0)
    assert.equal(harness.rpcCalls.length, 0)
  })

  test(`${method} rejects missing and incorrect credentials before creating the admin client`, async () => {
    for (const authorization of [undefined, 'Bearer incorrect-secret', 'Basic test-worker-secret']) {
      const harness = createHarness()
      const response = await harness.handlers[method](makeRequest(method, authorization))

      assert.equal(response.status, 401)
      assert.deepEqual(await response.json(), { error: 'Unauthorized' })
      assert.equal(harness.adminClientCreations, 0)
      assert.equal(harness.rpcCalls.length, 0)
    }
  })

  test(`${method} invokes the atomic claim RPC exactly once and maps returned rows`, async () => {
    const harness = createHarness()
    const response = await harness.handlers[method](makeRequest(method, 'Bearer test-worker-secret'))

    assert.equal(response.status, 200)
    assert.deepEqual(await response.json(), { delivered: 2, checked: 2 })
    assert.equal(harness.adminClientCreations, 1)
    assert.deepEqual(harness.rpcCalls, [{
      functionName: 'claim_due_reminders',
      args: { p_limit: 100 },
    }])
  })

  test(`${method} reports an RPC error as HTTP 500 without reporting successful delivery`, async () => {
    const harness = createHarness(
      'test-worker-secret',
      { data: null, error: { message: 'database unavailable' } },
    )
    const response = await harness.handlers[method](makeRequest(method, 'Bearer test-worker-secret'))
    const body = await response.json()

    assert.equal(response.status, 500)
    assert.deepEqual(body, { error: 'database unavailable' })
    assert.equal('delivered' in body, false)
    assert.equal(harness.rpcCalls.length, 1)
  })

  test(`${method} reports a rejected RPC promise as a generic HTTP 500`, async () => {
    const harness = createHarness(
      'test-worker-secret',
      { data: null, error: null },
      new Error('sensitive database detail'),
    )
    const response = await harness.handlers[method](makeRequest(method, 'Bearer test-worker-secret'))
    const body = await response.text()

    assert.equal(response.status, 500)
    assert.equal(body, JSON.stringify({ error: 'Reminder delivery failed' }))
    assert.equal(body.includes('sensitive database detail'), false)
    assert.equal(body.includes('test-worker-secret'), false)
    assert.equal(harness.rpcCalls.length, 1)
  })
}

test('a successful empty claim returns zero counts', async () => {
  const harness = createHarness('test-worker-secret', { data: [], error: null })
  const response = await harness.handlers.GET(makeRequest('GET', 'Bearer test-worker-secret'))

  assert.equal(response.status, 200)
  assert.deepEqual(await response.json(), { delivered: 0, checked: 0 })
})
