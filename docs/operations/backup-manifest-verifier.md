# Latest managed-schema safety gate — 2026-11-21

The manifest contract now requires **45 exact row-count keys**: nine public application tables plus 36 Supabase-managed/ephemeral data tables. All 36 managed counts must be exactly zero for the standard Supabase CLI logical-backup path. The verifier rejects any non-zero count because the standard CLI dump excludes managed schemas such as `auth`, `storage`, and extension-created schemas; Storage object bytes are also outside a database dump. This is a hard gate, not a warning.

If any of the 36 counts becomes non-zero, stop. Do not call the five CLI dump files a complete backup. Use a supported full backup/restore method or obtain an owner-reviewed, independently tested export path that preserves the affected managed data and settings. The current organization is on the Free plan; Supabase's “Restore to a new project” flow is paid-plan-only and requires physical backups, so it is not currently available without an owner plan decision.

The read-only inventory query is [`supabase/operations/restore-customization-inventory.sql`](../../supabase/operations/restore-customization-inventory.sql). It records exact managed-table counts, extension versions, roles/memberships, default ACLs, role/database settings, custom functions/triggers/event triggers, policies, publications, and foreign servers without reading secret values. Re-run it immediately before export and save the result privately.

The custom `auth.users.on_auth_user_created` trigger is not in the default dump because it belongs to the excluded Auth schema. Its function `public.handle_new_user()` is in the public schema dump. Recreate the trigger on the isolated target with [`restore-auth-user-trigger.sql`](../../supabase/operations/restore-auth-user-trigger.sql), then run its regression assertion. Never run that DDL script on production.

Passing this offline verifier still does not prove that project-level Auth settings, API keys, Storage, Vault key material, Realtime configuration, Edge Function secrets, or database settings were restored. See [the managed-schema and project-customization restore inventory](restore-customization-inventory.md).

---

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
- rejects credential-like manifest fields/values, symlinks (including symlinked migration SQL entries), unsafe artifact paths, and manifest/artifact locations inside the Git repository;
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
| \`rowCounts\` | All 45 required table keys with non-negative integer counts captured immediately before export |

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

Required row-count keys (45 total; the 36 managed/ephemeral keys must be zero):
- `public.activity_events`
- `public.goals`
- `public.notes`
- `public.notifications`
- `public.profiles`
- `public.progress_entries`
- `public.projects`
- `public.reminders`
- `public.tasks`
- `auth.users`
- `auth.instances`
- `auth.identities`
- `auth.refresh_tokens`
- `auth.sessions`
- `auth.audit_log_entries`
- `auth.mfa_factors`
- `auth.mfa_challenges`
- `auth.mfa_amr_claims`
- `auth.sso_providers`
- `auth.sso_domains`
- `auth.saml_providers`
- `auth.saml_relay_states`
- `auth.flow_state`
- `auth.one_time_tokens`
- `auth.oauth_clients`
- `auth.oauth_authorizations`
- `auth.oauth_consents`
- `auth.oauth_client_states`
- `auth.custom_oauth_providers`
- `auth.webauthn_credentials`
- `auth.webauthn_challenges`
- `auth.scim_users`
- `auth.scim_tokens`
- `auth.mfa_recovery_code_sets`
- `auth.mfa_recovery_codes`
- `storage.buckets`
- `storage.objects`
- `storage.s3_multipart_uploads`
- `storage.s3_multipart_uploads_parts`
- `storage.buckets_analytics`
- `storage.buckets_vectors`
- `storage.vector_indexes`
- `vault.secrets`
- `realtime.messages`
- `realtime.subscription`
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

The 25 tests cover valid inventories, missing files, byte-size and SHA-256 mismatches, failed command statuses, target mismatch/attestation, source and repository migration drift, malformed and symlinked migration filenames, unsafe paths, symlinks, repository-local artifact/manifest paths, credential material, incomplete row counts/extensions, commit mismatch, unsupported restore claims, and duplicate artifact paths.

The tests run as part of \`npm test\`; the CLI is exposed as \`npm run backup:manifest:verify\`.
