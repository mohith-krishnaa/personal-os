import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import {
  EXPECTED_SOURCE_PROJECT_REF,
  REQUIRED_EXTENSION_NAMES,
  REQUIRED_ROW_COUNT_KEYS,
  REQUIRED_SOURCE_MIGRATIONS,
  verifyBackupManifest,
} from './verify-backup-manifest'

const repositoryCommit = 'a'.repeat(40)
const repositoryVersions = [...REQUIRED_SOURCE_MIGRATIONS, '20261121000500'].sort()
const artifactDefinitions = [
  { path: 'roles.sql', commandId: 'roles', content: '-- roles export\n' },
  { path: 'schema.sql', commandId: 'schema', content: '-- schema export\n' },
  { path: 'data.sql', commandId: 'data', content: '-- data export\n' },
  { path: 'migration-history-schema.sql', commandId: 'migration-history-schema', content: '-- migration schema export\n' },
  { path: 'migration-history-data.sql', commandId: 'migration-history-data', content: '-- migration history data export\n' },
]

type Fixture = {
  baseDir: string
  repoRoot: string
  migrationsDir: string
  privateDir: string
  artifactsDir: string
  manifestPath: string
  manifest: Record<string, any>
}

function hash(content: string) {
  return createHash('sha256').update(content).digest('hex')
}

function createFixture(): Fixture {
  const baseDir = mkdtempSync(join(tmpdir(), 'personal-os-backup-manifest-'))
  const repoRoot = join(baseDir, 'repo')
  const migrationsDir = join(repoRoot, 'supabase', 'migrations')
  const privateDir = join(baseDir, 'private')
  const artifactsDir = join(privateDir, 'artifacts')
  const manifestPath = join(privateDir, 'manifest.json')

  mkdirSync(migrationsDir, { recursive: true })
  mkdirSync(artifactsDir, { recursive: true })

  for (const version of repositoryVersions) {
    writeFileSync(join(migrationsDir, version + '_fixture.sql'), '-- fixture migration\n')
  }

  const commands = artifactDefinitions.map(artifact => ({
    id: artifact.commandId,
    targetProjectRef: EXPECTED_SOURCE_PROJECT_REF,
    targetLineVerified: true,
    exitCode: 0,
  }))

  const artifacts = artifactDefinitions.map(artifact => {
    writeFileSync(join(artifactsDir, artifact.path), artifact.content)
    return {
      path: artifact.path,
      commandId: artifact.commandId,
      sizeBytes: Buffer.byteLength(artifact.content),
      sha256: hash(artifact.content),
    }
  })

  const rowCounts = Object.fromEntries(REQUIRED_ROW_COUNT_KEYS.map(key => [key, 0]))
  const manifest: Record<string, any> = {
    formatVersion: 1,
    source: {
      projectRef: EXPECTED_SOURCE_PROJECT_REF,
      region: 'ap-southeast-1',
      postgresVersion: '17.11.0.003',
      supabaseCliVersion: '3.2.0',
      postgresClientVersion: 'psql (PostgreSQL) 17.6',
      exportedAtUtc: '2026-11-21T02:00:00.000Z',
      repositoryCommit,
      appliedMigrationVersions: [...REQUIRED_SOURCE_MIGRATIONS],
      repositoryMigrationVersions: [...repositoryVersions],
      extensions: REQUIRED_EXTENSION_NAMES.map(name => ({ name, version: '1.0' })),
      rowCounts,
    },
    commands,
    artifacts,
  }

  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2))
  return { baseDir, repoRoot, migrationsDir, privateDir, artifactsDir, manifestPath, manifest }
}

function writeManifest(fixture: Fixture) {
  writeFileSync(fixture.manifestPath, JSON.stringify(fixture.manifest, null, 2))
}

async function verify(fixture: Fixture, overrides: Partial<Parameters<typeof verifyBackupManifest>[0]> = {}) {
  return verifyBackupManifest({
    manifestPath: fixture.manifestPath,
    artifactsDir: fixture.artifactsDir,
    migrationsDir: fixture.migrationsDir,
    repoRoot: fixture.repoRoot,
    expectedCommit: repositoryCommit,
    ...overrides,
  })
}

function clean(fixture: Fixture) {
  rmSync(fixture.baseDir, { recursive: true, force: true })
}

