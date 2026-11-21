import { createHash } from 'node:crypto'
import { createReadStream, lstatSync, readFileSync, readdirSync, realpathSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { dirname, isAbsolute, join, parse, relative, resolve, sep } from 'node:path'
import { pathToFileURL } from 'node:url'

export const EXPECTED_SOURCE_PROJECT_REF = 'gujzvkyytxsnervovvrt'

export const REQUIRED_SOURCE_MIGRATIONS = [
  '20260829182309',
  '20260830085036',
  '20260830103327',
  '20260830114218',
  '20260830120132',
  '20260830123420',
  '20260830141616',
  '20260905162251',
] as const

export const REQUIRED_EXTENSION_NAMES = [
  'pg_stat_statements',
  'pgcrypto',
  'supabase_vault',
  'uuid-ossp',
] as const

export const REQUIRED_ROW_COUNT_KEYS = [
  'public.activity_events',
  'public.goals',
  'public.notes',
  'public.notifications',
  'public.profiles',
  'public.progress_entries',
  'public.projects',
  'public.reminders',
  'public.tasks',
  'auth.users',
  'auth.instances',
  'auth.identities',
  'auth.refresh_tokens',
  'auth.sessions',
  'auth.audit_log_entries',
  'auth.mfa_factors',
  'auth.mfa_challenges',
  'auth.mfa_amr_claims',
  'auth.sso_providers',
  'auth.sso_domains',
  'auth.saml_providers',
  'auth.saml_relay_states',
  'auth.flow_state',
  'auth.one_time_tokens',
  'auth.oauth_clients',
  'auth.oauth_authorizations',
  'auth.oauth_consents',
  'auth.oauth_client_states',
  'auth.custom_oauth_providers',
  'auth.webauthn_credentials',
  'auth.webauthn_challenges',
  'auth.scim_users',
  'auth.scim_tokens',
  'auth.mfa_recovery_code_sets',
  'auth.mfa_recovery_codes',
  'storage.buckets',
  'storage.objects',
  'storage.s3_multipart_uploads',
  'storage.s3_multipart_uploads_parts',
  'storage.buckets_analytics',
  'storage.buckets_vectors',
  'storage.vector_indexes',
  'vault.secrets',
  'realtime.messages',
  'realtime.subscription',
] as const

export const REQUIRED_EMPTY_MANAGED_ROW_COUNT_KEYS = [
  'auth.users',
  'auth.instances',
  'auth.identities',
  'auth.refresh_tokens',
  'auth.sessions',
  'auth.audit_log_entries',
  'auth.mfa_factors',
  'auth.mfa_challenges',
  'auth.mfa_amr_claims',
  'auth.sso_providers',
  'auth.sso_domains',
  'auth.saml_providers',
  'auth.saml_relay_states',
  'auth.flow_state',
  'auth.one_time_tokens',
  'auth.oauth_clients',
  'auth.oauth_authorizations',
  'auth.oauth_consents',
  'auth.oauth_client_states',
  'auth.custom_oauth_providers',
  'auth.webauthn_credentials',
  'auth.webauthn_challenges',
  'auth.scim_users',
  'auth.scim_tokens',
  'auth.mfa_recovery_code_sets',
  'auth.mfa_recovery_codes',
  'storage.buckets',
  'storage.objects',
  'storage.s3_multipart_uploads',
  'storage.s3_multipart_uploads_parts',
  'storage.buckets_analytics',
  'storage.buckets_vectors',
  'storage.vector_indexes',
  'vault.secrets',
  'realtime.messages',
  'realtime.subscription',
] as const

const REQUIRED_COMMANDS = [
  'roles',
  'schema',
  'data',
  'migration-history-schema',
  'migration-history-data',
] as const

const REQUIRED_ARTIFACTS = [
  { path: 'roles.sql', commandId: 'roles' },
  { path: 'schema.sql', commandId: 'schema' },
  { path: 'data.sql', commandId: 'data' },
  { path: 'migration-history-schema.sql', commandId: 'migration-history-schema' },
  { path: 'migration-history-data.sql', commandId: 'migration-history-data' },
] as const

const MAX_MANIFEST_BYTES = 1024 * 1024

type JsonRecord = Record<string, unknown>

export type BackupManifestVerificationOptions = {
  manifestPath: string
  artifactsDir: string
  migrationsDir: string
  repoRoot: string
  expectedCommit?: string
}

export type BackupManifestVerificationResult = {
  ok: boolean
  errors: string[]
  artifactsVerified: number
  repositoryMigrationCount: number
  sourceMigrationCount: number
}

function fail(message: string): never {
  throw new Error(message)
}

function asRecord(value: unknown, label: string): JsonRecord {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(label + ' must be a JSON object.')
  }
  return value as JsonRecord
}

