import test from 'node:test'
import assert from 'node:assert/strict'
import { createProject, getProjectManagerSections, listProjects, updateProject } from './projects'
import type { Project } from '@/types/project'
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


test('getProjectManagerSections keeps completed projects separate and excludes archived projects', () => {
  const projects = [
    { id: 'active', status: 'ACTIVE' },
    { id: 'completed', status: 'COMPLETED' },
    { id: 'archived', status: 'ARCHIVED' },
  ] as Project[]

  const sections = getProjectManagerSections(projects)

  assert.deepEqual(sections.active.map(project => project.id), ['active'])
  assert.deepEqual(sections.completed.map(project => project.id), ['completed'])
})

test('listProjects preserves legacy COMPLETED status without rewriting it', async () => {
  const userId = 'authenticated-owner'
  const filters: Array<[string, string]> = []
  const projects = [{ id: 'completed-project', user_id: userId, name: 'Finished', description: null, status: 'COMPLETED', created_at: '', updated_at: '' }]
  const query = {
    eq(column: string, value: string) {
      filters.push([column, value])
      return this
    },
    order: async () => ({ data: projects, error: null }),
  }
  const supabase = {
    auth: { getUser: async () => ({ data: { user: { id: userId } }, error: null }) },
    from(table: string) {
      assert.equal(table, 'projects')
      return { select: () => query }
    },
  } as any

  const result = await listProjects(supabase, 'COMPLETED')

  assert.deepEqual(filters, [['user_id', userId], ['status', 'COMPLETED']])
  assert.equal(result[0].status, 'COMPLETED')
})

test('updateProject rejects a transition to legacy COMPLETED status', async () => {
  let fromCalls = 0
  const supabase = {
    auth: { getUser: async () => ({ data: { user: { id: 'authenticated-owner' } }, error: null }) },
    from() {
      fromCalls += 1
      throw new Error('database should not be reached')
    },
  } as any

  await assert.rejects(
    () => updateProject(supabase, 'project-1', { status: 'COMPLETED' } as any),
    /Project status is invalid/,
  )
  assert.equal(fromCalls, 0)
})

test('listProjects scopes reads to the authenticated owner and optional status', async () => {
  const userId = 'authenticated-owner'
  const filters: Array<[string, string]> = []
  const orderCalls: Array<[string, { ascending: boolean }]> = []
  const projects = [{ id: 'project-1', user_id: userId, name: 'Personal', status: 'ARCHIVED' }]
  const query = {
    eq(column: string, value: string) {
      filters.push([column, value])
      return this
    },
    order(column: string, options: { ascending: boolean }) {
      orderCalls.push([column, options])
      return Promise.resolve({ data: projects, error: null })
    },
  }
  const supabase = {
    auth: {
      getUser: async () => ({ data: { user: { id: userId } }, error: null }),
    },
    from(table: string) {
      assert.equal(table, 'projects')
      return {
        select(columns: string) {
          assert.equal(columns, 'id,user_id,name,description,status,created_at,updated_at')
          return query
        },
      }
    },
  } as any

  const result = await listProjects(supabase, 'ARCHIVED')

  assert.deepEqual(filters, [['user_id', userId], ['status', 'ARCHIVED']])
  assert.deepEqual(orderCalls, [['created_at', { ascending: false }]])
  assert.deepEqual(result, projects)
})

test('listProjects rejects unauthenticated callers before database access', async () => {
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

  await assert.rejects(() => listProjects(supabase), /Authentication required/)
  assert.equal(fromCalls, 0)
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
  assert.equal(inserted?.title, undefined, 'new application writes use only the canonical name column')
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
  assert.equal(updatePayload?.title, undefined, 'renames use only the canonical name column')
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
