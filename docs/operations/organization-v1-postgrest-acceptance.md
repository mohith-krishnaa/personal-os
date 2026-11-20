# Organization V1 — isolated PostgREST acceptance

This harness exercises the Organization V1 API contract through the real Supabase Auth and PostgREST endpoints. It is deliberately separate from migration replay: it never applies migrations, executes SQL, uses a service-role key, or modifies production.

## Hard prerequisites

Do not run this harness against production or against an unverified copy.

1. The owner must create a complete backup containing schema, data, and roles.
2. The owner must restore that backup into a separate isolated Supabase project.
3. The owner must verify the restore and complete the checklist reconciliation conflict review against the restored copy.
4. Create two disposable, confirmed Auth users in the isolated project. Do not use production user accounts.
5. Obtain only that isolated project's anon/publishable API key. A service-role or secret key is rejected by the script.

The three isolated-target/restore confirmation environment variables are operator attestations, not cryptographic proof that a backup exists. The script cannot independently verify backup completeness or restore success. The owner remains responsible for those checks.

## Required backup and restore evidence

Complete the [owner-controlled backup and isolated-restore gate](organization-v1-preflight.md#backup-gate--owner-controlled-export-and-isolated-restore) before setting any of the backup/restore confirmation variables.

The owner must retain a private evidence package outside Git containing:
- roles, schema, data, and the separate supabase_migrations schema/data exports;
- the managed-schema restore supplement for auth.users.on_auth_user_created and any reviewed custom auth/storage changes;
- separate Auth data and Storage object bytes/checksums if the source inventory requires them; because supabase_vault is installed, record the owner's root-key preservation decision and keep any key outside the artifact package/manifest;
- a non-secret manifest with source/target project refs, PostgreSQL and CLI versions, exact eight source migration versions, installed extension versions, per-table row counts, artifact byte sizes, SHA-256 hashes, and restore command exit statuses;
- isolated-target verification showing the exact eight-version baseline, matching schema/data/roles/extensions, RLS and relationship contracts, the restored auth profile-bootstrap trigger, and a successful read-only checklist conflict report.

The current read-only snapshot (2026-11-20) has nine empty public application tables, zero auth.users, zero Storage buckets/objects, and zero Vault secrets, but it still has a custom auth.users profile-bootstrap trigger, an installed supabase_vault extension, and four installed non-plpgsql extensions. Recheck all counts and customizations immediately before export. The default Supabase CLI dump excludes auth/storage and extension-created schemas; a default schema dump alone is not complete.

After the restored base has been verified, the isolated target must show exactly the eight source migrations applied and the 14 branch-only migrations pending. Review the dry-run, apply those 14 migrations only to the isolated target, run the checklist conflict report, and then run the two-owner PostgREST harness. Do not apply migrations to production. The environment variables below are owner attestations, not evidence; set them only after the artifacts and restore checks above have actually been reviewed.

## Environment

Set these variables in the shell running the harness. Do not put credentials in source control, CI variables, command-line arguments, or the runbook.

| Variable | Purpose |
|---|---|
| **PERSONAL_OS_ACCEPTANCE_SUPABASE_URL** | Exact isolated Supabase project origin |
| **PERSONAL_OS_ACCEPTANCE_PROJECT_REF** | Project ref matching the URL host |
| **PERSONAL_OS_ACCEPTANCE_ANON_KEY** | Isolated project's anon/publishable key only |
| **PERSONAL_OS_ACCEPTANCE_OWNER_A_EMAIL** | First disposable confirmed Auth user |
| **PERSONAL_OS_ACCEPTANCE_OWNER_A_PASSWORD** | First user's password |
| **PERSONAL_OS_ACCEPTANCE_OWNER_B_EMAIL** | Second disposable confirmed Auth user |
| **PERSONAL_OS_ACCEPTANCE_OWNER_B_PASSWORD** | Second user's password |
| **PERSONAL_OS_ACCEPTANCE_TARGET_ISOLATED** | Must be YES |
| **PERSONAL_OS_ACCEPTANCE_BACKUP_RESTORE_VERIFIED** | Owner attestation; must be YES |
| **PERSONAL_OS_ACCEPTANCE_CONFIRM_TARGET** | Must equal I_HAVE_RESTORED_A_COMPLETE_BACKUP |

For a local Supabase stack, use only http://localhost:54321 or http://127.0.0.1:54321 with project ref local. Hosted targets must use https://<20-character-project-ref>.supabase.co. Custom domains are intentionally rejected.

The known production project ref gujzvkyytxsnervovvrt is permanently blocked in the harness. A conflicting NEXT_PUBLIC_SUPABASE_URL or SUPABASE_URL also causes refusal.

## Run

After setting the environment above:

~~~bash
npm run acceptance:organization:postgrest -- --execute
~~~

The --execute flag is mandatory. Without it, the script exits before creating clients or making network requests.

## What it tests

Using two separate authenticated sessions and only the public anon/publishable key, it creates uniquely marked disposable records and verifies:

- Each owner can create, read, update, and delete their own projects.
- Each owner can create, read, update, and delete tasks and subtasks.
- Each owner can create, read, update, and delete canonical checklist_items and legacy task_checklist_items.
- Cross-owner SELECT returns no rows.
- Cross-owner UPDATE and DELETE affect no rows.
- Owner spoofing, cross-owner project/task/parent links, and cross-owner checklist/task links are rejected.
- Deleting a parent task cascades only through its own child hierarchy and attached checklist rows; the other owner's task remains.
- The script deletes only the IDs it created, using the same authenticated owner sessions.

The harness does not create Auth users, delete Auth users, or inspect production. The live PostgREST acceptance run does not run automatically in CI; its unit tests cover the environment/URL/key safety gate without contacting Supabase. A successful unit-test run is not evidence that the live PostgREST acceptance suite has been executed.

## Cleanup and failure handling

Cleanup is attempted after success or a caught request failure and is limited to the exact project, task, and checklist IDs returned by this run's inserts. If a request fails, cleanup is still attempted for both owners. A cleanup failure is reported and must be reconciled manually in the isolated project using the run's uniquely prefixed records.

Never point the harness at production to "see whether the guard works." Production is blocked in code, and no production write is authorized by this runbook.


## CI verification order

The CI workflow runs `npm run test:acceptance:preflight` before PostgreSQL client installation and migration replay. The same safety-gate tests are also included in `npm run test`. Neither command contacts Supabase; the live two-owner PostgREST acceptance command remains a manual owner-controlled step after a verified isolated restore.

## Task create request idempotency

When exercising authenticated task or subtask creation, provide a stable UUID in `client_request_id` and a 64-character lowercase SHA-256 payload fingerprint in `client_request_hash`. Repeat the same owner/request key with the same payload and verify only one task and one `TASK_CREATED` event exist. Reuse the same key with a different payload through the application service and verify it is rejected without changing the original row. The same UUID must remain usable by a second owner because uniqueness is scoped by `user_id`. Verify attempts to update either request-identity column are rejected. This acceptance remains unexecuted until the complete backup and isolated-restore gates are satisfied.