function assertExactKeys(record: JsonRecord, expected: readonly string[], label: string) {
  const expectedSet = new Set(expected)
  const actual = Object.keys(record)
  const unexpected = actual.filter(key => !expectedSet.has(key))
  const missing = expected.filter(key => !Object.hasOwn(record, key))

  if (unexpected.length) {
    const sensitive = unexpected.find(key =>
      /(password|connection.?string|database.?url|api.?key|secret|token|jwt|credential|root.?key|encryption.?key|private.?key)/i.test(key),
    )
    if (sensitive) fail(label + ' contains a forbidden credential-like field name.')
    fail(label + ' contains unsupported field(s): ' + unexpected.join(', ') + '.')
  }
  if (missing.length) fail(label + ' is missing required field(s): ' + missing.join(', ') + '.')
}

function requiredString(value: unknown, label: string): string {
  if (typeof value !== 'string' || !value.trim()) fail(label + ' must be a non-empty string.')
  return value
}

function assertNoCredentialValues(value: unknown, label = 'manifest') {
  if (typeof value === 'string') {
    if (
      /postgres(?:ql)?:\/\/[^\s/@:]+:[^\s/@]+@/i.test(value) ||
      /\bsb_secret_[A-Za-z0-9_-]+/i.test(value) ||
      /\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{8,}\b/.test(value)
    ) {
      fail(label + ' appears to contain credential material; remove it and rotate the exposed credential if necessary.')
    }
    return
  }

  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoCredentialValues(item, label + '[' + index + ']'))
    return
  }

  if (value && typeof value === 'object') {
    for (const [key, item] of Object.entries(value as JsonRecord)) {
      assertNoCredentialValues(item, label + '.' + key)
    }
  }
}

function isWithin(parent: string, candidate: string): boolean {
  const rel = relative(parent, candidate)
  return rel === '' || (rel !== '..' && !rel.startsWith('..' + sep) && !isAbsolute(rel))
}

function assertNoSymlinkComponents(targetPath: string) {
  const absolute = resolve(targetPath)
  const root = parse(absolute).root
  let current = root

  for (const segment of absolute.slice(root.length).split(sep).filter(Boolean)) {
    current = join(current, segment)
    const stat = lstatSync(current)
    if (stat.isSymbolicLink()) fail('Symbolic links are not allowed in manifest or artifact paths.')
  }
}

function readRepositoryMigrationVersions(migrationsDir: string): string[] {
  const entries = readdirSync(migrationsDir, { withFileTypes: true })
  const versions: string[] = []

  for (const entry of entries) {
    if (!entry.name.endsWith('.sql')) continue
    if (!entry.isFile()) fail('Migration SQL entries must be regular files: ' + entry.name)
    const match = entry.name.match(/^(\d{14})_[a-z0-9_]+\.sql$/)
    if (!match) fail('Migration filename does not match the required 14-digit format: ' + entry.name)
    versions.push(match[1])
  }

  if (!versions.length) fail('No numbered SQL migrations were found in supabase/migrations.')
  versions.sort()
  if (new Set(versions).size !== versions.length) fail('Repository migration versions must be unique.')
  return versions
}

function assertVersionList(value: unknown, expected: readonly string[], label: string) {
  if (!Array.isArray(value) || value.some(item => typeof item !== 'string')) {
    fail(label + ' must be an array of migration version strings.')
  }
  const versions = value as string[]
  if (versions.some(version => !/^\d{14}$/.test(version))) {
    fail(label + ' contains a version that is not exactly 14 digits.')
  }
  if (new Set(versions).size !== versions.length) fail(label + ' contains duplicate versions.')
  if (versions.some((version, index) => index > 0 && versions[index - 1] >= version)) {
    fail(label + ' must be sorted in ascending order.')
  }
  if (versions.length !== expected.length || versions.some((version, index) => version !== expected[index])) {
    fail(label + ' does not match the required migration inventory.')
  }
}

