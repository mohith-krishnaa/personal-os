import test from 'node:test'
import assert from 'node:assert/strict'
import { createProject, updateProject } from './projects'
import { validateProjectName } from './project-validation'

test('organization project contract accepts valid names', () => {
  assert.equal(validateProjectName('Exam preparation'), null)
})

test('organization project contract accepts names at the 120-character limit', () => {
  assert.equal(validateProjectName('P'.repeat(120)), null)
})

test('organization project contract rejects blank names', () => {
  assert.equal(validateProjectName('   '), 'Project name is required')
})

test('organization project contract rejects names over 120 characters', () => {
  assert.equal(validateProjectName('P'.repeat(121)), 'Project name must be 120 characters or fewer')
})

test('createProject derives user_id from the authenticated session', async () => {
  let inserted: Record<string, unknown> | undefined
  const userId = 'authenticated-owner'
  const query = {
    select() {
      return this
    },
    single: async () => ({
      data: { id: 'project-1', user_id: userId, name: 'Personal', description: null, status: 'ACTIVE' },
      error: null,
    }),
  }
  const supabase = {
    auth: {
      getUser: async () => ({ data: { user: { id: userId } }, error: null }),
    },
    from(table: string) {
      assert.equal(table, 'projects')
      return {
        insert(values: Record<string, unknown>) {
          inserted = values
          return query
        },
      }
    },
  } as any

  await createProject(supabase, { name: '  Personal  ', description: '  ' })

  assert.equal(inserted?.user_id, userId)
  assert.equal(inserted?.name, 'Personal')
  assert.equal(inserted?.description, null)
})

test('updateProject scopes the update to the authenticated owner', async () => {
  const userId = 'authenticated-owner'
  const filters: Array<[string, string]> = []
  let updatePayload: Record<string, unknown> | undefined
  const query = {
    eq(column: string, value: string) {
      filters.push([column, value])
      return this
    },
    select() {
      return this
    },
    single: async () => ({
      data: { id: 'project-1', user_id: userId, name: 'Renamed', description: null, status: 'ACTIVE' },
      error: null,
    }),
  }
  const supabase = {
    auth: {
      getUser: async () => ({ data: { user: { id: userId } }, error: null }),
    },
    from(table: string) {
      assert.equal(table, 'projects')
      return {
        update(values: Record<string, unknown>) {
          updatePayload = values
          return query
        },
      }
    },
  } as any

  await updateProject(supabase, 'project-1', { name: 'Renamed' })

  assert.deepEqual(filters, [['id', 'project-1'], ['user_id', userId]])
  assert.equal(updatePayload?.name, 'Renamed')
  assert.equal(updatePayload?.user_id, undefined)
})

test('updateProject rejects unauthenticated callers before database access', async () => {
  let fromCalls = 0
  const supabase = {
    auth: {
      getUser: async () => ({ data: { user: null }, error: null }),
    },
    from() {
      fromCalls += 1
      throw new Error('database should not be reached')
    },
  } as any

  await assert.rejects(
    () => updateProject(supabase, 'project-1', { name: 'Renamed' }),
    /Authentication required/,
  )
  assert.equal(fromCalls, 0)
})
