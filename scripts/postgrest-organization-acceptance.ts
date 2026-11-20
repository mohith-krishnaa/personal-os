import { randomUUID } from 'node:crypto'
import { pathToFileURL } from 'node:url'
import { createClient } from '@supabase/supabase-js'

type Environment = Record<string, string | undefined>

type OwnerCredentials = {
  email: string
  password: string
}

export type AcceptanceConfig = {
  url: string
  projectRef: string
  anonKey: string
  ownerA: OwnerCredentials
  ownerB: OwnerCredentials
}

const PRODUCTION_PROJECT_REF = 'gujzvkyytxsnervovvrt'
const RESTORE_CONFIRMATION = 'I_HAVE_RESTORED_A_COMPLETE_BACKUP'

function required(env: Environment, key: string) {
  const value = env[key]?.trim()
  if (!value) throw new Error('Missing required environment variable: ' + key)
  return value
}

function assertPublicKey(key: string) {
  if (key.startsWith('sb_secret_')) {
    throw new Error('A Supabase secret/service key is not allowed. Use the project anon or publishable key.')
  }

  const parts = key.split('.')
  if (parts.length !== 3) return

  let payload: { role?: unknown }
  try {
    payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')) as { role?: unknown }
  } catch {
    throw new Error('The configured Supabase API key is not a valid public JWT key.')
  }

  if (payload.role !== 'anon') {
    throw new Error('The configured Supabase JWT key is not an anon key. Service-role and authenticated JWTs are forbidden.')
  }
}

function normalizeOrigin(value: string) {
  try {
    return new URL(value).origin
  } catch {
    throw new Error('A configured Supabase URL is not valid.')
  }
}

export function loadAcceptanceConfig(env: Environment, args: string[]): AcceptanceConfig {
  if (!args.includes('--execute')) {
    throw new Error('Refusing to run. Pass --execute only after restoring a complete backup into an isolated Supabase project.')
  }

  if (env.PERSONAL_OS_ACCEPTANCE_TARGET_ISOLATED !== 'YES') {
    throw new Error('Set PERSONAL_OS_ACCEPTANCE_TARGET_ISOLATED=YES only for the isolated restored target.')
  }

  if (env.PERSONAL_OS_ACCEPTANCE_BACKUP_RESTORE_VERIFIED !== 'YES') {
    throw new Error('A complete schema/data/roles backup must be restored and verified before this harness can run.')
  }

  if (env.PERSONAL_OS_ACCEPTANCE_CONFIRM_TARGET !== RESTORE_CONFIRMATION) {
    throw new Error('The explicit isolated-target confirmation is missing.')
  }

  const rawUrl = required(env, 'PERSONAL_OS_ACCEPTANCE_SUPABASE_URL')
  const projectRef = required(env, 'PERSONAL_OS_ACCEPTANCE_PROJECT_REF').toLowerCase()
  const anonKey = required(env, 'PERSONAL_OS_ACCEPTANCE_ANON_KEY')

  let target: URL
  try {
    target = new URL(rawUrl)
  } catch {
    throw new Error('PERSONAL_OS_ACCEPTANCE_SUPABASE_URL must be a valid absolute URL.')
  }

  if (target.username || target.password || target.search || target.hash || target.pathname !== '/') {
    throw new Error('The acceptance URL must contain only the Supabase project origin.')
  }

  const hostname = target.hostname.toLowerCase()
  if (hostname === PRODUCTION_PROJECT_REF + '.supabase.co' || hostname.endsWith('.' + PRODUCTION_PROJECT_REF + '.supabase.co')) {
    throw new Error('The known production Supabase project is permanently blocked by this harness.')
  }

  const isLocal = hostname === 'localhost' || hostname === '127.0.0.1'
  if (isLocal) {
    if (target.protocol !== 'http:' || target.port !== '54321' || projectRef !== 'local') {
      throw new Error('Local Supabase is allowed only at http://localhost:54321 or http://127.0.0.1:54321 with project ref "local".')
    }
  } else {
    const match = hostname.match(/^([a-z0-9]{20})\.supabase\.co$/)
    if (!match || target.protocol !== 'https:' || target.port !== '') {
      throw new Error('Hosted targets must use https://<20-character-project-ref>.supabase.co; custom domains are not accepted.')
    }
    if (match[1] === PRODUCTION_PROJECT_REF) {
      throw new Error('The known production Supabase project is permanently blocked by this harness.')
    }
    if (projectRef !== match[1]) {
      throw new Error('PERSONAL_OS_ACCEPTANCE_PROJECT_REF does not match the Supabase URL host.')
    }
  }

  for (const [name, value] of [
    ['NEXT_PUBLIC_SUPABASE_URL', env.NEXT_PUBLIC_SUPABASE_URL],
    ['SUPABASE_URL', env.SUPABASE_URL],
  ] as const) {
    const appUrl = value?.trim()
    if (appUrl && normalizeOrigin(appUrl) !== target.origin) {
      throw new Error(name + ' points to a different project than the explicit acceptance target.')
    }
  }

  assertPublicKey(anonKey)

  const ownerA = {
    email: required(env, 'PERSONAL_OS_ACCEPTANCE_OWNER_A_EMAIL'),
    password: required(env, 'PERSONAL_OS_ACCEPTANCE_OWNER_A_PASSWORD'),
  }
  const ownerB = {
    email: required(env, 'PERSONAL_OS_ACCEPTANCE_OWNER_B_EMAIL'),
    password: required(env, 'PERSONAL_OS_ACCEPTANCE_OWNER_B_PASSWORD'),
  }

  if (ownerA.email.toLowerCase() === ownerB.email.toLowerCase()) {
    throw new Error('Owner A and Owner B must be two different isolated test accounts.')
  }

  return {
    url: target.origin,
    projectRef,
    anonKey,
    ownerA,
    ownerB,
  }
}

