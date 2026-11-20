# Organization V1 — isolated PostgREST acceptance

This harness exercises the Organization V1 API contract through the real Supabase Auth and PostgREST endpoints. It is deliberately separate from migration replay: it never applies migrations, executes SQL, uses a service-role key, or modifies production.

## Hard prerequisites

Do not run this harness against production or against an unverified copy.

1. The owner must create a complete backup containing schema, data, and roles.
2. The owner must restore that backup into a separate isolated Supabase project.
3. The owner must verify the restore and complete the checklist reconciliation conflict review against the restored copy.
4. Create two disposable, confirmed Auth users in the isolated project. Do not use production user accounts.
5. Obtain only that isolated project's anon/publishable API key. A service-role or secret key is rejected by the script.

The two restore confirmation environment variables are operator attestations, not cryptographic proof that a backup exists. The script cannot independently verify backup completeness or restore success. The owner remains responsible for those checks.

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

The known production project ref gujzvkyytxsnervovvrt is permanently blocked in the harness. A conflicting NEXT_PUBLIC_SUPABASE_URL also causes refusal.

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

The harness does not create Auth users, delete Auth users, inspect production, or run automatically in CI. Its unit tests cover the environment/URL/key safety gate without contacting Supabase. A successful unit-test run is not evidence that the live PostgREST acceptance suite has been executed.

## Cleanup and failure handling

Cleanup runs in finally and is limited to the exact project, task, and checklist IDs returned by this run's inserts. If a request fails, cleanup is still attempted for both owners. A cleanup failure is reported and must be reconciled manually in the isolated project using the run's uniquely prefixed records.

Never point the harness at production to "see whether the guard works." Production is blocked in code, and no production write is authorized by this runbook.