function validateManifestShape(value: unknown, repositoryVersions: string[], expectedCommit?: string) {
  const manifest = asRecord(value, 'manifest')
  assertExactKeys(manifest, ['formatVersion', 'source', 'commands', 'artifacts'], 'manifest')
  if (manifest.formatVersion !== 1) fail('Unsupported backup manifest formatVersion; expected 1.')

  const source = asRecord(manifest.source, 'source')
  assertExactKeys(source, [
    'projectRef',
    'region',
    'postgresVersion',
    'supabaseCliVersion',
    'postgresClientVersion',
    'exportedAtUtc',
    'repositoryCommit',
    'appliedMigrationVersions',
    'repositoryMigrationVersions',
    'extensions',
    'rowCounts',
  ], 'source')

  if (source.projectRef !== EXPECTED_SOURCE_PROJECT_REF) {
    fail('source.projectRef does not match the configured source project.')
  }
  requiredString(source.region, 'source.region')
  requiredString(source.postgresVersion, 'source.postgresVersion')
  requiredString(source.supabaseCliVersion, 'source.supabaseCliVersion')
  requiredString(source.postgresClientVersion, 'source.postgresClientVersion')

  const exportedAtUtc = requiredString(source.exportedAtUtc, 'source.exportedAtUtc')
  const exportedDate = new Date(exportedAtUtc)
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(exportedAtUtc) ||
      Number.isNaN(exportedDate.getTime()) ||
      exportedDate.toISOString() !== exportedAtUtc) {
    fail('source.exportedAtUtc must be a valid canonical UTC ISO timestamp.')
  }

  const repositoryCommit = requiredString(source.repositoryCommit, 'source.repositoryCommit')
  if (!/^[0-9a-f]{40}$/.test(repositoryCommit)) {
    fail('source.repositoryCommit must be a 40-character lowercase Git commit SHA.')
  }
  if (expectedCommit && repositoryCommit !== expectedCommit) {
    fail('source.repositoryCommit does not match the current Git HEAD.')
  }

  assertVersionList(
    source.appliedMigrationVersions,
    REQUIRED_SOURCE_MIGRATIONS,
    'source.appliedMigrationVersions',
  )
  assertVersionList(
    source.repositoryMigrationVersions,
    repositoryVersions,
    'source.repositoryMigrationVersions',
  )

  const extensions = source.extensions
  if (!Array.isArray(extensions)) fail('source.extensions must be an array.')
  const extensionNames: string[] = []
  for (const [index, value] of extensions.entries()) {
    const extension = asRecord(value, 'source.extensions[' + index + ']')
    assertExactKeys(extension, ['name', 'version'], 'source.extensions[' + index + ']')
    extensionNames.push(requiredString(extension.name, 'extension name'))
    requiredString(extension.version, 'extension version')
  }
  const sortedExtensionNames = [...extensionNames].sort()
  if (new Set(extensionNames).size !== extensionNames.length ||
      sortedExtensionNames.length !== REQUIRED_EXTENSION_NAMES.length ||
      sortedExtensionNames.some((name, index) => name !== REQUIRED_EXTENSION_NAMES[index])) {
    fail('source.extensions must contain each required non-plpgsql extension exactly once.')
  }

  const rowCounts = asRecord(source.rowCounts, 'source.rowCounts')
  assertExactKeys(rowCounts, REQUIRED_ROW_COUNT_KEYS, 'source.rowCounts')
  for (const key of REQUIRED_ROW_COUNT_KEYS) {
    const count = rowCounts[key]
    if (typeof count !== 'number' || !Number.isSafeInteger(count) || count < 0) {
      fail('source.rowCounts.' + key + ' must be a non-negative safe integer.')
    }
  }
  for (const key of REQUIRED_EMPTY_MANAGED_ROW_COUNT_KEYS) {
    if (rowCounts[key] !== 0) {
      fail('source.rowCounts.' + key + ' must be zero for this CLI logical backup path because the standard dump does not preserve all Supabase-managed and project-level data.')
    }
  }

  if (!Array.isArray(manifest.commands)) fail('commands must be an array.')
  if (manifest.commands.length !== REQUIRED_COMMANDS.length) {
    fail('commands must contain exactly the five required export commands.')
  }
  const commands = new Map<string, JsonRecord>()
  for (const [index, value] of manifest.commands.entries()) {
    const command = asRecord(value, 'commands[' + index + ']')
    assertExactKeys(command, ['id', 'targetProjectRef', 'targetLineVerified', 'exitCode'], 'commands[' + index + ']')
    const id = requiredString(command.id, 'command id')
    if (!REQUIRED_COMMANDS.includes(id as typeof REQUIRED_COMMANDS[number])) {
      fail('commands contains an unsupported export command id.')
    }
    if (commands.has(id)) fail('commands contains a duplicate export command id.')
    if (command.targetProjectRef !== source.projectRef || command.targetLineVerified !== true) {
      fail('Every export command must attest that its CLI Target line matched source.projectRef.')
    }
    if (command.exitCode !== 0) fail('Every required export command must have exitCode 0.')
    commands.set(id, command)
  }
  if (REQUIRED_COMMANDS.some(id => !commands.has(id))) {
    fail('commands is missing one or more required export command ids.')
  }

  if (!Array.isArray(manifest.artifacts)) fail('artifacts must be an array.')
  if (manifest.artifacts.length !== REQUIRED_ARTIFACTS.length) {
    fail('artifacts must contain exactly the five required dump files.')
  }

  const artifacts = new Map<string, JsonRecord>()
  for (const [index, value] of manifest.artifacts.entries()) {
    const artifact = asRecord(value, 'artifacts[' + index + ']')
    assertExactKeys(artifact, ['path', 'commandId', 'sizeBytes', 'sha256'], 'artifacts[' + index + ']')
    const artifactPath = requiredString(artifact.path, 'artifact path')
    if (
      artifactPath.includes('\\') ||
      artifactPath.startsWith('/') ||
      /^[A-Za-z]:/.test(artifactPath) ||
      artifactPath.split('/').some(segment => !segment || segment === '.' || segment === '..')
    ) {
      fail('Artifact paths must be safe relative paths without traversal or platform separators.')
    }
    const expected = REQUIRED_ARTIFACTS.find(item => item.path === artifactPath)
    if (!expected) fail('artifacts contains an unsupported artifact path.')
    if (artifact.commandId !== expected.commandId) {
      fail('Artifact ' + artifactPath + ' is associated with the wrong export command.')
    }
    if (artifacts.has(artifactPath)) fail('artifacts contains a duplicate path.')
    if (typeof artifact.sizeBytes !== 'number' || !Number.isSafeInteger(artifact.sizeBytes) || artifact.sizeBytes <= 0) {
      fail('Artifact ' + artifactPath + ' must have a positive integer sizeBytes.')
    }
    if (typeof artifact.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(artifact.sha256)) {
      fail('Artifact ' + artifactPath + ' must have a lowercase SHA-256 digest.')
    }
    artifacts.set(artifactPath, artifact)
  }

  if (REQUIRED_ARTIFACTS.some(item => !artifacts.has(item.path))) {
    fail('artifacts is missing one or more required dump files.')
  }

  return {
    sourceProjectRef: source.projectRef as string,
    repositoryMigrationCount: repositoryVersions.length,
    sourceMigrationCount: REQUIRED_SOURCE_MIGRATIONS.length,
    artifacts,
  }
}

