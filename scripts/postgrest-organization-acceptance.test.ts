import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  assertSingleTaskCreatedEvent,
  loadAcceptanceConfig,
  type ActivityEventAcceptanceRow,
} from './postgrest-organization-acceptance'

const validEnvironment = (): Record<string, string | undefined> => ({
  PERSONAL_OS_ACCEPTANCE_TARGET_ISOLATED: 'YES',
  PERSONAL_OS_ACCEPTANCE_BACKUP_RESTORE_VERIFIED: 'YES',
  PERSONAL_OS_ACCEPTANCE_CONFIRM_TARGET: 'I_HAVE_RESTORED_A_COMPLETE_BACKUP',
  PERSONAL_OS_ACCEPTANCE_SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co',
  PERSONAL_OS_ACCEPTANCE_PROJECT_REF: 'abcdefghijklmnopqrst',
  PERSONAL_OS_ACCEPTANCE_ANON_KEY: 'sb_publishable_test_key',
  PERSONAL_OS_ACCEPTANCE_OWNER_A_EMAIL: 'owner-a@example.test',
  PERSONAL_OS_ACCEPTANCE_OWNER_A_PASSWORD: 'owner-a-test-password',
  PERSONAL_OS_ACCEPTANCE_OWNER_B_EMAIL: 'owner-b@example.test',
  PERSONAL_OS_ACCEPTANCE_OWNER_B_PASSWORD: 'owner-b-test-password',
})

test('requires an explicit execution flag before any network operation', () => {
  assert.throws(
    () => loadAcceptanceConfig(validEnvironment(), []),
    /Pass --execute/,
  )
})

test('requires an explicit isolated-target marker', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_TARGET_ISOLATED = 'NO'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /TARGET_ISOLATED/)
})

test('requires an owner attestation that the complete backup was restored and verified', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_BACKUP_RESTORE_VERIFIED = 'NO'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /backup must be restored and verified/)
})

test('requires the explicit destructive-test confirmation phrase', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_CONFIRM_TARGET = 'YES'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /confirmation is missing/)
})

test('permanently refuses the known production project ref', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_SUPABASE_URL = 'https://gujzvkyytxsnervovvrt.supabase.co'
  env.PERSONAL_OS_ACCEPTANCE_PROJECT_REF = 'gujzvkyytxsnervovvrt'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /permanently blocked/)
})

test('rejects a project-ref mismatch between the URL and explicit target', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_PROJECT_REF = 'zyxwvutsrqponmlkjihg'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /does not match/)
})

test('rejects custom domains and arbitrary external hosts', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_SUPABASE_URL = 'https://db.example.test'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /custom domains are not accepted/)
})

test('rejects non-HTTPS hosted targets', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_SUPABASE_URL = 'http://abcdefghijklmnopqrst.supabase.co'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /custom domains are not accepted/)
})

test('rejects a conflicting application Supabase URL', () => {
  const env = validEnvironment()
  env.NEXT_PUBLIC_SUPABASE_URL = 'https://gujzvkyytxsnervovvrt.supabase.co'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /different project/)
})

test('rejects a service-role JWT even when supplied through the anon-key variable', () => {
  const env = validEnvironment()
  const payload = Buffer.from(JSON.stringify({ role: 'service_role' })).toString('base64url')
  env.PERSONAL_OS_ACCEPTANCE_ANON_KEY = 'header.' + payload + '.signature'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /not an anon key/)
})

test('rejects an owner pair that resolves from the same email address', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_OWNER_B_EMAIL = 'OWNER-A@example.test'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /two different isolated test accounts/)
})

test('accepts an explicitly confirmed isolated hosted Supabase project', () => {
  const config = loadAcceptanceConfig(validEnvironment(), ['--execute'])
  assert.equal(config.projectRef, 'abcdefghijklmnopqrst')
  assert.equal(config.url, 'https://abcdefghijklmnopqrst.supabase.co')
  assert.equal(config.ownerA.email, 'owner-a@example.test')
  assert.equal(config.ownerB.email, 'owner-b@example.test')
})

test('accepts only the explicit local Supabase loopback endpoint', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_SUPABASE_URL = 'http://127.0.0.1:54321'
  env.PERSONAL_OS_ACCEPTANCE_PROJECT_REF = 'local'
  const config = loadAcceptanceConfig(env, ['--execute'])
  assert.equal(config.projectRef, 'local')
  assert.equal(config.url, 'http://127.0.0.1:54321')
})

