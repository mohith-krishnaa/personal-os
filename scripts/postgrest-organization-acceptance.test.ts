import assert from 'node:assert/strict'
import { test } from 'node:test'
import { loadAcceptanceConfig } from './postgrest-organization-acceptance'

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