test('verifies all required dump artifacts and migration inventories', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))

  const result = await verify(fixture)
  assert.equal(result.ok, true, result.errors.join(' '))
  assert.equal(result.artifactsVerified, 5)
  assert.equal(result.sourceMigrationCount, 8)
  assert.equal(result.repositoryMigrationCount, repositoryVersions.length)
})

test('rejects a missing required artifact', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  rmSync(join(fixture.artifactsDir, 'roles.sql'))

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /roles\.sql/)
})

test('rejects an artifact whose byte size differs from the manifest', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  writeFileSync(join(fixture.artifactsDir, 'roles.sql'), '-- changed size\n')

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /byte size/)
})

test('rejects an artifact whose SHA-256 differs from the manifest', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  writeFileSync(join(fixture.artifactsDir, 'roles.sql'), '-- other content\n')

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /SHA-256/)
})

test('rejects a non-zero export command exit status', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.commands[0].exitCode = 1
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /exitCode 0/)
})

test('rejects a command whose recorded Target line was not verified', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.commands[0].targetLineVerified = false
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /Target line/)
})

test('rejects a command targeting a different project', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.commands[0].targetProjectRef = 'abcdefghijklmnopqrst'
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /Target line/)
})

test('rejects a source migration inventory that differs from the live baseline', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.source.appliedMigrationVersions.pop()
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /appliedMigrationVersions/)
})

test('rejects a repository migration inventory that differs from the checkout', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.source.repositoryMigrationVersions.pop()
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /repositoryMigrationVersions/)
})

test('rejects a migration filename outside the required version format', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  writeFileSync(join(fixture.migrationsDir, 'not-a-version.sql'), '-- invalid\n')

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /Migration filename/)
})

test('rejects unsafe artifact paths', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.artifacts[0].path = '../roles.sql'
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /safe relative paths/)
})

test('rejects symbolic links in artifact paths', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  const original = join(fixture.artifactsDir, 'roles.sql')
  const outside = join(fixture.privateDir, 'outside.sql')
  writeFileSync(outside, '-- outside artifact\n')
  rmSync(original)
  symlinkSync(outside, original)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /Symbolic links|symbolic link/)
})

test('rejects artifacts stored inside the Git repository', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  const inRepo = join(fixture.repoRoot, 'private-backup')
  mkdirSync(inRepo)
  for (const artifact of artifactDefinitions) {
    writeFileSync(join(inRepo, artifact.path), artifact.content)
  }

  const result = await verify(fixture, { artifactsDir: inRepo })
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /outside the Git repository/)
})

test('rejects a manifest stored inside the Git repository', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  const inRepoManifest = join(fixture.repoRoot, 'manifest.json')
  writeFileSync(inRepoManifest, JSON.stringify(fixture.manifest))

  const result = await verify(fixture, { manifestPath: inRepoManifest })
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /private manifest/)
})

test('rejects credential-like fields and connection strings in the manifest', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.source.databaseUrl = 'postgresql://user:password@example.test/db'
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /credential-like field name/)
})

test('rejects incomplete row-count inventory', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  delete fixture.manifest.source.rowCounts['vault.secrets']
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /rowCounts/)
})

test('rejects a manifest tied to a different Git commit', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))

  const result = await verify(fixture, { expectedCommit: 'b'.repeat(40) })
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /current Git HEAD/)
})

test('rejects unsupported restore claims instead of treating backup verification as restore proof', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.restoreStatus = 'verified'
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /unsupported field/)
})

test('rejects a source project ref other than the configured production source', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.source.projectRef = 'abcdefghijklmnopqrst'
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /source.projectRef/)
})

test('rejects non-zero and non-integer row counts', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.source.rowCounts['public.tasks'] = -1
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /non-negative safe integer/)
})

test('rejects an extension inventory that omits a required extension', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.source.extensions.pop()
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /required non-plpgsql extension/)
})

test('rejects a malformed export timestamp', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.source.exportedAtUtc = '2026-11-21T02:00:00+05:30'
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /canonical UTC ISO timestamp/)
})

test('rejects duplicate artifact paths', async t => {
  const fixture = createFixture()
  t.after(() => clean(fixture))
  fixture.manifest.artifacts[1].path = 'roles.sql'
  writeManifest(fixture)

  const result = await verify(fixture)
  assert.equal(result.ok, false)
  assert.match(result.errors.join(' '), /wrong export command|duplicate path/)
})