test('rejects local endpoints on unexpected ports', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_SUPABASE_URL = 'http://127.0.0.1:54322'
  env.PERSONAL_OS_ACCEPTANCE_PROJECT_REF = 'local'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /54321/)
})

test('rejects a conflicting generic SUPABASE_URL', () => {
  const env = validEnvironment()
  env.SUPABASE_URL = 'https://gujzvkyytxsnervovvrt.supabase.co'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /different project/)
})

test('rejects target URLs with a REST path or query parameters', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_SUPABASE_URL = 'https://abcdefghijklmnopqrst.supabase.co/rest/v1'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /only the Supabase project origin/)
})

test('rejects a Supabase secret API key prefix', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_ANON_KEY = 'sb_secret_test_key'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /secret\/service key is not allowed/)
})

const validTaskCreatedEvent: ActivityEventAcceptanceRow = {
  id: 'event-1',
  user_id: 'owner-a',
  event_type: 'TASK_CREATED',
  entity_type: 'TASK',
  entity_id: 'task-a',
}

test('accepts exactly one trusted TASK_CREATED event for the expected owner and task', () => {
  assert.equal(
    assertSingleTaskCreatedEvent([validTaskCreatedEvent], 'owner-a', 'task-a'),
    validTaskCreatedEvent,
  )
})

test('rejects missing and duplicate TASK_CREATED events', () => {
  assert.throws(
    () => assertSingleTaskCreatedEvent([], 'owner-a', 'task-a'),
    /exactly one TASK_CREATED event/,
  )
  assert.throws(
    () => assertSingleTaskCreatedEvent(
      [validTaskCreatedEvent, { ...validTaskCreatedEvent, id: 'event-2' }],
      'owner-a',
      'task-a',
    ),
    /exactly one TASK_CREATED event/,
  )
})

test('rejects a TASK_CREATED event owned by a different user', () => {
  assert.throws(
    () => assertSingleTaskCreatedEvent(
      [{ ...validTaskCreatedEvent, user_id: 'owner-b' }],
      'owner-a',
      'task-a',
    ),
    /owner does not match/,
  )
})

test('rejects an unexpected event type or entity identity', () => {
  assert.throws(
    () => assertSingleTaskCreatedEvent(
      [{ ...validTaskCreatedEvent, event_type: 'TASK_COMPLETED' }],
      'owner-a',
      'task-a',
    ),
    /unexpected event type/,
  )
  assert.throws(
    () => assertSingleTaskCreatedEvent(
      [{ ...validTaskCreatedEvent, entity_type: 'PROJECT' }],
      'owner-a',
      'task-a',
    ),
    /entity_type must be TASK/,
  )
  assert.throws(
    () => assertSingleTaskCreatedEvent(
      [{ ...validTaskCreatedEvent, entity_id: 'task-b' }],
      'owner-a',
      'task-a',
    ),
    /entity_id does not match/,
  )
})


test('accepts a legacy anon JWT key', () => {
  const env = validEnvironment()
  const payload = Buffer.from(JSON.stringify({ role: 'anon' })).toString('base64url')
  env.PERSONAL_OS_ACCEPTANCE_ANON_KEY = 'header.' + payload + '.signature'
  const config = loadAcceptanceConfig(env, ['--execute'])
  assert.equal(config.anonKey, env.PERSONAL_OS_ACCEPTANCE_ANON_KEY)
})

test('rejects an unrecognized opaque API key', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_ANON_KEY = 'not-a-supabase-api-key'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /publishable key or a legacy anon JWT/)
})

test('rejects an empty publishable-key prefix', () => {
  const env = validEnvironment()
  env.PERSONAL_OS_ACCEPTANCE_ANON_KEY = 'sb_publishable_'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /publishable key is empty/)
})

test('rejects a legacy JWT without an anon role claim', () => {
  const env = validEnvironment()
  const payload = Buffer.from(JSON.stringify({ sub: 'anonymous' })).toString('base64url')
  env.PERSONAL_OS_ACCEPTANCE_ANON_KEY = 'header.' + payload + '.signature'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /not an anon key/)
})

test('rejects an authenticated JWT', () => {
  const env = validEnvironment()
  const payload = Buffer.from(JSON.stringify({ role: 'authenticated' })).toString('base64url')
  env.PERSONAL_OS_ACCEPTANCE_ANON_KEY = 'header.' + payload + '.signature'
  assert.throws(() => loadAcceptanceConfig(env, ['--execute']), /not an anon key/)
})
