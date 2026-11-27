# Fresh source inventory — 2026-11-27

Inspected at 2026-11-27T09:13:42.759387Z (UTC) using the existing read-only restore-customization-inventory.sql against source project gujzvkyytxsnervovvrt. The query was statically screened as a single WITH/SELECT statement before execution. It reads catalog metadata, function source hashes, role names/settings, ACLs, and row counts; it does not read secret values.

## Database and migration ledgers

- Project status ACTIVE_HEALTHY; PostgreSQL 17.11.0.003; region ap-southeast-1.
- Project migration ledger: 8 versions — 20260829182309, 20260830085036, 20260830103327, 20260830114218, 20260830120132, 20260830123420, 20260830141616, 20260905162251.
- Repository migration inventory: 27 files; 19 branch-only. No migration was added or applied.
- Provider ledgers: auth.schema_migrations 85, realtime.schema_migrations 97, storage.migrations 81. The latest Auth version is 20261116120000; the previous recorded Auth count was 84. This is a provider-managed migration, not a project migration.

## Data and extensions

- All 9 public application tables returned zero rows.
- All 36 managed/ephemeral data-table counts required by the backup manifest returned zero rows.
- Installed non-plpgsql extensions: pg_stat_statements 1.11, pgcrypto 1.3, supabase_vault 0.3.1, uuid-ossp 1.1.
- No non-platform custom schemas, managed-schema RLS policies, foreign servers, pg_cron, pg_net, or wrappers were found.
- supabase_realtime has no table membership.

## Customizations and privilege state

- auth.users.on_auth_user_created remains present and calls public.handle_new_user(). The function is postgres-owned, not SECURITY DEFINER, with search_path=public.
- ensure_rls remains enabled, owned by postgres, and calls SECURITY DEFINER public.rls_auto_enable() with search_path=pg_catalog. Source MD5: 99be20677b456ea8d3be47bdd44fb369. Direct EXECUTE grantees remain postgres and service_role.
- public.claim_due_reminders(integer) remains postgres-owned SECURITY DEFINER with search_path=public. Source MD5: ac7098bd02d9fceb8713ea5cded0e0e4. Direct EXECUTE grantees remain postgres and service_role.
- postgres is not a SUPERUSER; supabase_admin is a SUPERUSER.
- Broad default ACLs remain in public, storage, graphql, and graphql_public. The isolated target must be reconciled against this exact source inventory. Do not blindly copy platform defaults or revoke all defaults.

## Backup and restore boundary

This inventory is a read-only snapshot, not a backup. The 36 zero managed-row counts make the documented CLI logical-backup route eligible under its current row-count gate at this timestamp, but roles/schema/data/project migration-history exports and a successful isolated restore remain mandatory. No owner-controlled backup artifacts were found in the Library; no isolated Supabase branches exist. The unrelated inactive yojantra project was not used. No export, restore, production DDL/DML, migration, RLS/role change, or project mutation occurred.

The inventory is time-bound. Re-run it immediately before owner export and capture a new private manifest; do not reuse this snapshot's counts without rechecking.

---

# Supabase-managed schema and project customization restore inventory

**Snapshot:** 2026-11-21 03:23 UTC  
**Source:** project `gujzvkyytxsnervovvrt`  
**Purpose:** define what the manual CLI logical backup does not preserve and what must be reconstructed or verified on a disposable isolated target.

This is an inventory and runbook, not proof of a backup or restore. No backup was created and no target project was created during this audit.

## 1. Hard boundary: the CLI dump is not a full Supabase project clone