type Client = ReturnType<typeof createClient<any>>
type Row = { id: string; user_id: string }
type CreatedRows = {
  projects: string[]
  tasks: string[]
  canonicalChecklists: string[]
  legacyChecklists: string[]
}

function createTracker(): CreatedRows {
  return { projects: [], tasks: [], canonicalChecklists: [], legacyChecklists: [] }
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

async function insertOwnedRow(client: Client, table: string, values: Record<string, unknown>, ids: string[]) {
  const { data, error } = await client.from(table).insert(values).select('id,user_id').single()
  if (error || !data) {
    throw new Error('Fixture INSERT failed for ' + table + ' (' + (error?.code ?? 'no-row') + ').')
  }
  const row = data as Row
  ids.push(row.id)
  return row
}

async function expectRlsDenied(label: string, operation: PromiseLike<{ data: unknown; error: { code?: string } | null }>) {
  const result = await operation
  assert(result.error?.code === '42501', label + ' must fail with PostgreSQL insufficient_privilege (42501).')
}

async function expectNoRow(label: string, operation: PromiseLike<{ data: unknown; error: { code?: string } | null }>) {
  const result = await operation
  if (result.error) throw new Error(label + ' returned an unexpected API error (' + result.error.code + ').')
  assert(result.data === null, label + ' unexpectedly affected or returned another owner\'s row.')
}

async function expectEmpty(label: string, operation: PromiseLike<{ data: unknown[] | null; error: { code?: string } | null }>) {
  const result = await operation
  if (result.error) throw new Error(label + ' returned an unexpected API error (' + result.error.code + ').')
  assert((result.data ?? []).length === 0, label + ' exposed another owner\'s rows.')
}

async function expectPresent(client: Client, table: string, id: string, label: string) {
  const { data, error } = await client.from(table).select('id').eq('id', id).maybeSingle()
  if (error) throw new Error(label + ' lookup failed (' + error.code + ').')
  assert(Boolean(data), label + ' was unexpectedly missing.')
}

async function expectMissing(client: Client, table: string, id: string, label: string) {
  const { data, error } = await client.from(table).select('id').eq('id', id).maybeSingle()
  if (error) throw new Error(label + ' lookup failed (' + error.code + ').')
  assert(data === null, label + ' still exists after deletion.')
}

async function deleteCreated(client: Client, table: string, ids: string[]) {
  for (const id of [...ids].reverse()) {
    const { error } = await client.from(table).delete().eq('id', id)
    if (error) throw new Error(table + ' cleanup failed (' + error.code + ').')
  }
}

async function cleanup(client: Client, rows: CreatedRows) {
  const errors: string[] = []
  for (const [table, ids] of [
    ['checklist_items', rows.canonicalChecklists],
    ['task_checklist_items', rows.legacyChecklists],
    ['tasks', rows.tasks],
    ['projects', rows.projects],
  ] as const) {
    try {
      await deleteCreated(client, table, ids)
    } catch (error) {
      errors.push(error instanceof Error ? error.message : table + ' cleanup failed.')
    }
  }
  return errors
}

async function signIn(client: Client, credentials: OwnerCredentials, label: string) {
  const { data, error } = await client.auth.signInWithPassword(credentials)
  if (error || !data.user) throw new Error(label + ' could not authenticate to the isolated target.')
  return data.user
}

export async function runOrganizationAcceptance(config: AcceptanceConfig) {
  const clientOptions = {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  }
  const ownerA = createClient(config.url, config.anonKey, clientOptions)
  const ownerB = createClient(config.url, config.anonKey, clientOptions)
  const rowsA = createTracker()
  const rowsB = createTracker()
  const runMarker = '__personal_os_acceptance_' + randomUUID() + '__'
  let runFailure: string | null = null

  try {
    const userA = await signIn(ownerA, config.ownerA, 'Owner A')
    const userB = await signIn(ownerB, config.ownerB, 'Owner B')
    assert(userA.id !== userB.id, 'Owner A and Owner B resolved to the same Auth user.')

    const projectA = await insertOwnedRow(ownerA, 'projects', {
      user_id: userA.id,
      name: runMarker + 'owner_a_project',
      description: 'Disposable PostgREST acceptance fixture',
    }, rowsA.projects)

    const projectB = await insertOwnedRow(ownerB, 'projects', {
      user_id: userB.id,
      name: runMarker + 'owner_b_project',
      description: 'Disposable PostgREST acceptance fixture',
    }, rowsB.projects)

    const projectARead = await ownerA.from('projects').select('id,user_id,name').eq('id', projectA.id).single()
    assert(!projectARead.error && projectARead.data?.user_id === userA.id, 'Owner A could not read its own project.')
    const projectBRead = await ownerB.from('projects').select('id,user_id,name').eq('id', projectB.id).single()
    assert(!projectBRead.error && projectBRead.data?.user_id === userB.id, 'Owner B could not read its own project.')

    await expectEmpty('Owner B project SELECT isolation', ownerB.from('projects').select('id').eq('id', projectA.id))
    await expectEmpty('Owner A project SELECT isolation', ownerA.from('projects').select('id').eq('id', projectB.id))
    await expectRlsDenied('Owner A project owner spoof', ownerA.from('projects').insert({
      user_id: userB.id,
      name: runMarker + 'owner_spoof_project',
    }).select('id').single())
    await expectRlsDenied('Owner B project owner spoof', ownerB.from('projects').insert({
      user_id: userA.id,
      name: runMarker + 'owner_spoof_project',
    }).select('id').single())
    await expectNoRow('Owner B project UPDATE isolation', ownerB.from('projects').update({ name: runMarker + 'foreign_update' }).eq('id', projectA.id).select('id').maybeSingle())
    await expectNoRow('Owner A project UPDATE isolation', ownerA.from('projects').update({ name: runMarker + 'foreign_update' }).eq('id', projectB.id).select('id').maybeSingle())
    await expectNoRow('Owner B project DELETE isolation', ownerB.from('projects').delete().eq('id', projectA.id).select('id').maybeSingle())
    await expectNoRow('Owner A project DELETE isolation', ownerA.from('projects').delete().eq('id', projectB.id).select('id').maybeSingle())

    const projectAUpdate = await ownerA.from('projects').update({ name: runMarker + 'owner_a_project_updated' }).eq('id', projectA.id).select('id,name').single()
    assert(!projectAUpdate.error && projectAUpdate.data?.name === runMarker + 'owner_a_project_updated', 'Owner A project UPDATE failed.')
    const projectBUpdate = await ownerB.from('projects').update({ name: runMarker + 'owner_b_project_updated' }).eq('id', projectB.id).select('id,name').single()
    assert(!projectBUpdate.error && projectBUpdate.data?.name === runMarker + 'owner_b_project_updated', 'Owner B project UPDATE failed.')

    const taskA = await insertOwnedRow(ownerA, 'tasks', {
      user_id: userA.id, project_id: projectA.id, title: runMarker + 'owner_a_root',
    }, rowsA.tasks)
    const taskB = await insertOwnedRow(ownerB, 'tasks', {
      user_id: userB.id, project_id: projectB.id, title: runMarker + 'owner_b_root',
    }, rowsB.tasks)

    await expectEmpty('Owner B task SELECT isolation', ownerB.from('tasks').select('id').eq('id', taskA.id))
    await expectEmpty('Owner A task SELECT isolation', ownerA.from('tasks').select('id').eq('id', taskB.id))
    await expectRlsDenied('Owner B cannot attach a task to Owner A project', ownerB.from('tasks').insert({
      user_id: userB.id, project_id: projectA.id, title: runMarker + 'foreign_project_task',
    }).select('id').single())
    await expectRlsDenied('Owner A cannot attach a task to Owner B project', ownerA.from('tasks').insert({
      user_id: userA.id, project_id: projectB.id, title: runMarker + 'foreign_project_task',
    }).select('id').single())
    await expectRlsDenied('Owner B cannot use Owner A parent', ownerB.from('tasks').insert({
      user_id: userB.id, project_id: projectB.id, parent_task_id: taskA.id, title: runMarker + 'foreign_parent',
    }).select('id').single())
    await expectRlsDenied('Owner A cannot use Owner B parent', ownerA.from('tasks').insert({
      user_id: userA.id, project_id: projectA.id, parent_task_id: taskB.id, title: runMarker + 'foreign_parent',
    }).select('id').single())

    const childA = await insertOwnedRow(ownerA, 'tasks', {
      user_id: userA.id, project_id: projectA.id, parent_task_id: taskA.id, title: runMarker + 'owner_a_child',
    }, rowsA.tasks)
    const childDeleteA = await insertOwnedRow(ownerA, 'tasks', {
      user_id: userA.id, project_id: projectA.id, parent_task_id: taskA.id, title: runMarker + 'owner_a_child_delete',
    }, rowsA.tasks)
    const childB = await insertOwnedRow(ownerB, 'tasks', {
      user_id: userB.id, project_id: projectB.id, parent_task_id: taskB.id, title: runMarker + 'owner_b_child',
    }, rowsB.tasks)

    const taskAUpdate = await ownerA.from('tasks').update({ title: runMarker + 'owner_a_root_updated' }).eq('id', taskA.id).select('id,title').single()
    assert(!taskAUpdate.error && taskAUpdate.data?.title === runMarker + 'owner_a_root_updated', 'Owner A task UPDATE failed.')
    const childAUpdate = await ownerA.from('tasks').update({ title: runMarker + 'owner_a_child_updated' }).eq('id', childA.id).select('id,title').single()
    assert(!childAUpdate.error && childAUpdate.data?.title === runMarker + 'owner_a_child_updated', 'Owner A subtask UPDATE failed.')
    const taskBUpdate = await ownerB.from('tasks').update({ title: runMarker + 'owner_b_root_updated' }).eq('id', taskB.id).select('id,title').single()
    assert(!taskBUpdate.error && taskBUpdate.data?.title === runMarker + 'owner_b_root_updated', 'Owner B task UPDATE failed.')
    const childBUpdate = await ownerB.from('tasks').update({ title: runMarker + 'owner_b_child_updated' }).eq('id', childB.id).select('id,title').single()
    assert(!childBUpdate.error && childBUpdate.data?.title === runMarker + 'owner_b_child_updated', 'Owner B subtask UPDATE failed.')
    await expectPresent(ownerB, 'tasks', childB.id, 'Owner B subtask after update')
    await expectEmpty('Owner B subtask SELECT isolation', ownerB.from('tasks').select('id').eq('id', childA.id))
    await expectEmpty('Owner A subtask SELECT isolation', ownerA.from('tasks').select('id').eq('id', childB.id))
    await expectNoRow('Owner B task UPDATE isolation', ownerB.from('tasks').update({ title: runMarker + 'foreign_update' }).eq('id', taskA.id).select('id').maybeSingle())
    await expectNoRow('Owner A task UPDATE isolation', ownerA.from('tasks').update({ title: runMarker + 'foreign_update' }).eq('id', taskB.id).select('id').maybeSingle())
    await expectNoRow('Owner B subtask UPDATE isolation', ownerB.from('tasks').update({ title: runMarker + 'foreign_update' }).eq('id', childA.id).select('id').maybeSingle())
    await expectNoRow('Owner A subtask UPDATE isolation', ownerA.from('tasks').update({ title: runMarker + 'foreign_update' }).eq('id', childB.id).select('id').maybeSingle())
    await expectNoRow('Owner B task DELETE isolation', ownerB.from('tasks').delete().eq('id', taskA.id).select('id').maybeSingle())
    await expectNoRow('Owner A task DELETE isolation', ownerA.from('tasks').delete().eq('id', taskB.id).select('id').maybeSingle())
    await expectNoRow('Owner B subtask DELETE isolation', ownerB.from('tasks').delete().eq('id', childA.id).select('id').maybeSingle())
    await expectNoRow('Owner A subtask DELETE isolation', ownerA.from('tasks').delete().eq('id', childB.id).select('id').maybeSingle())

    const canonicalA = await insertOwnedRow(ownerA, 'checklist_items', {
      user_id: userA.id, task_id: childA.id, title: runMarker + 'canonical_a', position: 1,
    }, rowsA.canonicalChecklists)
    const canonicalCascadeA = await insertOwnedRow(ownerA, 'checklist_items', {
      user_id: userA.id, task_id: childA.id, title: runMarker + 'canonical_cascade_a', position: 2,
    }, rowsA.canonicalChecklists)
    const legacyA = await insertOwnedRow(ownerA, 'task_checklist_items', {
      user_id: userA.id, task_id: childA.id, title: runMarker + 'legacy_a', position: 1,
    }, rowsA.legacyChecklists)
    const legacyCascadeA = await insertOwnedRow(ownerA, 'task_checklist_items', {
      user_id: userA.id, task_id: childA.id, title: runMarker + 'legacy_cascade_a', position: 2,
    }, rowsA.legacyChecklists)
    const canonicalB = await insertOwnedRow(ownerB, 'checklist_items', {
      user_id: userB.id, task_id: childB.id, title: runMarker + 'canonical_b', position: 1,
    }, rowsB.canonicalChecklists)
    const legacyB = await insertOwnedRow(ownerB, 'task_checklist_items', {
      user_id: userB.id, task_id: childB.id, title: runMarker + 'legacy_b', position: 1,
    }, rowsB.legacyChecklists)

    const canonicalUpdate = await ownerA.from('checklist_items').update({ title: runMarker + 'canonical_a_updated', is_completed: true }).eq('id', canonicalA.id).select('id,title,is_completed').single()
    assert(!canonicalUpdate.error && canonicalUpdate.data?.is_completed === true, 'Owner A canonical checklist UPDATE failed.')
    const legacyUpdate = await ownerA.from('task_checklist_items').update({ title: runMarker + 'legacy_a_updated', is_completed: true }).eq('id', legacyA.id).select('id,title,is_completed').single()
    assert(!legacyUpdate.error && legacyUpdate.data?.is_completed === true, 'Owner A legacy checklist UPDATE failed.')
    const canonicalBUpdate = await ownerB.from('checklist_items').update({ is_completed: true }).eq('id', canonicalB.id).select('id,is_completed').single()
    assert(!canonicalBUpdate.error && canonicalBUpdate.data?.is_completed === true, 'Owner B canonical checklist UPDATE failed.')
    const legacyBUpdate = await ownerB.from('task_checklist_items').update({ is_completed: true }).eq('id', legacyB.id).select('id,is_completed').single()
    assert(!legacyBUpdate.error && legacyBUpdate.data?.is_completed === true, 'Owner B legacy checklist UPDATE failed.')

    await expectEmpty('Owner B canonical checklist SELECT isolation', ownerB.from('checklist_items').select('id').eq('id', canonicalA.id))
    await expectEmpty('Owner A canonical checklist SELECT isolation', ownerA.from('checklist_items').select('id').eq('id', canonicalB.id))
    await expectEmpty('Owner B legacy checklist SELECT isolation', ownerB.from('task_checklist_items').select('id').eq('id', legacyA.id))
    await expectEmpty('Owner A legacy checklist SELECT isolation', ownerA.from('task_checklist_items').select('id').eq('id', legacyB.id))

    await expectRlsDenied('Owner B cannot attach canonical checklist to Owner A task', ownerB.from('checklist_items').insert({
      user_id: userB.id, task_id: childA.id, title: runMarker + 'foreign_canonical',
    }).select('id').single())
    await expectRlsDenied('Owner A cannot attach canonical checklist to Owner B task', ownerA.from('checklist_items').insert({
      user_id: userA.id, task_id: childB.id, title: runMarker + 'foreign_canonical',
    }).select('id').single())
    await expectRlsDenied('Owner B cannot attach legacy checklist to Owner A task', ownerB.from('task_checklist_items').insert({
      user_id: userB.id, task_id: childA.id, title: runMarker + 'foreign_legacy',
    }).select('id').single())
    await expectRlsDenied('Owner A cannot attach legacy checklist to Owner B task', ownerA.from('task_checklist_items').insert({
      user_id: userA.id, task_id: childB.id, title: runMarker + 'foreign_legacy',
    }).select('id').single())

    await expectNoRow('Owner B canonical checklist UPDATE isolation', ownerB.from('checklist_items').update({ title: runMarker + 'foreign_update' }).eq('id', canonicalA.id).select('id').maybeSingle())
    await expectNoRow('Owner A canonical checklist UPDATE isolation', ownerA.from('checklist_items').update({ title: runMarker + 'foreign_update' }).eq('id', canonicalB.id).select('id').maybeSingle())
    await expectNoRow('Owner B legacy checklist UPDATE isolation', ownerB.from('task_checklist_items').update({ title: runMarker + 'foreign_update' }).eq('id', legacyA.id).select('id').maybeSingle())
    await expectNoRow('Owner A legacy checklist UPDATE isolation', ownerA.from('task_checklist_items').update({ title: runMarker + 'foreign_update' }).eq('id', legacyB.id).select('id').maybeSingle())
    await expectNoRow('Owner B canonical checklist DELETE isolation', ownerB.from('checklist_items').delete().eq('id', canonicalA.id).select('id').maybeSingle())
    await expectNoRow('Owner A canonical checklist DELETE isolation', ownerA.from('checklist_items').delete().eq('id', canonicalB.id).select('id').maybeSingle())
    await expectNoRow('Owner B legacy checklist DELETE isolation', ownerB.from('task_checklist_items').delete().eq('id', legacyA.id).select('id').maybeSingle())
    await expectNoRow('Owner A legacy checklist DELETE isolation', ownerA.from('task_checklist_items').delete().eq('id', legacyB.id).select('id').maybeSingle())

    const canonicalDelete = await ownerA.from('checklist_items').delete().eq('id', canonicalA.id).select('id').single()
    assert(!canonicalDelete.error && canonicalDelete.data?.id === canonicalA.id, 'Owner A canonical checklist DELETE failed.')
    const legacyDelete = await ownerA.from('task_checklist_items').delete().eq('id', legacyA.id).select('id').single()
    assert(!legacyDelete.error && legacyDelete.data?.id === legacyA.id, 'Owner A legacy checklist DELETE failed.')
    const canonicalBDelete = await ownerB.from('checklist_items').delete().eq('id', canonicalB.id).select('id').single()
    assert(!canonicalBDelete.error && canonicalBDelete.data?.id === canonicalB.id, 'Owner B canonical checklist DELETE failed.')
    const legacyBDelete = await ownerB.from('task_checklist_items').delete().eq('id', legacyB.id).select('id').single()
    assert(!legacyBDelete.error && legacyBDelete.data?.id === legacyB.id, 'Owner B legacy checklist DELETE failed.')

    const childDelete = await ownerA.from('tasks').delete().eq('id', childDeleteA.id).select('id').single()
    assert(!childDelete.error && childDelete.data?.id === childDeleteA.id, 'Owner A could not delete its own subtask.')
    await expectPresent(ownerA, 'tasks', taskA.id, 'Owner A root after subtask deletion')
    await expectPresent(ownerA, 'tasks', childA.id, 'Owner A retained subtask')
    await expectPresent(ownerB, 'tasks', taskB.id, 'Owner B root after Owner A operations')

    const rootDeleteA = await ownerA.from('tasks').delete().eq('id', taskA.id).select('id').single()
    assert(!rootDeleteA.error && rootDeleteA.data?.id === taskA.id, 'Owner A could not delete its own root task.')
    await expectMissing(ownerA, 'tasks', childA.id, 'Cascaded Owner A subtask')
    await expectMissing(ownerA, 'checklist_items', canonicalCascadeA.id, 'Canonical checklist cascade')
    await expectMissing(ownerA, 'task_checklist_items', legacyCascadeA.id, 'Legacy checklist cascade')
    await expectPresent(ownerB, 'tasks', taskB.id, 'Owner B task after Owner A cascade')

    const childDeleteB = await ownerB.from('tasks').delete().eq('id', childB.id).select('id').single()
    assert(!childDeleteB.error && childDeleteB.data?.id === childB.id, 'Owner B could not delete its own subtask.')
    const rootDeleteB = await ownerB.from('tasks').delete().eq('id', taskB.id).select('id').single()
    assert(!rootDeleteB.error && rootDeleteB.data?.id === taskB.id, 'Owner B could not delete its own root task.')

    const projectDeleteA = await ownerA.from('projects').delete().eq('id', projectA.id).select('id').single()
    assert(!projectDeleteA.error && projectDeleteA.data?.id === projectA.id, 'Owner A could not delete its own project.')
    const projectDeleteB = await ownerB.from('projects').delete().eq('id', projectB.id).select('id').single()
    assert(!projectDeleteB.error && projectDeleteB.data?.id === projectB.id, 'Owner B could not delete its own project.')
    await expectMissing(ownerA, 'projects', projectA.id, 'Deleted Owner A project')
    await expectMissing(ownerB, 'projects', projectB.id, 'Deleted Owner B project')
  } catch (error) {
    runFailure = error instanceof Error ? error.message : 'Unknown PostgREST acceptance failure.'
  }

  const cleanupErrors = [
    ...await cleanup(ownerA, rowsA),
    ...await cleanup(ownerB, rowsB),
  ]

  if (runFailure || cleanupErrors.length) {
    const details = [runFailure, ...cleanupErrors].filter(Boolean).join(' | ')
    throw new Error(details)
  }

  return {
    projectRef: config.projectRef,
    ownersAuthenticated: 2,
    projectCrud: true,
    taskAndSubtaskCrud: true,
    canonicalAndLegacyChecklistCrud: true,
    crossOwnerIsolation: true,
    cleanupCompleted: true,
  }
}

async function main() {
  const config = loadAcceptanceConfig(process.env, process.argv.slice(2))
  const result = await runOrganizationAcceptance(config)
  console.log('Organization PostgREST acceptance passed for isolated project ' + result.projectRef + '.')
  console.log('Two owners; project/task/subtask/canonical+legacy checklist CRUD; cross-owner SELECT/INSERT/UPDATE/DELETE; cleanup completed.')
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : 'Organization PostgREST acceptance failed.')
    process.exitCode = 1
  })
}
