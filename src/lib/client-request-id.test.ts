import test from 'node:test'
import assert from 'node:assert/strict'
import {
  completeClientRequestState,
  getClientRequestState,
  type ClientRequestStorage,
} from './client-request-id'

const REQUEST_ID_A = '91000000-0000-4000-8000-000000000001'
const REQUEST_ID_B = '91000000-0000-4000-8000-000000000002'
const REQUEST_ID_C = '91000000-0000-4000-8000-000000000003'

class MemoryStorage implements ClientRequestStorage {
  private readonly values = new Map<string, string>()

  getItem(key: string) {
    return this.values.get(key) ?? null
  }

  setItem(key: string, value: string) {
    this.values.set(key, value)
  }
}

test('reuses a request ID when the same payload is retried in the mounted form', async () => {
  let created = 0
  const createId = () => 'request-' + ++created
  const first = await getClientRequestState(null, { title: 'Task', project_id: null }, createId)
  const retry = await getClientRequestState(first, { title: 'Task', project_id: null }, createId)

  assert.equal(first.id, 'request-1')
  assert.equal(retry.id, first.id)
  assert.equal(created, 1)
})

test('assigns a new request ID when the payload changes', async () => {
  let created = 0
  const createId = () => 'request-' + ++created
  const first = await getClientRequestState(null, { title: 'Task A' }, createId)
  const changed = await getClientRequestState(first, { title: 'Task B' }, createId)

  assert.equal(first.id, 'request-1')
  assert.equal(changed.id, 'request-2')
})

test('a successful submission can start a fresh request after clearing pending state', async () => {
  let created = 0
  const createId = () => 'request-' + ++created
  const first = await getClientRequestState(null, { title: 'Same title' }, createId)
  const next = await getClientRequestState(null, { title: 'Same title' }, createId)

  assert.notEqual(next.id, first.id)
  assert.equal(created, 2)
})

test('restores the same pending request ID after a component remount', async () => {
  const storage = new MemoryStorage()
  let created = 0
  const createId = () => [REQUEST_ID_A, REQUEST_ID_B][created++]
  const firstMount = await getClientRequestState(
    null,
    { title: 'Sensitive task title', priority: 'HIGH' },
    createId,
    storage,
    'task-editor',
  )
  const remounted = await getClientRequestState(
    null,
    { title: 'Sensitive task title', priority: 'HIGH' },
    createId,
    storage,
    'task-editor',
  )

  assert.equal(remounted.id, firstMount.id)
  assert.equal(created, 1)
  const persisted = storage.getItem('task-editor') ?? ''
  assert.equal(persisted.includes('Sensitive task title'), false)
  assert.match(persisted, /fingerprintHash/)
})

test('keeps different pending payloads isolated and can recover either after remount', async () => {
  const storage = new MemoryStorage()
  const ids = [REQUEST_ID_A, REQUEST_ID_B]
  let created = 0
  const createId = () => ids[created++]
  const first = await getClientRequestState(null, { title: 'Task A' }, createId, storage, 'quick-add')
  const second = await getClientRequestState(null, { title: 'Task B' }, createId, storage, 'quick-add')
  const retryFirst = await getClientRequestState(null, { title: 'Task A' }, createId, storage, 'quick-add')

  assert.equal(first.id, REQUEST_ID_A)
  assert.equal(second.id, REQUEST_ID_B)
  assert.equal(retryFirst.id, first.id)
  assert.equal(created, 2)
})

test('completing a request prevents a later identical task from reusing its ID', async () => {
  const storage = new MemoryStorage()
  let created = 0
  const ids = [REQUEST_ID_A, REQUEST_ID_B]
  const createId = () => ids[created++]
  const payload = { title: 'Repeatable task title' }
  const first = await getClientRequestState(null, payload, createId, storage, 'task-editor')

  completeClientRequestState(first, storage, 'task-editor')
  const next = await getClientRequestState(null, payload, createId, storage, 'task-editor')

  assert.equal(first.id, REQUEST_ID_A)
  assert.equal(next.id, REQUEST_ID_B)
  assert.notEqual(next.id, first.id)
})

test('ignores malformed persisted state and replaces it with a valid pending entry', async () => {
  const storage = new MemoryStorage()
  storage.setItem('task-editor', '{invalid json')
  const request = await getClientRequestState(
    null,
    { title: 'Task' },
    () => REQUEST_ID_C,
    storage,
    'task-editor',
  )

  assert.equal(request.id, REQUEST_ID_C)
  const persisted = JSON.parse(storage.getItem('task-editor') ?? '{}') as { version: number; requests: unknown[] }
  assert.equal(persisted.version, 1)
  assert.equal(persisted.requests.length, 1)
})

test('storage failures fall back to an in-memory request without throwing', async () => {
  const storage: ClientRequestStorage = {
    getItem() { throw new Error('storage unavailable') },
    setItem() { throw new Error('storage unavailable') },
  }
  const request = await getClientRequestState(
    null,
    { title: 'Task' },
    () => REQUEST_ID_C,
    storage,
    'task-editor',
  )

  assert.equal(request.id, REQUEST_ID_C)
  assert.equal(request.fingerprint, JSON.stringify({ title: 'Task' }))
})
