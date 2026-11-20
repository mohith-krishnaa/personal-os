import test from 'node:test'
import assert from 'node:assert/strict'
import { getClientRequestState } from './client-request-id'

test('reuses a request ID when the same payload is retried', () => {
  let created = 0
  const createId = () => 'request-' + ++created
  const first = getClientRequestState(null, { title: 'Task', project_id: null }, createId)
  const retry = getClientRequestState(first, { title: 'Task', project_id: null }, createId)

  assert.equal(first.id, 'request-1')
  assert.equal(retry.id, first.id)
  assert.equal(created, 1)
})

test('assigns a new request ID when the payload changes', () => {
  let created = 0
  const createId = () => 'request-' + ++created
  const first = getClientRequestState(null, { title: 'Task A' }, createId)
  const changed = getClientRequestState(first, { title: 'Task B' }, createId)

  assert.equal(first.id, 'request-1')
  assert.equal(changed.id, 'request-2')
})

test('a successful submission can start a fresh request after clearing pending state', () => {
  let created = 0
  const createId = () => 'request-' + ++created
  const first = getClientRequestState(null, { title: 'Same title' }, createId)
  const next = getClientRequestState(null, { title: 'Same title' }, createId)

  assert.notEqual(next.id, first.id)
  assert.equal(created, 2)
})