async function sha256File(filePath: string): Promise<string> {
  const hash = createHash('sha256')
  for await (const chunk of createReadStream(filePath)) {
    hash.update(chunk)
  }
  return hash.digest('hex')
}

export async function verifyBackupManifest(
  options: BackupManifestVerificationOptions,
): Promise<BackupManifestVerificationResult> {
  try {
    const repoRoot = realpathSync(options.repoRoot)
    const manifestPath = resolve(options.manifestPath)
    const artifactsDir = resolve(options.artifactsDir)
    const migrationsDir = resolve(options.migrationsDir)

    assertNoSymlinkComponents(manifestPath)
    assertNoSymlinkComponents(artifactsDir)
    assertNoSymlinkComponents(migrationsDir)

    const manifestStat = lstatSync(manifestPath)
    if (!manifestStat.isFile() || manifestStat.size > MAX_MANIFEST_BYTES) {
      fail('Manifest must be a regular file no larger than 1 MiB.')
    }
    const realManifestPath = realpathSync(manifestPath)
    if (isWithin(repoRoot, realManifestPath)) {
      fail('The private manifest must be stored outside the Git repository.')
    }

    const artifactsStat = lstatSync(artifactsDir)
    if (!artifactsStat.isDirectory()) fail('Artifact directory must be a real directory.')
    const realArtifactsDir = realpathSync(artifactsDir)
    if (isWithin(repoRoot, realArtifactsDir)) {
      fail('Backup artifacts must be stored outside the Git repository.')
    }

    const migrationStat = lstatSync(migrationsDir)
    if (!migrationStat.isDirectory()) fail('Migration inventory path must be a directory.')
    const realMigrationsDir = realpathSync(migrationsDir)
    if (!isWithin(repoRoot, realMigrationsDir)) {
      fail('Migration inventory must come from this Git checkout.')
    }

    const repositoryVersions = readRepositoryMigrationVersions(realMigrationsDir)
    const manifestText = readFileSync(realManifestPath, 'utf8')
    let parsed: unknown
    try {
      parsed = JSON.parse(manifestText)
    } catch {
      fail('Manifest is not valid JSON.')
    }

    assertNoCredentialValues(parsed)
    const validated = validateManifestShape(parsed, repositoryVersions, options.expectedCommit)

    const artifactErrors: string[] = []
    let artifactsVerified = 0
    for (const expected of REQUIRED_ARTIFACTS) {
      const artifact = validated.artifacts.get(expected.path)
      if (!artifact) continue

      const artifactPath = join(realArtifactsDir, expected.path)
      try {
        assertNoSymlinkComponents(artifactPath)
        const stat = lstatSync(artifactPath)
        if (!stat.isFile()) {
          artifactErrors.push(expected.path + ': not a regular file.')
          continue
        }
        if (stat.size !== artifact.sizeBytes) {
          artifactErrors.push(expected.path + ': byte size does not match the manifest.')
          continue
        }
        const actualHash = await sha256File(artifactPath)
        if (actualHash !== artifact.sha256) {
          artifactErrors.push(expected.path + ': SHA-256 does not match the manifest.')
          continue
        }
        artifactsVerified += 1
      } catch {
        artifactErrors.push(expected.path + ': missing, unreadable, or contains a symbolic link.')
      }
    }

    if (artifactErrors.length) fail(artifactErrors.join(' '))
    if (artifactsVerified !== REQUIRED_ARTIFACTS.length) {
      fail('Not all required backup artifacts were verified.')
    }

    return {
      ok: true,
      errors: [],
      artifactsVerified,
      repositoryMigrationCount: validated.repositoryMigrationCount,
      sourceMigrationCount: validated.sourceMigrationCount,
    }
  } catch (error) {
    return {
      ok: false,
      errors: [error instanceof Error ? error.message : 'Backup manifest verification failed.'],
      artifactsVerified: 0,
      repositoryMigrationCount: 0,
      sourceMigrationCount: 0,
    }
  }
}