The standard Supabase CLI `db dump` excludes Supabase-managed schemas such as `auth`, `storage`, and extension-created schemas. Storage object bytes are not part of a database dump. Supabase documents Auth/Storage schema customizations as a separate restore step. See the [CLI backup/restore guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) and [database backup guide](https://supabase.com/docs/guides/platform/backups).

For this repository's manual CLI path, the offline manifest verifier now requires **45 exact row counts**:
- 9 public application tables, whose counts are recorded but may be non-zero when the dump contains their data.
- 36 managed/ephemeral data tables listed below, all of which must be exactly zero.

If any managed count is non-zero, the verifier fails. Stop rather than treating the five standard dump artifacts as complete. Use a supported full backup/restore method or an owner-approved, independently tested managed-data export.

The Supabase “Restore to a new project” flow copies database schema/data/roles, Auth user data, and the encryption root key, but Storage objects/settings, Edge Functions, Auth settings/API keys, Realtime settings, extensions/database settings, and read replicas require manual reconfiguration. The flow is restricted to paid plans with physical backups enabled. The current organization is on the Free plan, so that native flow is not currently available without an explicit owner plan/cost decision. See [Restore to a new project](https://supabase.com/docs/guides/platform/clone-project).

## 2. Read-only inventory command

Run [`supabase/operations/restore-customization-inventory.sql`](../../supabase/operations/restore-customization-inventory.sql) in the source project's SQL editor only after verifying the project reference in the Dashboard. It is one SELECT statement and does not read secret values. Save the JSON result privately and calculate its SHA-256; do not commit the result.

The query inventories:
- Exact row counts for all 9 public application tables and 36 managed/ephemeral tables.
- Provider-managed migration ledger counts.
- Installed extensions and versions.
- Non-platform schemas.
- Public functions, non-internal triggers, event triggers, and managed-schema RLS policies.
- Default ACLs, login roles, role memberships, role settings, database settings.
- Publications and table membership.
- Foreign servers and presence of `pg_cron`, `pg_net`, and `wrappers`.

It deliberately excludes function bodies and secret values. Project-level Auth, API, Edge Function secret, Storage API, and Dashboard settings still require an owner inventory.

## 3. Exact managed-data row-count contract

The current source snapshot returned zero for every table below. The verifier requires these keys in `source.rowCounts` and rejects any non-zero value:

**Auth**
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

**Storage**
- `storage.buckets`
- `storage.objects`
- `storage.s3_multipart_uploads`
- `storage.s3_multipart_uploads_parts`
- `storage.buckets_analytics`
- `storage.buckets_vectors`
- `storage.vector_indexes`

**Vault and Realtime**
- `vault.secrets`
- `realtime.messages`
- `realtime.subscription`

Provider-managed migration ledgers are recorded separately and must not be copied as application data:
- `auth.schema_migrations`: 84 rows
- `storage.migrations`: 81 rows
- `realtime.schema_migrations`: 97 rows
- `supabase_migrations.schema_migrations`: 8 project migration versions

The exact Realtime ledger count is 97. A previous table-list result reported 8; that was not an exact `count(*)` result and is superseded by the read-only inventory query.

## 4. Current source customization findings

### Project-installed and migration-owned database objects

| Object | Current source contract | Restore treatment |
|---|---|---|
| `auth.users.on_auth_user_created` | AFTER INSERT; calls `public.handle_new_user()` | Auth schema is excluded from standard dump. Recreate with the dedicated script below after the public function and Auth table exist. |
| `public.handle_new_user()` | Owner `postgres`; SECURITY INVOKER; `search_path=public` | Lives in public schema and should be in `schema.sql`. Do not recreate a second function. |
| `ensure_rls` event trigger | Enabled `ddl_command_end` trigger owned by `postgres`; calls postgres-owned SECURITY DEFINER `public.rls_auto_enable()` with `search_path=pg_catalog`. Current function ACL contains only `postgres` and `service_role`. | Project-installed optional customization, not a Supabase-managed built-in and not created by this repository's migrations. The only migration reference is the privilege revoke in `20260905162251_restrict_rls_auto_enable_execute.sql`. Restore with `supabase/operations/restore-ensure-rls-event-trigger.sql` on the isolated target while authenticated directly as `postgres`; do not require `rolsuper` or switch to `supabase_admin`. |
| `public.claim_due_reminders(integer)` | Owner `postgres`; SECURITY DEFINER; `search_path=public`; EXECUTE granted to `service_role` only | Matches the applied baseline migration `20260830123420_atomize_reminder_delivery_claim.sql`; this is expected source state, not out-of-ledger drift. Branch-only `20261120000300_atomic_reminder_delivery.sql` is the intended atomic replacement and changes `search_path` to `pg_catalog, public`. Apply and verify it only on the isolated target after the complete restore gate. |

The first repository migration, `20260829182309_create_personal_os_core.sql`, creates both `public.handle_new_user()` and the Auth trigger. Because the trigger belongs to the excluded `auth` schema, restoring the migration ledger as already applied does not recreate it.

The `ensure_rls`/ `rls_auto_enable()` pair is different: Supabase documents this as an optional event-trigger pattern, not an automatically installed platform object ([official guide](https://supabase.com/docs/guides/database/postgres/event-triggers)). The repository contains no migration that creates it. The applied migration `20260905162251_restrict_rls_auto_enable_execute.sql` only revokes EXECUTE from `anon` and `authenticated`; it does not revoke PUBLIC. The live ACL currently has no PUBLIC grant and grants EXECUTE only to `postgres` and `service_role`, so that exact ACL must be verified after restore.

The source inventory also confirms that the `postgres` role is **not** a PostgreSQL superuser (`pg_roles.rolsuper=false`), while the current session is authenticated and running as `postgres`. Supabase's Supautils extension nevertheless permits the `postgres` role to create and manage event triggers; the official guide explicitly documents this privilege ([Supabase Event Triggers](https://supabase.com/docs/guides/database/postgres/event-triggers)). The restore script therefore requires both `session_user` and `current_user` to equal `postgres`, not `rolsuper=true`. It creates the event trigger as `postgres`, so no ownership-transfer statement is needed. A separate local superuser role is tested as a negative control and must be rejected.

Use the following only after the isolated target is fully restored and its project reference is verified in the Dashboard:

1. Connect directly as the target's `postgres` database role (do not use `SET ROLE supabase_admin`).
2. In that same session, set `app.personal_os_restore_target='isolated'`.
3. Run `supabase/operations/restore-ensure-rls-event-trigger.sql` twice. It refuses a missing/mismatched function body, owner, SECURITY DEFINER/search-path contract, unexpected direct EXECUTE grantees, grant options, or a conflicting existing event trigger. It removes PUBLIC/anon/authenticated EXECUTE and grants service_role, then creates `ensure_rls` only if it is absent.
4. Run `supabase/tests/restore-ensure-rls-event-trigger.sql` to verify the exact ACL/event-trigger contract, public-table RLS enablement, non-public-schema skip, and exception behavior.

The local CI PostgreSQL container runs as a superuser named `postgres`; it verifies the identity gate, rejects the separate `supabase_admin` SUPERUSER control, and exercises the SQL contract. It does **not** emulate Supautils' hosted privilege hook. The actual event-trigger creation capability must still be verified on the restored Supabase target before this restore step is accepted.

The live `rls_auto_enable()` body catches errors from `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` and writes `RAISE LOG` without re-raising. Supabase's current example re-raises the exception. The source behavior can therefore allow table creation to continue after an RLS-enable failure; inspect logs and require an owner decision before changing or codifying this behavior. The event trigger enables RLS only for future public-table creation commands and does not create policies or retroactively repair existing tables.

Apply [`supabase/operations/restore-auth-user-trigger.sql`](../../supabase/operations/restore-auth-user-trigger.sql) **only on the isolated target**, after `schema.sql` has restored `public.handle_new_user()` and the Supabase target provides `auth.users`. First verify the target project reference in the Dashboard, then set `app.personal_os_restore_target='isolated'` in the same SQL session. The script refuses to run without that explicit session attestation, verifies the function owner/security/search-path contract, then drops and recreates only `on_auth_user_created`. It does not create the function or touch production.

Afterward run [`supabase/tests/restore-auth-user-trigger.sql`](../../supabase/tests/restore-auth-user-trigger.sql). The migration CI runner also executes the restore script twice on disposable PostgreSQL to verify idempotence.

### Platform-managed objects and settings

The snapshot found:
- Four non-plpgsql extensions: `pg_stat_statements 1.11`, `pgcrypto 1.3`, `supabase_vault 0.3.1`, `uuid-ossp 1.1`.
- No non-platform custom schemas.
- No RLS policies in `auth`, `storage`, or `realtime`.
- Publication `supabase_realtime` exists with no table membership.
- No `pg_cron`, `pg_net`, or `wrappers` extension and no foreign servers.
- No custom LOGIN roles; the nine login roles reported are platform roles.
- No Edge Functions are listed.
- `storage.buckets`, `storage.objects`, `vault.secrets`, all inventoried Auth data tables, and Realtime messages/subscriptions are empty.

The `supabase_vault` extension is installed but `vault.secrets` is empty. The encryption root key was not retrieved. If any Vault secrets or encrypted columns exist at backup time, the owner must preserve the root key through the documented Supabase procedure; never place it in the repository, manifest, CI, or chat. Recheck before export.

The source has role/database settings and default ACLs that matter:
- Role settings include `statement_timeout=3s` for `anon`, `8s` for `authenticated` and `authenticator`, and explicit search paths for platform roles.
- Database settings include `row_security=on`, `statement_timeout=120000`, and a user-set search path.
- `pg_default_acl` includes broad default grants in `public`, `storage`, `graphql`, and `graphql_public` for source owners/platform roles.

The restore runbook prepares target default privileges before schema restore to prevent target defaults from broadening access. After schema restore, compare the target's `pg_default_acl`, role memberships, role settings, and database settings to the saved source inventory. Do not leave the target with all defaults revoked if the source dump restores explicit default ACLs.

## 5. Schema drift review when generating a CLI diff

The repository intentionally has no `supabase/config.toml`. Do not run `supabase init` in the repository or add a config file as part of this audit. To generate a source-baseline diff, create a private temporary workspace outside Git and copy **only the exact eight live project migration files**, not all 27 branch migrations:

```bash
set -euo pipefail
REPO_ROOT="$PWD"
DIFF_WORKDIR="$(mktemp -d)"
mkdir -p "$DIFF_WORKDIR"
(cd "$DIFF_WORKDIR" && supabase init)
mkdir -p "$DIFF_WORKDIR/supabase/migrations"

for version in \
  20260829182309 \
  20260830085036 \
  20260830103327 \
  20260830114218 \
  20260830120132 \
  20260830123420 \
  20260830141616 \
  20260905162251; do
  file="$(find "$REPO_ROOT/supabase/migrations" -maxdepth 1 -type f -name "${version}_*.sql" -print -quit)"
  test -n "$file"
  cp "$file" "$DIFF_WORKDIR/supabase/migrations/"
done

(cd "$DIFF_WORKDIR" && supabase db diff --remote="$SOURCE_DB_URL" --use-pg-delta > "$BACKUP_DIR/source-schema-diff.sql")
```

This uses the exact eight-version source baseline and avoids mixing in the 19 branch-only migrations. It requires Docker for the CLI shadow database. Review the diff manually; it is drift evidence, not a backup artifact and not an apply script. Do not apply the output wholesale. The Auth trigger is already present in the first source migration, so the diff may not emit it even though the default dump excludes the Auth schema. Separately inspect the dump for the project-installed `rls_auto_enable()` function and `ensure_rls` event trigger; verify both on the isolated target rather than assuming a database-level event trigger was captured.

## 6. Project-level settings checklist

The database inventory cannot recover or attest these Dashboard/API settings. The owner must record their presence and a secure external reference, never secret values:

- Auth Site URL, redirect allowlist, enabled providers, OAuth/SAML configuration, SMTP/SMS settings, MFA, CAPTCHA, hooks, rate limits, JWT signing/key rotation, and any custom domains.
- New project's publishable/secret API keys and the deployments that must receive the new values.
- Edge Function source, `deno.json`/import maps, verify-JWT settings, and secret names. No Edge Functions were listed in this snapshot; secret names/values were not accessible through the connected tools.
- Storage bucket configuration and object bytes. Current bucket/object counts are zero; if non-zero, export object bytes through the Storage API and verify size/checksum separately.
- Realtime project settings and publication table membership. Current `supabase_realtime` membership is empty.
- Database webhooks, cron jobs, read replicas, network restrictions, SSL enforcement, compute/database settings, log drains, and backup/PITR configuration.
- Vault root key dependency. Current secret count is zero, but the owner must confirm there are no encrypted columns or other Vault-dependent values.

## 7. Optional fail-closed `ensure_rls` candidate — owner decision required

The source project's `public.rls_auto_enable()` currently logs and swallows errors from `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`. The existing event-trigger behavior test proves that a forced enable failure can allow `CREATE TABLE` to complete with RLS disabled. This is a real fail-open edge case, not merely a documentation concern.

A separately reviewed candidate is provided at [`supabase/operations/apply-ensure-rls-fail-closed.sql`](../../supabase/operations/apply-ensure-rls-fail-closed.sql). It preserves the function owner, SECURITY DEFINER setting, fixed `search_path=pg_catalog`, event-trigger definition, and exact postgres/service_role EXECUTE ACL. Its only behavioral change is to log an RLS-enable error and then re-raise it, causing the originating table-creation statement to roll back rather than leave a public table without RLS.

**This candidate is not a migration, is not automatically applied, and is not approved for production.** It is prepared for review and testing on a fully restored isolated target only. It refuses to run unless the same session has both:

```sql
SET app.personal_os_restore_target = 'isolated';
SET app.personal_os_fail_closed_rls_approval = 'owner-approved';
```

The second setting is an operator attestation, not cryptographic proof of approval. Set it only after the owner has reviewed the operational consequence: if RLS cannot be enabled, the CREATE TABLE/CREATE TABLE AS/SELECT INTO statement now fails. The script also requires a direct `session_user=current_user='postgres'`, the exact reviewed source or candidate function fingerprint, the expected owner/security/search-path contract, the postgres/service_role-only ACL, and the existing enabled postgres-owned `ensure_rls` trigger. It is idempotent for the exact source/candidate fingerprints and refuses unknown definitions or ACL drift.

The candidate's reviewed `pg_proc.prosrc` fingerprint is `b95d4b52e100f89abf4b5afa270a4776`; the original source fingerprint is `99be20677b456ea8d3be47bdd44fb369`.

The disposable CI test [`supabase/tests/ensure-rls-fail-closed-candidate.sql`](../../supabase/tests/ensure-rls-fail-closed-candidate.sql) checks successful public-table RLS enablement, injects an error in a test-only replacement body that uses the same re-raise semantics, proves the CREATE TABLE statement leaves no table behind, and rolls back to restore the candidate body. The migration runner also verifies missing-target, missing-approval, and wrong-role rejection and applies the candidate twice. This validates SQL behavior on local PostgreSQL; it does **not** emulate Supautils' hosted event-trigger privilege hook or constitute an owner decision.

Do not run this candidate against production. Do not add it to the migration chain unless a separate owner-approved production change is explicitly authorized after a complete owner-controlled backup and successful isolated restoration.

## 8. Acceptance order

1. Re-run the SQL inventory immediately before export; save and hash the private JSON output.
2. Export roles, schema, data, and the project migration history with the corrected CLI target selector. Verify each command's target and exit status.
3. Build the manifest with all 45 row-count keys. Run the offline verifier; it must pass with all 36 managed data counts equal to zero.
4. Create a separate isolated Supabase target. Do not use production as the target.
5. Restore roles, prepare target defaults, restore schema/data and project migration history, enable compatible extensions, and compare roles/default ACLs/settings.
6. Apply the Auth trigger restore script on the isolated target. Then connect directly as the target's `postgres` role, set the same-session isolated marker, run `restore-ensure-rls-event-trigger.sql` twice, and execute its behavior test. Verify the `claim_due_reminders` baseline-to-branch migration transition separately.
7. If and only if the owner has explicitly approved the fail-closed behavior, set `app.personal_os_fail_closed_rls_approval='owner-approved'` in that same isolated postgres session, run `apply-ensure-rls-fail-closed.sql` twice, and execute `ensure-rls-fail-closed-candidate.sql`. Do not rerun the original `restore-ensure-rls-event-trigger.sql` after this candidate has replaced the function body. If the owner has not approved the behavior, leave the original function unchanged and record the open fail-open risk.
8. Review the checklist conflict report against the restored copy and record owner-approved dispositions.
9. Run authenticated two-owner PostgREST acceptance against the isolated target.
10. Only after all evidence is complete may a separate owner review consider production rollout. This runbook does not authorize production DDL, DML, migration, RLS changes, project changes, or PR merge.

---

## Evidence and limitations

The inventory was executed with read-only SQL on the source project. It did not create a backup, restore a target, retrieve secrets, inspect Auth provider configuration, or change project settings. The current production migration ledger remains at eight project migrations; the repository contains 27. The production database remains read-only for this automation.


## Latest read-only revalidation — 2026-11-21

Database-reported inspection time: `2026-11-21T14:16:37.284033Z`. The full inventory query was re-executed against the source project; no DDL or DML was issued.

Reconfirmed:
- Project `ACTIVE_HEALTHY`, PostgreSQL `17.11.0.003`, region `ap-southeast-1`.
- Project migration ledger: 8 versions; repository migration inventory: 27 (19 branch-only).
- All 9 public application tables: 0 rows. All 36 managed/ephemeral data tables required by the manifest: 0 rows.
- Extensions: `pg_stat_statements 1.11`, `pgcrypto 1.3`, `supabase_vault 0.3.1`, `uuid-ossp 1.1`.
- Provider migration ledgers: Auth 84 rows, Realtime 97 rows, Storage 81 rows; project ledger 8 rows.
- No non-platform custom schemas, foreign servers, `pg_cron`, `pg_net`, `wrappers`, or managed-schema RLS policies; `supabase_realtime` has no table membership.
- The custom Auth trigger, `ensure_rls` event trigger, and baseline `claim_due_reminders(integer)` function remain present with the contracts described above.
- Default ACL entries remain present across `public`, `storage`, `graphql`, and `graphql_public`; the isolated restore must compare and reconcile them against the captured source inventory.

This is a read-only inventory refresh, **not a backup** and not evidence of a successful isolated restore. The standard CLI logical-backup path passes the current managed-row-count gate, but owner-controlled exports and restore verification remain mandatory.
