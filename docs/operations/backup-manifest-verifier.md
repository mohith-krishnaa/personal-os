# Offline backup manifest verifier

This verifier checks the integrity and declared inventory of owner-created backup artifacts. It is offline and read-only. It does not create a backup, connect to Supabase, inspect database contents, or prove that a restore succeeded.

## Run

Run from the exact clean Git checkout recorded in the manifest. Keep both the manifest and SQL dumps in a private directory outside the repository:

~~~bash
npm run backup:manifest:verify -- \
  --manifest "$BACKUP_DIR/manifest.json" \
  --artifacts-dir "$BACKUP_DIR"
~~~

The verifier:
- requires a clean Git working tree and matches \`source.repositoryCommit\` to the current HEAD;
- reads numbered migration filenames in \`supabase/migrations\` and compares them with the manifest;
- requires the exact eight source migration versions recorded in the current live baseline;
- validates the required source project, extension names, row-count keys, five export command records, and five artifact records;
- rejects credential-like manifest fields/values, symlinks, unsafe artifact paths, and manifest/artifact locations inside the Git repository;
- checks each artifact's actual byte size and SHA-256 digest.

It does not read environment variables, invoke GitHub, invoke the Supabase CLI, call a database, or parse SQL dump contents. The SQL files may contain sensitive data and must remain private. Do not commit the manifest or dump files.

## Manifest contract

The top-level JSON object accepts exactly: \`formatVersion\`, \`source\`, \`commands\`, and \`artifacts\`. Unknown fields are rejected so credential-bearing metadata cannot be added accidentally.

### Source metadata

\`formatVersion\` must be integer \`1\`. \`source\` accepts exactly:

| Field | Requirement |
|---|---|
| \`projectRef\` | \`gujzvkyytxsnervovvrt\` |
| \`region\` | Non-empty string captured at export time |
| \`postgresVersion\` | Non-empty PostgreSQL version captured at export time |
| \`supabaseCliVersion\` | Non-empty CLI version |
| \`postgresClientVersion\` | Non-empty \`psql --version\` output |
| \`exportedAtUtc\` | Canonical UTC ISO timestamp with milliseconds |
| \`repositoryCommit\` | 40-character lowercase SHA equal to the clean checkout's current HEAD |
| \`appliedMigrationVersions\` | Exact ascending eight-version source ledger below |
| \`repositoryMigrationVersions\` | Exact ascending version prefixes of every numbered \`.sql\` file in this checkout |
| \`extensions\` | Exactly the four required non-plpgsql extension names, each with a non-empty captured version |
| \`rowCounts\` | All 13 required table keys with non-negative integer counts captured immediately before export |

The current source migration baseline is:

~~~text
20260829182309
20260830085036
20260830103327
20260830114218
20260830120132
20260830123420
20260830141616
20260905162251
~~~

The current repository has 27 numbered migrations. The verifier does not hardcode those 27 values; it reads the exact filenames from the checkout and requires the manifest to match them. Create the manifest from the same commit that will be used for verification.

Required extension names:
- \`pg_stat_statements\`
- \`pgcrypto\`
- \`supabase_vault\`
- \`uuid-ossp\`

Required row-count keys:
- \`public.activity_events\`
- \`public.goals\`
- \`public.notes\`
- \`public.notifications\`
- \`public.profiles\`
- \`public.progress_entries\`
- \`public.projects\`
- \`public.reminders\`
- \`public.tasks\`
- \`auth.users\`
- \`storage.buckets\`
- \`storage.objects\`
- \`vault.secrets\`

Record actual counts; do not copy the earlier zero-row snapshot without rechecking. If the live source migration ledger or required extension inventory changes after an explicitly approved rollout, update the verifier's expected baseline and tests in a separate reviewed code change before accepting a new manifest.

### Export command records

The \`commands\` array must contain exactly one record for each ID:

| ID | Export |
|---|---|
| \`roles\` | \`roles.sql\` |
| \`schema\` | \`schema.sql\` |
| \`data\` | \`data.sql\` |
| \`migration-history-schema\` | \`migration-history-schema.sql\` |
| \`migration-history-data\` | \`migration-history-data.sql\` |

Each record contains exactly:
- \`id\`: one of the IDs above;
- \`targetProjectRef\`: the source project ref;
- \`targetLineVerified\`: boolean \`true\` only after the CLI's printed \`Target:\` line was compared with Dashboard Connect details;
- \`exitCode\`: integer \`0\`.

Do not store raw command lines, stdout/stderr, connection URLs, or credentials. \`targetLineVerified\` is an owner attestation: the verifier checks the recorded value and matching project ref, but cannot independently authenticate CLI output or prove which server produced a dump.

### Artifact records

The \`artifacts\` array must contain exactly one record for each path:
- \`roles.sql\`
- \`schema.sql\`
- \`data.sql\`
- \`migration-history-schema.sql\`
- \`migration-history-data.sql\`

Each record contains exactly:
- \`path\`: one of the five relative filenames above;
- \`commandId\`: the matching command ID;
- \`sizeBytes\`: positive integer byte size;
- \`sha256\`: 64-character lowercase SHA-256 digest.

The verifier rejects missing files, non-regular files, symbolic links, size mismatches, digest mismatches, path traversal, duplicate records, and extra artifact paths.

## What a successful result means

A successful result means only that the manifest matches the current source/repository inventory contract, all five required export commands are recorded as successful and targeted to the declared source ref, and all five required files exist outside the repository with matching sizes and SHA-256 digests.

It does **not** prove:
- that the operator actually inspected the CLI \`Target:\` output;
- that the dump includes every required Supabase-managed schema, Auth/Storage object, Vault root-key dependency, project setting, or custom trigger supplement;
- that row counts or extension versions were measured accurately;
- that SQL dumps are semantically complete or restorable;
- that roles, schema, data, extensions, Auth trigger, RLS, policies, grants, or default ACLs restore correctly;
- that the isolated restore succeeded.

There is intentionally no \`restoreStatus\` field in the accepted manifest. Restore verification remains a separate owner-controlled gate in [Organization V1 preflight](organization-v1-preflight.md#restore-verification--mandatory-evidence). Never treat this verifier's success as permission to apply migrations to production.

## Regression coverage

The tests cover valid inventories, missing files, byte-size and SHA-256 mismatches, failed command statuses, target mismatch/attestation, source and repository migration drift, malformed migration filenames, unsafe paths, symlinks, repository-local artifact/manifest paths, credential material, incomplete row counts/extensions, commit mismatch, unsupported restore claims, and duplicate artifact paths.

The tests run as part of \`npm test\`; the CLI is exposed as \`npm run backup:manifest:verify\`.