function parseArguments(args: string[]) {
  let manifestPath: string | undefined
  let artifactsDir: string | undefined

  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index]
    if (argument === '--help') return { help: true as const }
    if (argument !== '--manifest' && argument !== '--artifacts-dir') {
      fail('Unsupported argument. Use --manifest and --artifacts-dir.')
    }
    const value = args[index + 1]
    if (!value || value.startsWith('--')) fail(argument + ' requires a path.')
    if (argument === '--manifest') {
      if (manifestPath) fail('--manifest may be provided only once.')
      manifestPath = value
    } else {
      if (artifactsDir) fail('--artifacts-dir may be provided only once.')
      artifactsDir = value
    }
    index += 1
  }

  if (!manifestPath || !artifactsDir) {
    fail('Both --manifest and --artifacts-dir are required. Use --help for usage.')
  }
  return { help: false as const, manifestPath, artifactsDir }
}

function gitOutput(repoRoot: string, args: string[]) {
  return execFileSync('git', args, {
    cwd: repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim()
}

async function main() {
  const args = parseArguments(process.argv.slice(2))
  if (args.help) {
    console.log('Usage: npm run backup:manifest:verify -- --manifest <private-manifest.json> --artifacts-dir <private-dump-directory>')
    return
  }

  let repoRoot: string
  let currentCommit: string
  try {
    repoRoot = gitOutput(process.cwd(), ['rev-parse', '--show-toplevel'])
    currentCommit = gitOutput(repoRoot, ['rev-parse', 'HEAD'])
    const status = gitOutput(repoRoot, ['status', '--porcelain', '--untracked-files=all'])
    if (status) fail('Git working tree must be clean before verifying a backup manifest.')
  } catch (error) {
    if (error instanceof Error && error.message.includes('Git working tree')) throw error
    fail('Run the verifier from a clean Git checkout with Git available.')
  }

  const result = await verifyBackupManifest({
    manifestPath: resolve(args.manifestPath),
    artifactsDir: resolve(args.artifactsDir),
    migrationsDir: join(repoRoot, 'supabase', 'migrations'),
    repoRoot,
    expectedCommit: currentCommit,
  })

  if (!result.ok) {
    console.error('Backup manifest verification failed: ' + result.errors.join(' '))
    process.exitCode = 1
    return
  }

  console.log(
    'Backup artifact manifest verified: ' +
    result.artifactsVerified + ' files; ' +
    result.sourceMigrationCount + ' source migrations; ' +
    result.repositoryMigrationCount + ' repository migrations.',
  )
  console.log('This verifies recorded metadata and artifact integrity only. It does not prove backup completeness or a successful restore.')
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : 'Backup manifest verification failed.')
    process.exitCode = 1
  })
}
