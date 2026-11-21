# Latest preflight update — trusted activity-event writers (migration 27, 2026-11-21)

The branch contains **27 migrations**; the last read-only production ledger contains **8**, leaving **19 branch-only**. Migration 27 is `20261121000500_trusted_activity_event_writers.sql`. CI #444 passed the implementation/test commit `d05d5a47efd51dca6088ea211f897573b789374d`: 27/27 PostgreSQL migrations, migration 27 reapplication, 17/17 PostgREST safety tests, 147/147 application tests, typecheck, production build and npm audit (0 vulnerabilities). The fail-closed follow-up `fbb3be06e3c21156ce8e4f3d72c408d657af7d45` passed [CI #445](https://github.com/mohith-krishnaa/personal-os/actions/runs/44828178553): 27 migration replay/reapplication, 17/17 preflight tests, 147/147 application tests, typecheck, production build, and npm audit 0 vulnerabilities.

CI #448 also passed on final checkpoint HEAD `c179e331f75ba3a490043eb0b90c047a89ca0a3b`: 17/17 preflight tests, 27 migrations plus migration 27 reapplication, 147/147 app tests, typecheck, production build, and npm audit 0 vulnerabilities.

## Read-only query contracts

- Query 16: task activity trigger enabled, postgres-owned SECURITY DEFINER, fixed search path; authenticated direct trigger EXECUTE and direct activity-event INSERT are false; service_role trigger EXECUTE remains true; owner SELECT policy present; authenticated INSERT policy absent.
- Query 18: the same SECURITY DEFINER owner/search-path contract plus TASK_DELETED mapping and existing cascade FKs.
- Query 19: authenticated activity_events SELECT true and INSERT/UPDATE/DELETE/TRUNCATE false; service_role SELECT/INSERT true and UPDATE/DELETE/TRUNCATE false; anon has no privileges; the authenticated INSERT policy is absent; postgres retains owner maintenance privileges.
- Query 20: reports event_type/entity metadata nullability, CHECK/FK absence, current task/reminder event mappings, task-create request uniqueness, recurring-occurrence uniqueness, reminder-notification uniqueness, and absence of a generic event idempotency key.

## Fresh production read-only result

Query 20 executed successfully against production on 2026-11-21. It reported event_type TEXT NOT NULL; entity_type TEXT nullable; entity_id UUID nullable; metadata JSONB NOT NULL; no event-type CHECK, entity-pair CHECK, entity_id FK, or generic event idempotency key; task activity trigger absent; reminder event mapping present; task-create request uniqueness absent; recurring-occurrence and reminder-notification uniqueness present. The live ledger remains at 8; the 27-migration branch is not deployed. Existing production activity_events still has its legacy FOR ALL policy and broad grants. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred.

The complete owner-controlled schema/data/roles backup, successful isolated restoration, restored-copy checklist conflict review, and authenticated two-owner PostgREST acceptance remain mandatory. Do not run the PostgREST acceptance harness against production.

## Checklist reconciliation conflict disposition — 2026-11-21

`supabase/operations/checklist-reconciliation-conflicts.sql` is a read-only diagnostic. It contains SELECT only and never copies, updates, deletes, reassigns, or merges rows. Run it only on the verified isolated target after both checklist tables exist and the branch-only migrations have been applied there. Do not run it against production while the checklist tables and migrations are absent.

The report's classification priority is:

- **`missing_task`** — the legacy row references no task. A validated task foreign key should normally prevent this; treat it as referential-integrity or constraint drift. Preserve the source and stop for investigation.
- **`task_owner_mismatch`** — the task exists but `tasks.user_id` differs from `task_checklist_items.user_id`. This is a cross-owner association. Do not copy the row or transfer ownership based on the report alone. Verify the source backup and authoritative task ownership; unresolved ownership blocks acceptance.
- **`missing_canonical`** — the task exists and has the same owner as the legacy row, but no canonical row has that ID. This can be a write made after the one-time reconciliation or a row omitted from that copy. Compare the backup snapshot, migration time, legacy-client logs, and owner evidence. Timestamps are clues, not proof of when a row was written.
- **`canonical_id_collision`** — a canonical row with the same ID exists, but one or more owner, task, or payload values differ. This category includes both cross-owner/task collisions and payload-only collisions. Use `owner_mismatch`, `task_mismatch`, `payload_mismatch`, the per-field mismatch flags, and the side-by-side legacy/canonical values for title, completion, position, `created_at`, and `updated_at`.

### Required evidence and disposition register

Keep the report output and disposition register private; they contain user IDs, task IDs, and checklist text. For each run, retain:

1. Source and isolated-target project refs, PostgreSQL version, branch/commit SHA, exact migration ledger, UTC report time, and the backup-manifest SHA-256.
2. The complete report output and its SHA-256; do not paste row data into GitHub issues or commit it to the repository.
3. For each conflict ID, the report's legacy/canonical values and flags, the referenced task owner, the relevant backup snapshot, and any corroborating legacy-client or application logs.
4. A per-row decision with rationale, evidence reference, owner/reviewer approval, date, target environment, and before/after row counts. Record unresolved rows explicitly; never omit them from the register.

### Safe disposition rules

- **`task_owner_mismatch`:** preserve both records. Do not change `user_id` to make the row pass. Only consider a corrected task association after the intended owner/task is independently proven and the owner approves the exact repair on the isolated copy.
- **`canonical_id_collision`:** `ON CONFLICT (id) DO NOTHING` intentionally preserves the canonical row and leaves the legacy source intact. First decide whether the rows represent the same logical item or two distinct items. If they are distinct, a separately reviewed copy with a new canonical UUID may be appropriate; if they are the same, define an owner-approved field precedence before any merge. Never overwrite the canonical row or delete the legacy source automatically.
- **`missing_canonical`:** confirm the task still exists, its owner matches the legacy row, and the canonical ID is genuinely absent. Establish whether the row was written after the one-time copy or omitted from it. Only after owner approval may a copy be proposed on the isolated target; retain the legacy source until client cutover and verification are complete.
- **`missing_task`:** do not copy or invent a replacement task link. Verify the FK is present and validated, compare the backup, and resolve the integrity anomaly separately.

Any approved correction must first be rehearsed on the isolated restored copy in an explicit transaction with before/after snapshots, expected affected-row counts, and `RETURNING` evidence. Re-run the report and verify that the row is either resolved or recorded as an owner-approved exception. No automated remediation is permitted. Production correction requires a separate explicit owner authorization after the complete backup/restore gate; this automation remains read-only.

Acceptance requires zero unresolved conflicts or a documented owner-approved exception list with explicit rationale and risk acceptance. A non-empty report is not automatically a failure, but silently ignoring a row is.

The disposable PostgreSQL fixture now covers four conflict rows: ID `30000000-0000-4000-8000-000000000002` (task-owner mismatch), ID `...0005` (cross-owner/task collision), ID `...0007` (same-owner/task payload-only collision), and ID `...0006` (missing canonical after reconciliation). The `missing_task` case remains defensive and is not seeded because the validated legacy task FK prevents an orphan in the normal fixture. CI #454 passed on implementation/test HEAD `44cde434c6507f1c492b373b6d53b60f5214bb8f`: 21/21 PostgREST preflight tests, 27/27 migration replay, four conflict rows with field-level payload evidence, 151/151 application tests, typecheck, production build, and npm audit with 0 vulnerabilities.

---

# Latest preflight update — activity-event append-only migration 26 (2026-11-21)

The branch contains 26 migrations; the last read-only production ledger contains 8, leaving 18 branch-only. Query 19 was executed read-only against production and confirmed the expected pre-migration activity_events state: RLS enabled, owner postgres, old FOR ALL policy, and broad table privileges for anon, authenticated, and service_role. No production change was made.

The disposable replay passed migration 26 and its reapplication. CI #442 passed 26/26 migrations, 17/17 PostgREST preflight tests, 147/147 application tests, typecheck, production build, and npm audit (0 vulnerabilities).

---

## Task DELETE event contract — migration 25 (2026-11-21)

Read-only preflight query **18** reports the task activity trigger's DELETE event mapping, authenticated-owner context guard, SECURITY INVOKER status, fixed search path, function grants, and the three existing cascade FKs. On an isolated target after migration 25, expected results are:

- `task_activity_trigger_enabled = true`
- `task_delete_event_enabled = true`
- `task_deleted_event_mapping_present = true`
- `task_delete_owner_context_guard_present = true`
- `task_activity_trigger_is_security_invoker = true`
- `task_activity_trigger_search_path_safe = true`
- authenticated and service_role EXECUTE = true; anon EXECUTE = false
- `task_parent_delete_cascade_preserved = true`
- `task_owner_delete_cascade_preserved = true`
- `activity_owner_delete_cascade_preserved = true`

Fresh read-only production execution of query 18 returned the expected pre-deployment state: the task activity trigger is absent, while all three cascade FK contracts are present. Migration 25 remains branch-only. The DELETE trigger emits events only when the authenticated JWT subject owns the deleted task; service-role/Auth-account cascades intentionally skip per-task events to preserve Auth cleanup.

CI #438 passed 25/25 PostgreSQL 17 migration replay, direct/cascade deletion rollback, Owner A/B isolation, Auth-account cleanup, and migration reapplication. No production DDL/DML or migration was applied.

---

## Task create request identity — migration 24 (2026-11-21)

Read-only preflight query **17** reports the `tasks.client_request_id` UUID column/default/not-null state, exact per-owner unique key, payload-hash type/check, immutable trigger, SECURITY INVOKER/search-path settings, and EXECUTE grants. Expected results:

- `task_request_id_not_null = true`
- `task_request_id_is_uuid = true`
- `task_request_id_default` resolves to `gen_random_uuid()`
- `task_request_hash_is_text = true`
- `task_request_unique_per_owner = true`
- `task_request_hash_format_check = true`
- `task_request_identity_trigger_enabled = true`
- `request_trigger_is_security_invoker = true`
- `request_trigger_search_path_safe = true`
- authenticated and service_role EXECUTE = true; anon EXECUTE = false

The new branch-only migration is `20261121000200_task_create_request_idempotency.sql`. The migration runner now expects **24 migrations** and runs sequential plus two-session concurrent retry assertions. The latest application tests include client request-state reuse, task/subtask same-request resolution, payload mismatch rejection, and conflict fallback. The migration remains branch-only; the live ledger remains at eight versions and the live `tasks` table still has no request-identity columns. Do not apply it to production before the owner-controlled complete backup and successful isolated restore.

## Activity-event access contract — migrations 23, 25, and 26

Read-only query **16** now verifies the transactional task trigger, SECURITY INVOKER/search-path contract, trigger EXECUTE grants, owner-scoped activity-event SELECT/INSERT policies, and absence of ALL/UPDATE/DELETE policies. On an isolated target after migration 26, expect:
- task activity trigger enabled; SECURITY INVOKER; fixed search path;
- authenticated and service_role EXECUTE = true; anon EXECUTE = false;
- `activity_events_select_owner_policy_present = true`;
- `activity_events_insert_owner_policy_present = true`;
- `activity_events_mutation_policies_absent = true`;
- authenticated INSERT = true; authenticated UPDATE/DELETE/TRUNCATE = false.

Read-only query **19** reports the complete table privilege matrix:
- authenticated and service_role: SELECT/INSERT = true; UPDATE/DELETE/TRUNCATE = false;
- anon: SELECT/INSERT/UPDATE/DELETE/TRUNCATE = false;
- postgres table owner: DELETE/TRUNCATE = true for owner-controlled maintenance;
- RLS enabled; separate owner-scoped SELECT/INSERT policies; no ALL/UPDATE/DELETE policy.

The Auth-account `ON DELETE CASCADE` remains. This is append-only for application roles, not tamper-proof against the table owner; no retention schedule is defined.

CI #442 passed on code/test HEAD `03217aefdefb88fee593629f217d7efaf36d538d`: 26/26 PostgreSQL 17 migrations, append-only privilege/RLS tests, 17/17 PostgREST safety tests, 147/147 application tests, typecheck, production build, and npm audit with 0 vulnerabilities.

Fresh read-only production query 19 returned the expected pre-migration state: RLS enabled, owner postgres, new SELECT/INSERT policies absent, the old FOR ALL mutation policy present, and broad privileges still granted to anon/authenticated/service_role. Migration 26 is not deployed. Do not apply it until the complete owner-controlled backup has been restored and verified in an isolated project and rollout is explicitly authorized.


> **Verified checkpoint — 2026-11-20 (Organization migration dependency and FK-contract audit).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test HEAD `b91e63bddb1decace36be78b3849dce02133fb9b`; [CI #396](https://github.com/mohith-krishnaa/personal-os/actions/runs/44762846651) passed on that exact HEAD. PR #11 remains open and unmerged; PR #12 remains an open superseded draft.

> Fresh read-only Supabase inspection: project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 in `ap-southeast-1`. The live migration ledger has exactly eight versions: 20260829182309, 20260830085036, 20260830103327, 20260830114218, 20260830120132, 20260830123420, 20260830141616, and 20260905162251. The branch contains 22 numbered SQL migrations, so 14 remain branch-only. All nine live public tables have RLS enabled and currently report zero rows.

> The live legacy schema matches the expected eight-version baseline: `projects.title/status` exist while `projects.name` is absent; `goals.unit/target` are absent; both checklist tables are absent; task/project/goal/reminder/notification FKs exist with the expected targets and delete actions; `notifications_reminder_unique` is a valid unique index on `notifications(reminder_id)`. The six baseline FKs inspected are validated, MATCH SIMPLE, NOT DEFERRABLE, and use ON UPDATE NO ACTION. The custom `auth.users.on_auth_user_created` trigger exists. `rls_auto_enable()` is SECURITY DEFINER with `search_path=pg_catalog`, and effective EXECUTE is denied to PUBLIC/anon/authenticated and granted to service_role. Installed extensions: pg_stat_statements 1.11, pgcrypto 1.3, supabase_vault 0.3.1, uuid-ossp 1.1.

> The 14 branch-only migrations were reviewed in timestamp order against those exact ledger versions and live catalog contracts. No missing prerequisite or dependency-order inversion was found. The migration replay script counts 22 files, replays them lexicographically, seeds legacy checklist fixtures after the legacy table is created and before reconciliation, and runs the read-only conflict report after replay.

> The audit found a fail-closed gap: the project/task FK guard and the reminder/notification migration verified ON DELETE and target columns but did not require the baseline ON UPDATE NO ACTION action when recognizing the old single-column FK. A noncanonical ON UPDATE CASCADE constraint could therefore be accepted as the expected legacy contract and then replaced with a different default action. The live baseline itself is canonical; this was a migration-guard weakness, not a detected live-schema mismatch.

> Corrected `20261119000300_ensure_project_task_foreign_keys.sql` and `20261120000200_enforce_reminder_notification_ownership.sql` to require ON UPDATE NO ACTION when matching the legacy contracts. Updated preflight query 11 to report and match the expected update action. Added rollback-only negative tests that install NOT VALID ON UPDATE CASCADE variants for project/task, reminder/task, and notification/reminder FKs and require the guards to fail closed. Migration count remains 22; no new migration was added.

> [CI #396](https://github.com/mohith-krishnaa/personal-os/actions/runs/44762846651) passed on code/test HEAD `b91e63bddb1decace36be78b3849dce02133fb9b`: acceptance preflight 17/17; PostgreSQL 17 migration replay 22/22; Organization/RLS, archive lifecycle, hierarchy/concurrency, and the new noncanonical ON UPDATE rejection cases passed; application tests 119/119; typecheck and production build passed; npm install audited 43 packages and reported 0 vulnerabilities. The workflow has no lint step. Expected SQL errors from the negative tests were matched by the runner and the step passed.

> No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. The complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and live two-owner PostgREST acceptance remain outstanding. The static audit and CI replay do not replace those owner gates.

> **Next action:** owner-controlled complete backup and isolated restore, then apply the 14 branch-only migrations only to that isolated target, review the checklist conflict report, and execute the authenticated two-owner PostgREST harness. If the owner action is still unavailable, do not retry production operations; continue with a static audit of runtime task/project create/update callers against the active-project and ownership triggers. Keep Analytics queued.

---


## Migration dependency audit

See [Organization V1 migration dependency and baseline audit](organization-v1-migration-order-audit.md). Read-only query 11 now includes the expected ON UPDATE NO ACTION action as well as target columns and ON DELETE behavior. A missing exact match must be reviewed before rollout; do not repair the live database from this report.

> **Verified checkpoint — 2026-11-20 (reminder delivery route contract).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `b49dfe13a175fee78bd20f7c34a5c651633ac812`; [CI #384](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734936277) passed. PR #11 remains open and unmerged.
>
> Extracted the reminder delivery request logic into `src/lib/reminder-delivery-handler.ts`, with the route exporting the same handler for GET and POST. `getReminderWorkerSecret()` preserves the existing precedence (`REMINDER_WORKER_SECRET`, then `CRON_SECRET`). No deployed secret values were read or committed. The existing `vercel.json` cron still targets `/api/reminders/deliver` every five minutes.
>
> Added `src/lib/reminder-delivery-handler.test.ts` to `npm test`. Both GET and POST are tested for missing configuration, missing/wrong credentials, no admin-client creation before authorization, exactly one `claim_due_reminders({ p_limit: 100 })` RPC on success, response count mapping, empty claims, returned RPC errors, and rejected RPC promises. Thrown transport/client errors return a generic HTTP 500 without exposing the thrown detail or worker token.
>
> The first test attempt [CI #381](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734618309) failed because the generated authorization regex contained a double-escaped whitespace token; corrected in `aae5007aa31b18b2e4ec84ee2efa42443c0dc49d`. [CI #382](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734660774) then exposed a test-fixture bug: passing `undefined` activated the harness default secret, so the missing-secret case was not actually missing; corrected in `c391ac9bbeb4e206f1f5dd3f0ec62c929010b7a0`. [CI #383](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734731617) passed migration replay and all 102 application tests but failed typecheck because `ProcessEnv` did not overlap with the narrow environment object type. The resolver now accepts `Record<string, string | undefined>`.
>
> [CI #384](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734936277) passed on the exact code/test commit `b49dfe13a175fee78bd20f7c34a5c651633ac812`: PostgreSQL 17 replayed **22/22 migrations**; Organization/RLS, archive, task hierarchy, and concurrency checks passed; **102/102 application tests passed**; TypeScript typecheck and production build passed. npm install audited 43 packages and reported **0 vulnerabilities**; the existing install-script allowlist warning remains. No lint script is configured.
>
> No database migration, application schema, RLS policy, or production record changed in this task. Repository migration count remains **22**. No production Supabase operation was performed; the last verified live checkpoint remains 8 migration-ledger entries versus 22 in the branch, but live state was not rechecked during this route-only task. Production rollout remains blocked on a complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation testing.
>
> **Next task:** prepare an isolated-environment authenticated two-user PostgREST acceptance harness and explicit environment preflight. It must refuse production project URLs, require an explicitly supplied isolated/restored target, test owner-scoped CRUD and cross-user denial, and never apply migrations or write to production. Keep Analytics queued.
>
> ---
>
> **Verified checkpoint — 2026-11-20 (atomic reminder delivery).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `2953e1eb29955d2464b2e565e80b41ad16a85510`; [CI #378](https://github.com/mohith-krishnaa/personal-os/actions/runs/44727301882) passed. PR #11 remains open and unmerged.
>
> A fresh read-only Supabase inspection found project `gujzvkyytxsnervovvrt` ACTIVE_HEALTHY on PostgreSQL 17.11.0.003, with 8 live migration-ledger entries and 9 public tables with RLS enabled. The live `claim_due_reminders(integer)` is still the older SECURITY DEFINER function: it locks due reminders with `FOR UPDATE SKIP LOCKED`, marks them delivered, and inserts the activity event, but it does not create the notification. Its execution is granted to `service_role` only. No production write was attempted.
>
> The branch worker previously performed notification upsert, delivered-marker update, and activity-event insert as separate PostgREST requests. If the final event insert failed after the delivered marker committed, the next run excluded that reminder and could not repair the missing event. The existing SQL claim function was not called by the route and did not create notifications.
>
> Added local-only migration `20261120000300_atomic_reminder_delivery.sql`, which replaces the claim function without changing its signature. Each claimed reminder now creates or safely reuses its matching notification, inserts `REMINDER_DELIVERED`, and only then sets `delivered_at` inside the same RPC transaction. An existing notification is reused only when its owner and task match; its read state is preserved. Any notification/event/update failure aborts the RPC statement and rolls back all writes, leaving the reminder retryable. The function remains SECURITY DEFINER with `search_path = pg_catalog, public`; EXECUTE is revoked from PUBLIC/anon/authenticated and granted only to service_role.
>
> `src/app/api/reminders/deliver/route.ts` retains its existing bearer-secret check and now calls only `claim_due_reminders(p_limit => 100)`; it no longer makes separate notification, reminder, and activity-event writes. The repository's `vercel.json` schedules this endpoint every five minutes; deployed secret configuration was not inspected.
>
> Added disposable-PostgreSQL fault-injection assertions for notification-insert and activity-event-insert failures, proving all writes roll back and retries succeed. Tests also verify an existing notification is reused without clearing `read_at`, repeated delivery produces no duplicate event/notification, and the RPC remains service_role-only. A separate two-session test proves Worker B completes with zero claims while Worker A holds the row lock, then exactly one notification, event, and delivered marker exist after Worker A commits. The migration is reapplied in CI to verify idempotence. Read-only preflight query 15 reports the function/security/locking contract.
>
> [CI #378](https://github.com/mohith-krishnaa/personal-os/actions/runs/44727301882) passed on the exact code/test commit: PostgreSQL 17 replayed **22/22 migrations**; the new migration reapplication, injected notification/event failure rollback and retry cases, existing-notification reuse, duplicate-call idempotency, two-session `SKIP LOCKED` concurrency, Organization/RLS, archive lifecycle, and hierarchy/project concurrency checks passed; **90/90 application tests passed**; TypeScript typecheck and production build passed. npm install audited 43 packages and reported **0 vulnerabilities**; the existing `esbuild@0.28.2` install-script allowlist warning remains. No lint script is configured.
>
> Repository migration count is **22**: 8 versions match the live ledger and 14 are branch-only (11 Organization/related, 1 Progress compatibility, 2 RLS performance). The new migration and route change are not deployed. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. Production rollout still requires a complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation.
>
> **Next task:** add route-level tests for the reminder endpoint's bearer-secret rejection, successful RPC result mapping, and RPC error handling; verify the cron route/secret contract without reading or exposing secret values. Keep Analytics queued until Organization acceptance is genuinely complete.
>
> ---
>
# Organization V1 — Live Preflight and Recovery Runbook

## Latest atomic reminder delivery verification — 2026-11-20

Code/test commit `2953e1eb29955d2464b2e565e80b41ad16a85510` passed [CI #378](https://github.com/mohith-krishnaa/personal-os/actions/runs/44727301882). The full 22-migration PostgreSQL 17 replay, migration reapplication, notification/event failure rollback and retry tests, existing-notification reuse, duplicate-call idempotency, two-session reminder claim concurrency, 90/90 application tests, typecheck, and production build passed.

The branch-only `20261120000300_atomic_reminder_delivery.sql` replaces `claim_due_reminders(integer)` with an atomic notification + activity-event + delivered-marker transaction. The API route now invokes this RPC after its bearer-secret check. Preflight query **15** reports the function signature, SECURITY DEFINER setting, configured search_path, notification/event writes, SKIP LOCKED clause, and role EXECUTE privileges. Expect exactly one row with service_role execution true and anon/authenticated execution false.

The repository has 22 migrations: 8 live-ledger versions and 14 branch-only versions. The live database still has the previous claim function and has not received this migration or the route deployment. No production operation was performed. The complete owner-controlled backup and isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation remain rollout gates.

The repository's `vercel.json` schedules `/api/reminders/deliver` every five minutes. The bearer-secret check is preserved; the deployed value/presence of `REMINDER_WORKER_SECRET` or `CRON_SECRET` was not inspected.

**Next repository task:** add route-level tests for bearer-secret rejection, successful RPC result mapping, and RPC error handling. Keep Analytics queued.

Last verified: 2026-11-20  
Supabase project: gujzvkyytxsnervovvrt (ap-southeast-1, PostgreSQL 17.11.0.003)  
Application rollout: BLOCKED — no recoverable backup has been produced.

This runbook records the live read-only inspection and the safe path to complete Organization V1. It does not authorize production DDL or a PR merge.

## Previous reminder/notification ownership integrity — 2026-11-20

Code/test commit `8fbf83e18fa15dc60a9a8bc8ab58563738d00df0` passed [CI #375](https://github.com/mohith-krishnaa/personal-os/actions/runs/44719688076): 21/21 PostgreSQL 17 migrations replayed; authenticated Owner A/B reminder INSERT/UPDATE and notification UPDATE assertions passed; service-role valid/invalid write assertions passed; migration reapplication and unexpected-FK fail-closed tests passed; archive lifecycle and task hierarchy/project concurrency checks passed; 90/90 application tests, typecheck, and production build passed. npm install reported 0 vulnerabilities; no lint script is configured.

The live policy catalog shows that `reminders_owner_insert/update` and `notifications_owner_update` constrain `user_id` only. The live foreign keys reference `tasks.id` and `reminders.id` without owner/task columns. Consequently, a direct authenticated PostgREST write can satisfy the owner policy while associating a reminder with another owner's task, or a notification with another owner's reminder/task. This is a schema-level capability inferred from the live policy/FK definitions; no production write was attempted to reproduce it.

The branch-only migration `20261120000200_enforce_reminder_notification_ownership.sql` replaces the weak reminder.task and notification.reminder links with composite foreign keys. It adds unique referenced keys on `tasks(id,user_id)` and `reminders(id,user_id,task_id)`; preserves `ON DELETE CASCADE`; enforces that notification user/task match its reminder; and prevents changing a reminder's task while a notification references its old key. The migration checks existing data before changing constraints and fails closed on unexpected extra foreign keys. Existing RLS policies remain unchanged.

The authenticated disposable-PostgreSQL fixture verifies both owners can create/reassign same-owner reminders and matching notification pairs; cross-owner task/reminder references and same-owner mismatches fail with foreign-key violations and preserve the prior relationship. A BYPASSRLS `service_role` fixture confirms the reminder delivery worker's valid insert shape still succeeds and invalid cross-owner writes remain rejected. This is not live PostgREST verification.

Fresh read-only live inspection: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, 8 migration-ledger entries, 9 public tables with RLS enabled. Live reminders/notifications still have the old single-column FKs; the new composite migration is not deployed. Repository count is 21 migrations (8 live, 13 branch-only: 10 Organization/related, 1 Progress compatibility, 2 RLS performance).

No production DDL/DML, migration, RLS change, backup, restore, or merge occurred. Owner-controlled complete schema/data/roles backup and successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation remain mandatory rollout gates.

**Next repository task:** audit the reminder delivery worker's service-role notification upsert and retry/claim behavior against the composite FK contract; verify valid delivery and duplicate idempotency without changing production. Keep Analytics queued.
 
## Latest authenticated parent-task reassignment verification — 2026-11-20

Code/test commit `0a4bd7e623cee437580d425d0fb71e5758febb47` passed [CI #364](https://github.com/mohith-krishnaa/personal-os/actions/runs/44694065363). The workflow replayed all 20 migrations in disposable PostgreSQL 17; authenticated Owner A/B and anonymous RLS assertions, project archive lifecycle, task hierarchy and two-session concurrency checks passed; 90/90 application tests, typecheck, and production build passed; npm install found 0 vulnerabilities. No migration was added; repository count remains 20.

The authenticated fixture verifies valid same-owner/same-project parent reassignment, rejects cross-project and cross-owner parent reassignment while preserving the previous parent, permits reparenting an existing task within an archived project's historical links, and verifies Owner B's reciprocal rejected update leaves its NULL parent unchanged. This is a disposable PostgreSQL role/RLS test, not a live PostgREST test.

Fresh read-only live inspection: project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003; the live ledger has 8 entries; all 9 public application tables have RLS enabled. Live `projects.title/status` and `tasks.project_id/parent_task_id` remain present, while `projects.name` and user-defined triggers on projects/tasks remain absent. No production DDL/DML, migration, RLS change, backup, restore, or merge occurred.

Owner action remains required: create a complete owner-controlled schema/data/roles backup and prove isolated restore; review checklist conflicts against that restored copy; then run authenticated two-user PostgREST CRUD/isolation tests. Do not apply migrations or alter production RLS before those gates and explicit approval.

**Next repository task:** add authenticated-role UPDATE coverage for hierarchy-cycle rejection and preservation of the previous parent link.

## Latest authenticated-role verification — 2026-11-20

Code/test HEAD `eb194521e6d1bb12147058530c84ce7315395a44` passed [CI #357](https://github.com/mohith-krishnaa/personal-os/actions/runs/44680309313). The full 20-migration PostgreSQL 17 replay and Organization/RLS assertions passed. The authenticated Owner A/B fixture asserts a non-superuser, non-BYPASSRLS `authenticated` role, then verifies ACTIVE subtask insertion, COMPLETED/ARCHIVED rejection with no residual rows, unchanged historical-link updates after archive, and cross-owner parent/project denial. The existing project archive lifecycle and both two-session concurrency cases passed; 90/90 application tests, typecheck, and production build passed; npm audit found 0 vulnerabilities. No migration was added; repository count remains 20.

Fresh read-only live inspection: project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003, with 8 ledger versions and 9 public tables all RLS-enabled. Live `projects.title/status` and `tasks.project_id/parent_task_id` remain present; `projects.name` and user-defined project/task triggers remain absent. The authenticated-role fixture is disposable PostgreSQL, not live PostgREST. No production schema or data was changed.

Owner action still required: create a complete owner-controlled schema/data/roles backup and prove isolated restore; review checklist conflicts against the restored copy; then run authenticated two-user PostgREST CRUD/isolation tests. Do not apply migrations or alter production RLS before those gates and explicit approval.

## Latest verified checkpoint — 2026-11-20

Code/test HEAD `c016f78410eac0ddcfd521be19890853bd5268b2` passed [CI #347](https://github.com/mohith-krishnaa/personal-os/actions/runs/44659601808): full PostgreSQL 17 replay of 20 migrations, Organization/RLS assertions, sequential project archive lifecycle assertions, two-session project-status/task-assignment races in both lock orders, the existing task-hierarchy cycle race, 87/87 application tests, TypeScript typecheck, and production build. No lint script is configured.

The first code/test attempt `0336eef34d4dfffd7bc498d896aadfbc1af31128` failed CI #374 because Owner A's negative notification UPDATE reused Owner B's reminder that already had a notification; the pre-existing `notifications_reminder_unique` index correctly rejected the duplicate before the new composite FK was evaluated. The test fixture was corrected by adding unused foreign-owner reminder IDs and targeting those IDs, so the regression now isolates the composite owner FK. No production data was involved. Corrected code/test commit `8fbf83e18fa15dc60a9a8bc8ab58563738d00df0` passed CI #375. Documentation checkpoint `4329dc2c88a528d2caaacba88ddd5dafaf34866d` passed CI #376 on the exact documentation HEAD. Documentation-only checkpoint `558b635d87e11cdf2657e18b922d143ce4d3aa60` passed [CI #372](https://github.com/mohith-krishnaa/personal-os/actions/runs/44711269740) on the exact final documentation HEAD.

The concurrency regression extends the disposable task-hierarchy fixture with `projects.status` and installs the branch-only active-project guard. In the assignment-first case, the archive transaction is observed blocked by the task transaction's `FOR SHARE` project lock; both then commit and the historical task link remains. In the completion-first case, the assignment is observed blocked by the project update; after completion commits, the assignment fails with the expected check violation and leaves no link. The test checks final state and session cleanup.

CI #346 failed because psql does not interpolate `:'variable'` syntax inside a `-c` SQL string; the logs showed a syntax error at the colon. Commit `c016f78410eac0ddcfd521be19890853bd5268b2` replaced those parameters with fixed test-owned application-name literals, and #347 passed. No migration was added; the branch remains at 20 files.

Fresh read-only live inspection: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, exactly 8 migration-ledger rows. The live schema still has legacy `projects.title/status` and `tasks.project_id/parent_task_id`; `projects.name` is absent; no user-defined triggers exist on the live `projects` or `tasks` tables. The branch-only trigger and its concurrency behavior have not been applied to production. No production DDL/DML, migration, RLS change, backup, restore, or merge occurred.

The owner-controlled complete schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation tests remain mandatory. No local checkout is attached, so local working-tree status is unverified.

**Next repository task:** audit every runtime task INSERT/creation path, including recurring generation and subtasks, to confirm it uses the ACTIVE-project service preflight or remains protected by the database trigger while preserving owner filters. Do not advance to Analytics until Organization acceptance is genuinely complete.

## Legacy checklist compatibility contract — 2026-11-19

### Runtime inventory

A branch-head audit inspected all 56 TypeScript/TSX/JavaScript files under `src/` and `lib/`, plus root `middleware.ts`. No runtime module references `task_checklist_items`. The current service in `src/lib/checklists.ts` uses only `checklist_items`; authenticated dashboard actions call `auth.getUser()` and pass the resolved user to that service. Service tests assert the canonical table and owner/task filters.

This establishes the repository's current client behavior only. It does not establish whether an older external or already-deployed client still calls the legacy table.

### Database behavior on the Organization branch

- `20260905170100_organization_v1_checklists.sql` creates `task_checklist_items` with RLS and authenticated owner-scoped SELECT/INSERT/UPDATE/DELETE policies. INSERT and UPDATE require the referenced task to belong to the authenticated owner.
- `20261117000200_harden_checklist_select_ownership.sql` additionally requires the referenced task to belong to the caller for SELECT visibility.
- `20261015000200_reconcile_checklist_tables.sql` performs a one-time copy of same-owner task rows into `checklist_items`. It preserves existing canonical IDs with `ON CONFLICT (id) DO NOTHING`.
- No migration installs a legacy-to-canonical synchronization trigger. A valid legacy write made after reconciliation is not guaranteed to appear in `checklist_items`; the read-only report identifies it as `missing_canonical`.

### Decision

1. `public.checklist_items` is the only supported table for current application code.
2. Keep `public.task_checklist_items` temporarily with its existing owner-scoped policies to avoid an unreviewed compatibility break for unknown older clients. It is a transitional compatibility surface, not a second source of truth.
3. Do not add dual-write/synchronization behavior, change legacy RLS/write permissions, or drop the legacy table in this audit. Those choices require an explicit compatibility window and owner approval.
4. Before a future sunset, inventory deployed clients and observe PostgREST/API logs for legacy-table reads/writes over an owner-approved window after the table exists in the target environment. Review every row returned by the conflict report against a complete backup restored in isolation.
5. A future deprecation should be staged: first restrict legacy writes through a reviewed forward migration while preserving a read/export window and rollback period; remove the table only in a separate later migration after the retention and rollback criteria are met.

### Current production limitation

As of the read-only inspection on 2026-11-19, the live project has 8 applied migrations and neither checklist table exists. Therefore production legacy-table traffic cannot yet be measured, and the branch's compatibility behavior is not deployed. The branch's 19-migration replay and mocked service tests do not replace a production backup restore or authenticated PostgREST isolation test.

## Verified checkpoint — 2026-11-19

The live project was rechecked read-only: ACTIVE_HEALTHY on PostgreSQL 17.11.0.003, exactly 8 applied migrations, and 9 public application tables with RLS enabled. All 9 currently report zero rows. Both checklist tables and the task-organization trigger are absent; `projects.name`, `goals.unit`, and `goals.target` are absent. The live migration ledger remains unchanged.

The branch now contains 19 numbered migrations: 8 live versions plus 11 local-only migrations (8 Organization, 1 Progress compatibility, 2 RLS performance). [CI #265](https://github.com/mohith-krishnaa/personal-os/actions/runs/44495502033) passed on exact code/test head `521ae65f60fc58e01d4be09f7de6b2ee84b5a0f1`. All configured steps succeeded: migration replay/RLS assertions, read-only preflight execution, hierarchy concurrency, application tests, typecheck, and production build. CI #257 and #261 also passed on their respective earlier heads.

The read-only preflight query 5 now includes Organization, goals, reminders, notifications, and progress_entries policies. The disposable migration bootstrap creates a minimal `supabase_migrations.schema_migrations` fixture, and the replay script executes the exact preflight after all 19 migrations and RLS assertions. This validates the preflight catalog queries against disposable PostgreSQL 17 without connecting to production.

The owner-controlled schema/data/roles backup and successful isolated restore are still missing. No production changes or PR merge were made.

## Current live evidence

Read-only Supabase project, migration, table, policy, constraint, and advisor calls are working again. Project metadata is ACTIVE_HEALTHY.

- The live migration ledger contains exactly 8 rows. The exact versions and names are listed below.
- All 9 public application tables have RLS enabled.
- Exact row counts are 0 for all 9 public application tables, auth.users, and storage.objects. This is useful context, not a backup.
- public.projects has the legacy title column and no name column. It also has goal_id, priority, start_date, and target_date. Its status check allows ACTIVE, COMPLETED, and ARCHIVED.
- public.tasks already has project_id and parent_task_id columns and their foreign keys. The Organization validation trigger is absent.
- Neither public.checklist_items nor public.task_checklist_items exists.
- Current projects and tasks policies are the legacy owner-wide policies. goals has one owner-wide policy plus four command-specific policies, creating overlapping permissive policies.
- No production migration, DDL, RLS change, data write, or merge was performed during this inspection.

### Live migration ledger

| Version | Name |
| --- | --- |
| 20260829182309 | create_personal_os_core |
| 20260830085036 | add_task_recurrence_v1 |
| 20260830103327 | add_recurring_occurrence_idempotency |
| 20260830114218 | create_reminders |
| 20260830120132 | reminder_notifications_v1 |
| 20260830123420 | atomize_reminder_delivery_claim |
| 20260830141616 | progress_goals_v1 |
| 20260905162251 | restrict_rls_auto_enable_execute |

The SQL statement for each applied migration was read from supabase_migrations.schema_migrations. The repository's previous core migration filenames had timestamp drift; two applied migrations were missing locally, and a second reminder-notifications file was not represented in the live ledger. The branch now restores the eight exact ledger versions and removes the duplicate local-only core migration. See supabase/migrations/README.md.

The nine Organization migrations remain local-only and unapplied:

1. 20260905170000_organization_v1.sql
2. 20260905170100_organization_v1_checklists.sql
3. 20261015000100_harden_checklist_ownership.sql
4. 20261015000200_reconcile_checklist_tables.sql
5. 20261015000300_prevent_task_hierarchy_cycles.sql
6. 20261016000100_projects_name_title_compatibility.sql
7. 20261117000200_harden_checklist_select_ownership.sql
8. 20261119000300_ensure_project_task_foreign_keys.sql
9. 20261120000100_enforce_active_project_task_links.sql

The other three local-only migrations are:

- `20261117000100_reconcile_progress_goal_metrics.sql` — Progress compatibility.
- `20261119000100_deduplicate_goals_owner_policies.sql` — remove four redundant goals policies.
- `20261119000200_optimize_reminder_progress_rls.sql` — optimize ten reminder, notification, and progress policy expressions.

Do not run migration up or migration repair until the local/remote history has been reviewed using the Supabase CLI and the rollout plan has been approved.

## Backup gate — owner-controlled export and isolated restore

This gate is not satisfied. No complete backup has been produced or restored. A zero-row check is useful inventory only; it is not a backup.

The last recorded Dashboard check says the Free Plan has no scheduled project backups. Recheck the current plan before relying on provider backups. No backup/export action is available through the connected Supabase tools in this run.

### Fresh source snapshot — 2026-11-21 (read-only)

- Project: gujzvkyytxsnervovvrt; region ap-southeast-1; ACTIVE_HEALTHY; PostgreSQL 17.11.0.003.
- Live project migration ledger: exactly eight versions: 20260829182309, 20260830085036, 20260830103327, 20260830114218, 20260830120132, 20260830123420, 20260830141616, 20260905162251.
- Repository branch at verified HEAD: 27 numbered migrations; 19 are not present in the live ledger. The repository migration runner expects and replays all 27.
- All nine public application tables are present, RLS-enabled, and currently contain zero rows: activity_events, goals, notes, notifications, profiles, progress_entries, projects, reminders, tasks. The transitional checklist tables are absent from this source baseline.
- auth.users=0; storage.buckets=0; storage.objects=0; vault.secrets=0.
- auth.schema_migrations has 84 provider-managed rows; storage.migrations has 81 provider-managed rows; the project migration ledger reports eight project versions. Do not treat auth/storage migration metadata as application data or copy provider-owned migration history into a new project.
- Installed non-plpgsql extensions: pg_stat_statements 1.11, pgcrypto 1.3, supabase_vault 0.3.1, uuid-ossp 1.1. Verify the same versions are available/enabled on the isolated target before restore.
- No auth/storage RLS policies were returned by the catalog query.
- Twelve non-internal triggers exist across auth/storage: one auth trigger and eleven Storage platform triggers. The project-owned auth.users.on_auth_user_created trigger calls public.handle_new_user(); its function is owned by postgres, is SECURITY INVOKER, and has search_path=public. The auth.users table is owned by supabase_auth_admin. The eleven Storage trigger functions/tables are owned by supabase_storage_admin; do not copy those platform triggers manually.
- No Edge Functions are currently listed (rechecked 2026-11-21). Project-level Auth/Realtime/webhook/secret settings were not refreshed in this run; inventory them immediately before backup.

### Export from a private workspace

The repository has no supabase/config.toml. Do not assume supabase link will work from the repository root. Use a private temporary workspace outside Git, initialize the CLI there, and keep all dump files outside the repository. The Supabase CLI db dump command runs pg_dump in Docker. Use a PostgreSQL 17 client for verification.

Set SOURCE_DB_URL from the Supabase Dashboard Connect panel in the owner-controlled shell. Prefer the direct connection; use the session pooler if the network cannot reach the direct IPv6 endpoint. Do not put the connection string in shell history, Git, CI logs, or ChatGPT. Disable shell tracing before running commands.

~~~bash
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"
supabase init
umask 077
read -rsp "Source DB URL: " SOURCE_DB_URL
printf '\n'
test -n "$SOURCE_DB_URL" || { echo "SOURCE_DB_URL is required." >&2; exit 1; }
supabase --version
psql --version

supabase db dump --remote="$SOURCE_DB_URL" -f roles.sql --role-only
supabase db dump --remote="$SOURCE_DB_URL" -f schema.sql
supabase db dump --remote="$SOURCE_DB_URL" -f data.sql --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"

supabase db dump --remote="$SOURCE_DB_URL" -f migration-history-schema.sql --schema supabase_migrations
supabase db dump --remote="$SOURCE_DB_URL" -f migration-history-data.sql --use-copy --data-only --schema supabase_migrations
unset SOURCE_DB_URL
~~~

Use the current Supabase CLI `--remote=<ref|branch|url>` selector for every export. For a connection string, keep the equals form exactly as shown (`--remote="$SOURCE_DB_URL"`); the flag parser does not consume a separate following token. The current CLI documentation says `--db-url` is deprecated in v3 and removed in v4, while `--remote` accepts a PostgreSQL URL and prints a `Target:` line to stderr. The hosted Supabase reference page still shows the older `--db-url` alias, so do not copy that stale syntax. Record `supabase --version`, verify each printed `Target:` line and the Dashboard Connect details identify source project `gujzvkyytxsnervovvrt`, and stop on any mismatch. See the [current Supabase CLI db dump documentation](https://github.com/supabase/cli/blob/develop/apps/cli/docs/supabase/db/dump.md) and [current target flag implementation](https://github.com/supabase/cli/blob/develop/apps/cli/src/command-internal/target/target-flags.ts). The default dump excludes Supabase-managed auth/storage schemas and extension-created schemas, and it does not include data or custom roles unless the corresponding flags are supplied. The separate migration-history export is required to preserve the exact eight-version baseline.

The standard dump does not include Storage object bytes. Current buckets/objects are both zero; if either becomes non-zero before backup, export the object bytes through the Storage API and verify each object's size/checksum separately. Likewise, the current auth.users count is zero; if it becomes non-zero, use Supabase's documented Auth migration procedure or a supported full backup/SQL export path rather than assuming the default dump contains Auth data.

The project has a custom auth.users trigger even though auth.users is empty. The public.handle_new_user() function is in the public schema dump, but the trigger is in the excluded auth schema. After restoring the public schema, explicitly recreate and verify this trigger on the isolated target using the exact statement from 20260829182309_create_personal_os_core.sql:

~~~sql
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
~~~

Do not replay the entire already-applied core migration just to restore this trigger. Do not copy the eleven Storage platform triggers. If other customizations in auth/storage are found, capture and review them separately with the Supabase CLI diff workflow using the exact eight live migrations as the baseline. In the private scratch workspace, copy only the eight exact live migration files into supabase/migrations, link that workspace to the source project, and run the CLI diff without applying it. With the default pg-delta engine, a plain remote diff captures customizations in managed schemas; if the workspace uses the legacy migra engine (pg-delta disabled), use the explicit auth,storage schema filter. Review the generated SQL manually. The current auth trigger is already in the baseline, so a diff against the same baseline may not emit it.

The installed supabase_vault extension has zero rows in vault.secrets, but the root encryption key is not contained in database dumps. Because the extension is installed, treat the key as a separate restore dependency: preserve it through the documented Supabase procedure while the source project is active, then copy it to the isolated target and verify decryption. If the owner elects not to transfer it because there is no encrypted data anywhere in the project, record that explicit inventory decision; do not infer it from vault.secrets alone. Never put the key in the repository, backup manifest, CI, or chat. Do not pause or delete the source before the key decision is complete. Custom LOGIN roles exported in roles.sql may require new passwords to be set manually on the isolated target.

Also inventory project-level configuration that SQL dumps do not contain: Auth providers/redirect settings, JWT/API key rotation requirements, database webhooks, Realtime publications, Vercel cron configuration and secret names, and any project secrets. The live project currently lists no Edge Functions; the application reminder cron is versioned in vercel.json, but deployed environment-secret values were not inspected. Transfer secret values only through an owner-controlled secret manager, never through the manifest.

Create a private backup manifest containing only non-secret metadata:
- source project ref, source region, PostgreSQL version, UTC export time, Supabase CLI version, and PostgreSQL client version;
- the eight exact live migration versions and the 27-file repository inventory;
- installed extension names/versions;
- exact source row counts for all nine public tables, auth.users, storage buckets/objects, and vault.secrets;
- artifact filenames, byte sizes, SHA-256 hashes, and command exit statuses;
- any Auth/Storage/Vault/custom-schema supplements and their verification results.

All export commands must exit successfully. Record hashes even when a data-only export contains no row payload because every application table is empty. Do not accept an empty export as proof by itself.

### Restore into a separate isolated project

Create a separate isolated Supabase project; do not use the production project, a production branch, or the connected production restore operation. Match PostgreSQL major version and enable the same installed extensions before restoring. Review Supabase's documented handling for custom roles and platform-owned objects; do not broadly strip ownership or ACL statements to make a restore appear successful.

### Restore roles and prepare target default privileges

Restore the custom-role export first so every source owner role exists before privilege preparation. This is still only the isolated target:

~~~bash
psql --single-transaction --variable ON_ERROR_STOP=1 --file roles.sql --dbname "$TARGET_DB_URL"
~~~

The Supabase CLI restore documentation warns that a new project's default privileges can grant broad access to restored tables. Before restoring schema objects, connect as `postgres` and revoke the target's default table grants to `anon` and `authenticated` for the role that owns the restored public objects:

~~~bash
psql "$TARGET_DB_URL" --set ON_ERROR_STOP=1 <<'SQL'
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated;
SQL
~~~

The live source snapshot shows public application tables owned by `postgres`. If the reviewed schema export assigns public objects to any other owner role, apply the same `ALTER DEFAULT PRIVILEGES FOR ROLE <owner>` statement for each such role after `roles.sql` has created it and before `schema.sql` is restored. This changes defaults for the specified owner only; do not broadly strip source ACLs. Apply the same three statements for every reviewed owner role that will create public objects. Repeat this preparation before any later restore into the same target. Run these commands only on the new isolated target, never on production. See the [current CLI dump privilege-migration note](https://github.com/supabase/cli/blob/develop/apps/cli/docs/supabase/db/dump.md#note-on-privilege-migration).

After restore, capture the target's public-table default ACLs and compare them with the source manifest and intended owner roles:

~~~sql
select
  defaclrole::regrole as owner_role,
  defaclobjtype as object_type,
  defaclacl as default_acl
from pg_default_acl
where defaclnamespace = 'public'::regnamespace
  and defaclobjtype in ('r', 'f', 'S')
order by defaclrole::regrole::text;
~~~

Use the documented logical restore sequence against TARGET_DB_URL:

~~~bash
psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file schema.sql \
  --command 'SET session_replication_role = replica' \
  --file data.sql \
  --dbname "$TARGET_DB_URL"

psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file migration-history-schema.sql \
  --file migration-history-data.sql \
  --dbname "$TARGET_DB_URL"
~~~

If the target already has migration history, stop and inspect it before importing the source history; never overwrite or repair a conflicting ledger blindly. Restore the auth.users trigger supplement after public.handle_new_user() exists and before creating test users. If any Auth users, Storage objects, Vault secrets, custom policies, or other managed-schema customizations exist at backup time, complete their separately documented restore path and verify them before proceeding.

### Restore verification — mandatory evidence

Do not proceed on a successful psql exit alone. Record and verify all of the following on the isolated target:

1. All artifact hashes match the private manifest; both restore commands exited zero with ON_ERROR_STOP enabled and no ignored errors.
2. The exact eight source migration versions exist in supabase_migrations.schema_migrations. No branch-only migration is marked applied.
3. The nine public application tables and all source row counts match. At the 2026-11-21 source snapshot, all nine public application tables, auth.users, storage.buckets, storage.objects, and vault.secrets had zero rows.
4. The four installed extension versions match.
5. RLS remains enabled on all nine public application tables; compare policy names, roles, commands, USING/WITH CHECK expressions, grants, foreign keys, triggers, and functions with the read-only preflight output.
6. auth.users.on_auth_user_created exists and calls the matching public.handle_new_user() definition. Confirm a disposable user created only on the isolated target receives the expected profile row.
7. Any non-empty Storage export is restored and every object is readable with matching size/checksum. Any Vault data decrypts with the preserved root key.
8. After the base restore is verified, confirm the isolated target has exactly the eight baseline migrations applied and the 19 branch-only migrations pending (27 repository migrations total). Review `supabase db push --dry-run`; apply those 19 migrations only to the isolated target, never production.
9. After both checklist tables exist, run the SELECT-only conflict report, save its private output, and complete the per-row disposition register described above. Require zero unresolved conflicts or a documented owner-approved exception list before proceeding.
10. Run the authenticated two-owner PostgREST acceptance harness only after the restore and checklist disposition gates pass.

The connected automation environment has no repository checkout, Docker daemon, Supabase CLI, pg_dump, or psql, and no database password. It cannot create or restore these artifacts. No production migration, DDL/DML, RLS change, backup, restore, or merge was performed by this automation.

## Advisor snapshot

- Security advisor: no lints.
- Health advisor: no lints.
- Performance advisor snapshot (read-only, 2026-11-19):
  - 4 unindexed foreign keys: notifications.task_id, projects.goal_id, tasks.parent_task_id, tasks.project_id.
  - 14 auth_rls_initplan warnings across goals, reminders, notifications, and progress_entries.
  - 13 unused-index findings. Do not drop indexes solely because they are currently unused.
  - 4 multiple-permissive-policy findings on goals because goals_owner overlaps the four command-specific policies.
  - Security and health advisors returned no lints.
- A fresh read-only index probe confirmed that the expected index names `notifications_task_id_idx`, `projects_goal_id_idx`, `tasks_parent_task_id_idx`, and `tasks_project_id_idx` are absent from the live database.
- The pending migration chain already creates the latter three indexes: the two task indexes in `20260905170000_organization_v1.sql`, and the conditional project-goal index in `20261016000100_projects_name_title_compatibility.sql`. The full migration replay assertion now checks that each exists and is valid/ready. They remain absent from production until the migrations are approved and applied.
- `notifications.task_id` has no corresponding pending migration and remains outside Organization V1; track it for reminder/production hardening.

Do not change live policies or indexes as part of this preflight. Review each finding against the query workload and migration history after a verified backup.

## Read-only SQL preflight

Run supabase/operations/organization-v1-preflight.sql in the Supabase SQL Editor. It contains SELECT statements only and reports the migration ledger, required table/column presence, RLS flags, policies, triggers, constraints, and indexes. Query 4 includes the Progress compatibility columns `goals.unit` and `goals.target`. Query 5 includes Organization, goals, reminders, notifications, and progress_entries policies. Query 12 reports the goal metric column types/nullability and the `goals_unit_nonempty` / `goals_target_positive` constraint definitions and validation state. These checks can run before and after the pending migrations because the base `goals` table already exists. The exact preflight file is also executed at the end of the disposable migration replay in CI; the test bootstrap creates only a minimal migration-ledger fixture so the preflight syntax and catalog queries are exercised without connecting to production. Re-run it immediately before and after any approved rollout.

Query 10 reports `rows_blocking_name_compatibility` and `rows_with_name_title_drift` for `projects`. It uses `to_jsonb(p)->>'name'` and `->>'title'`, so it can run before the optional `name` column exists. It counts null, blank, space-only, tab/newline-only, and over-120-character resulting names as blocking; it separately reports rows where both columns exist but disagree. Do not apply the compatibility migration while either count is non-zero. Do not silently truncate or overwrite existing project names; any remediation must be reviewed and covered by a verified backup/restore plan. The 2026-11-19 read-only live probe returned 0 projects, 0 blocking rows, and 0 drift rows.

The compatibility migration's validated check and trigger now require a non-whitespace character and a trimmed length from 1 to 120. Disposable assertions verify the constraint is validated, reject invalid application `name` and legacy `title` writes, and verify both name-only and title-only inserts plus bidirectional updates. [CI #278](https://github.com/mohith-krishnaa/personal-os/actions/runs/44505121491) passed on code/test commit `582fd8337c13f0c7d67059dd8335ab94183077af`, including all 18 migrations, RLS assertions, preflight, hierarchy concurrency, application tests, typecheck, and production build. The final title-only insert regression is on code/test commit `62a27a00927797aa8c323ec370d1b2661ceb2d72`; [CI #279](https://github.com/mohith-krishnaa/personal-os/actions/runs/44505338156) passed on this exact commit, including the complete migration replay, preflight, hierarchy, application test, typecheck, and build steps.

## Safe rollout sequence

1. Produce and restore-test the manual backup described above.
2. Run supabase migration list and confirm the eight applied versions exactly match the reconstructed repository files. Resolve any discrepancy locally; do not repair the remote ledger by guesswork.
3. Review all eight Organization migrations against the live schema snapshot and test them against a disposable database matching that schema.
4. Confirm the intended order and recovery plan. In particular, verify the legacy projects.title to application projects.name compatibility path, checklist table creation/reconciliation, task relationship constraints/triggers, and RLS policy replacement.
5. Apply only the reviewed Organization migrations after explicit production rollout approval.
6. Re-run the SQL preflight and security/performance/health advisors.
7. Exercise project, task association, subtask, and checklist CRUD with two distinct authenticated users. Verify direct API writes cannot attach another user's project, parent task, or checklist row.
8. Merge PR #11 only after database verification, recovery, authorization, and current-head CI gates pass. PR #12 remains a superseded draft and must not be merged separately.

Analytics V1 remains queued behind Organization V1. No Analytics, AI Assistant, Research Agent, or Adaptive Scheduling feature work should bypass this gate.


## Task hierarchy concurrency verification — 2026-11-17

The branch's unapplied `20261015000300_prevent_task_hierarchy_cycles.sql` migration now acquires an owner-scoped transaction advisory lock before validating parent/project links and traversing ancestors. Owner transfers acquire old/new lock keys in deterministic order. This closes the previously identified same-owner concurrent-write race under the application's normal READ COMMITTED transaction behavior, subject to the integration test below.

CI #173 passed a disposable PostgreSQL 17 test that applies the actual migration function, attaches the trigger using the earlier Organization migration's event definition, verifies the ownership/project/self/cycle checks, then runs two separate READ COMMITTED writers. The second writer is observed waiting on the advisory lock and is rejected after the first writer commits because its inverse edge would create a cycle.

Scope limits: this focused fixture does not apply the entire six-migration Organization sequence, reproduce the live Supabase legacy schema in full, test RLS/PostgREST with two users, or restore a production backup. The trigger remains absent from the live database. Do not treat CI #173 as production acceptance or authorization to apply migrations.

## Parent changes with existing children — 2026-11-17

The cycle-prevention migration also rejects updates to a parent task's owner or project when an existing direct child would be left with a different owner or project. This check runs under the same owner-scoped transaction advisory lock as child relationship writes. CI #176 passed disposable PostgreSQL 17 tests for both invalid parent project moves and invalid parent owner transfers, in addition to the two-session concurrent cycle test.

This remains branch-only migration coverage. The live database has no Organization trigger yet, and the integration fixture is not a full six-migration replay, production backup restore, RLS test, or authenticated two-user PostgREST test.

## Full migration replay and authenticated isolation — 2026-11-17

CI #189, #191, and #195 replayed all 15 local SQL migration files against a disposable PostgreSQL 17 database. CI #195 also verified the final project-state, roadmap, handoff, and runbook documentation checkpoint. The fixture bootstraps the Supabase roles and auth helpers, seeds legacy `projects.title` rows and legacy checklist items before the reconciliation migration, then verifies:

- both checklist tables remain present and the canonical table receives only checklist rows whose task owner matches the item owner;
- the legacy project `title` and application `name` columns remain synchronized in both directions;
- the `rls_auto_enable()` function is not executable by `anon` or `authenticated`, while its pre-existing `service_role` grant remains;
- separate authenticated Owner A and Owner B sessions cannot read or mutate each other's projects, tasks, or checklist items;
- the hierarchy concurrency integration still rejects a concurrent inverse edge that would create a cycle.

This closes the disposable full-chain and simulated two-owner RLS test gap. It does not restore a production backup, reproduce the exact live Supabase environment, or exercise live PostgREST JWT/API behavior. Production rollout remains blocked by the missing private backup/restore test and explicit approval.

## Related live Progress V1 schema mismatch

The same live schema inspection found that `public.goals` lacks `unit` and `target`, although the dashboard progress service selects both columns. The original Progress V1 migration used `CREATE TABLE IF NOT EXISTS` after the core migration had already created `goals`, so those columns were not added. A forward-only branch migration, `20261117000100_reconcile_progress_goal_metrics.sql`, adds nullable columns and checks without inventing metrics for legacy goals. The dashboard now handles legacy rows without those metrics. This migration is also unapplied in production and must be included in the backup/restore-tested rollout.


## Disposable authenticated mutation verification — 2026-11-17

CI #204 passed the full local migration replay and now includes stronger two-owner RLS assertions:

- Both owners have valid legacy checklist records; the reconciliation migration must copy both to checklist_items.
- A malformed Owner A checklist row attached to Owner B's task must not be copied.
- Each owner sees only its own projects, tasks, canonical checklist rows, and legacy checklist rows.
- Each owner’s UPDATE and DELETE attempts against the other owner's project, task, canonical checklist item, and legacy checklist item must each affect zero rows.

This is a disposable PostgreSQL 17 test. It does not replace a private production backup/restore, a live PostgREST JWT test, or approval to apply migrations. The live database was not changed.

CI: [run #207](https://github.com/mohith-krishnaa/personal-os/actions/runs/44055203271) on code-bearing head a9f73bfc26de818679c101974544793a839f2c74.


## Reciprocal insert and relationship-reassignment checks — 2026-11-17

CI #209 extends the disposable PostgreSQL 17 fixture beyond read visibility and UPDATE/DELETE isolation. Under Owner B's JWT subject, it now attempts:

- Inserting a project with Owner A's user_id.
- Inserting a task that references Owner A's project.
- Inserting canonical and legacy checklist items that reference Owner A's task.
- Reassigning Owner B's task to Owner A's project and parent task.
- Reassigning Owner B's canonical and legacy checklist items to Owner A's task.

Each operation must raise insufficient_privilege; the test raises an uncaught exception if an operation is accepted. Owner A's corresponding insert/link tests and reciprocal UPDATE/DELETE checks remain in the fixture.

[CI #209](https://github.com/mohith-krishnaa/personal-os/actions/runs/44064242592) passed the full 15-migration replay, task-hierarchy concurrency checks, 58 application tests, typecheck, and production build. This remains a disposable-database result, not a live PostgREST authorization test. The live database was not changed; the backup/restore and production approval gates remain mandatory.


## Checklist SELECT ownership hardening — 2026-11-17

The seventh Organization migration, 20261117000200_harden_checklist_select_ownership.sql, tightens SELECT policies on both canonical and legacy checklist tables. Visibility now requires the checklist row and its referenced task to belong to the authenticated caller.

The disposable migration fixture seeds malformed canonical and legacy rows with Owner A's user_id but Owner B's task_id. Owner A must not see either row; each owner must still see their valid checklist rows. [CI #211](https://github.com/mohith-krishnaa/personal-os/actions/runs/44065216491) passed the full 16-migration PostgreSQL 17 replay and all configured application checks. [CI #212](https://github.com/mohith-krishnaa/personal-os/actions/runs/44065285214) passed the assertion-message correction.

This migration is not applied to the live project. The live checklist tables are still absent, and no production DDL or policy change was performed.


## Anonymous-role verification — CI evidence only (2026-11-17)

The migration assertion fixture now grants `anon` table-level SELECT/INSERT/UPDATE/DELETE privileges before switching to the anonymous role with an empty JWT subject. It verifies:

- Zero visible rows in projects, tasks, canonical checklist items, and legacy checklist items.
- Anonymous INSERT attempts are rejected for each of those four tables.
- Anonymous UPDATE/DELETE attempts cannot affect authenticated records.

[CI #216](https://github.com/mohith-krishnaa/personal-os/actions/runs/44072614729) passed the full 16-migration PostgreSQL 17 replay, authenticated two-owner isolation, anonymous denial, task-hierarchy concurrency, application tests, typecheck, and production build.

This is not a live PostgREST test. The live project still has no Organization tables or Organization migrations applied, and no backup/restore has been completed. During production acceptance, test anonymous and two separate authenticated identities against a restored snapshot before applying migrations to the live project.


## Complete anonymous Organization CRUD verification — 2026-11-17

The disposable PostgreSQL fixture now grants the `anon` role table-level SELECT/INSERT/UPDATE/DELETE privileges on all four Organization tables, then verifies all four operations are denied by RLS under an empty JWT subject. This prevents missing SQL grants from creating a false-positive authorization test. [GitHub Actions run 44082207231](https://github.com/mohith-krishnaa/personal-os/actions/runs/44082207231) passed the full 16-migration replay, hierarchy concurrency, 58 application tests, typecheck, and production build.

This remains test-fixture evidence only. The live project has no Organization tables yet; do not apply migrations until a private schema/data/role backup is restored successfully and live JWT/PostgREST checks are completed.


## Migration index assertions — 2026-11-18

The disposable full-chain assertion now fails if any of the three indexes supplied by the pending Organization/compatibility migrations is missing, invalid, or not ready. This makes the intended remediation independently verifiable before rollout. It does not assert that the live database has these indexes; the live probe confirms they are absent. The fourth finding, `notifications.task_id`, remains a separate reminder/production-hardening item.

CI #222 passed on code-bearing commit [da8d9bc](https://github.com/mohith-krishnaa/personal-os/commit/da8d9bc39015c9897135b9477f8eb713f982be5e) ([run 44345681369](https://github.com/mohith-krishnaa/personal-os/actions/runs/44345681369)): the full 16-migration PostgreSQL 17 replay including all three index assertions, hierarchy concurrency integration, 58 application tests, TypeScript typecheck, production build, and npm install audit with 0 vulnerabilities. No lint script/configuration exists. Documentation-only checkpoint [a97c180](https://github.com/mohith-krishnaa/personal-os/commit/a97c180578d1712c9023a970b4eff091c6dbb0b0) passed CI #223 ([run 44346093573](https://github.com/mohith-krishnaa/personal-os/actions/runs/44346093573)). The new ninth read-only preflight query was executed separately against live Supabase and returned `index_exists=false`, `index_ready=false`, and `index_valid=false` for all four expected index names. No production DDL, migration, index creation, RLS change, data write, backup restore, or PR merge was performed.


## Current CI and live index probe — 2026-11-18

The full migration replay now asserts that `tasks_project_id_idx`, `tasks_parent_task_id_idx`, and `projects_goal_id_idx` exist and are both ready and valid after all 16 local migrations. CI #222 passed this assertion on PostgreSQL 17. The read-only preflight query 9 reports the four expected names, including `notifications_task_id_idx`; all four are absent in the live database. The three Organization/compatibility indexes are supplied by pending migrations, while the notifications index remains outside Organization V1. Do not manually create any of them in production before the backup/restore and rollout gates pass.


## Automation status — 2026-11-19

The Personal-OS Builder automation is enabled. It may continue safe repository-side implementation, static review, tests, and documentation while production rollout is blocked. It must not apply production DDL/migrations or merge PR #11. The backup/restore and live authenticated API gates remain owner-controlled.


## Checklist reconciliation ID-collision review — 2026-11-19

The general `supabase/operations/organization-v1-preflight.sql` remains SELECT-only and safe to run both before and after Organization migrations. Do not add static references to checklist tables that may not exist yet.

After both checklist tables exist, run the separate SELECT-only report:

    supabase/operations/checklist-reconciliation-conflicts.sql

It joins legacy and canonical checklist rows by ID and reports owner, task, and payload mismatches. The reconciliation migration uses `ON CONFLICT (id) DO NOTHING`: an existing canonical row is preserved, and a conflicting legacy source row remains in the legacy table without being copied to the canonical application table. Any returned row requires explicit review; do not automatically overwrite either side or mark reconciliation complete. Resolve cases on a verified restored copy first and obtain owner approval before any production data correction.

The disposable migration fixture now seeds one cross-owner same-ID collision. Assertions verify the canonical Owner B row remains unchanged, the Owner A legacy source row remains intact, and neither owner can read the other's row. The migration replay script executes the general preflight and then the dedicated conflict report after all 18 migrations. [CI #290](https://github.com/mohith-krishnaa/personal-os/actions/runs/44514046666) passed the exact code/test head `83c4e99ce30ae47a558931fbc93e6f6d9cf4159f`, including migration replay, both read-only reports, RLS assertions, hierarchy concurrency, 58 application tests, typecheck, and production build.

Fresh live read-only SQL still shows 8 applied migrations; `projects` and `tasks` exist with RLS enabled, while both checklist tables are absent. No live checklist conflict can be inspected until a restored schema contains those tables. No production changes were made.


## Post-reconciliation legacy-write drift — 2026-11-19

The migration `20261015000200_reconcile_checklist_tables.sql` performs a one-time insert from `task_checklist_items` into `checklist_items`. It does not create an ongoing legacy-to-canonical synchronization trigger. Because the legacy table is retained and its owner-scoped policies still permit writes, a valid legacy-client write after the migration can remain absent from the canonical table used by the current application.

The read-only `supabase/operations/checklist-reconciliation-conflicts.sql` report now classifies:
- `missing_task`: legacy task reference cannot be resolved (defensive detection for malformed/constraint-drifted data).
- `task_owner_mismatch`: the referenced task belongs to another owner.
- `missing_canonical`: a valid same-owner legacy row has no canonical row, including a write made after the one-time reconciliation.
- `canonical_id_collision`: the canonical ID exists but owner, task, or payload differs.

CI #293 ([run](https://github.com/mohith-krishnaa/personal-os/actions/runs/44522858528)) replayed all 18 migrations on disposable PostgreSQL 17, then seeded one valid legacy-only row after reconciliation. The report returned exactly three seeded unresolved rows: one task-owner mismatch, one non-identical canonical ID collision, and one missing-canonical row. It did not return the two valid legacy rows that were copied successfully. The same run passed Organization RLS assertions, hierarchy concurrency, the general read-only preflight, 58/58 application tests, typecheck, and production build.

This is disposable CI evidence only. Live Supabase still has 8 applied migrations and neither checklist table exists, so no live legacy-write drift can currently be measured. Do not add a trigger, disable legacy writes, delete legacy data, or repair rows in production until the owner-controlled backup/restore and explicit rollout approval gates are satisfied. The next repository task is to inspect all runtime callers and determine whether legacy writes are still supported by any deployed client before choosing a compatibility/deprecation policy.



## Checklist task-FK drift assertion — 2026-11-19

The checklist conflict report includes `missing_task` as a defensive drift category. Under the expected schema, this should not occur: both checklist tables have a NOT NULL `task_id` column with a validated FK to `public.tasks(id)` and `ON DELETE CASCADE`. The full migration replay assertion now verifies those properties for both tables. If it ever fails, stop rollout and inspect the table definition/constraint validation on the restored copy; do not repair production by writing data or altering constraints during preflight.

Code/test commit: `7e3d75f46214d078cfc1d4ba7a416584127aa05b`. [CI #296](https://github.com/mohith-krishnaa/personal-os/actions/runs/44542112681) passed the 19-migration PostgreSQL 17 replay, RLS assertions, hierarchy concurrency, 58/58 application tests, typecheck, and production build. [CI #297](https://github.com/mohith-krishnaa/personal-os/actions/runs/44542401798) passed on the subsequent documentation head `ab6a3381109d50496e1171494f9191f304b03298`. Live Supabase remains read-only with 8 applied migrations and both checklist tables absent. No production changes were made.

## Project/task/checklist FK preflight — 2026-11-19

Read-only live schema inspection confirms the current legacy project/task relationships exist and the live project remains on the eight-migration core ledger. The checklist tables do not exist in production, so their contracts cannot be verified there yet.

Repository query 11 now reports five expected relationships: `tasks.project_id -> projects.id SET NULL`, `tasks.parent_task_id -> tasks.id CASCADE`, `projects.goal_id -> goals.id SET NULL`, and each checklist table's `task_id -> tasks.id CASCADE`. It counts every FK containing each source column, including composite constraints, and separately reports whether the exact validated single-column target/action is present.

The disposable migration assertion requires each checklist `task_id` to be NOT NULL and to participate in exactly one FK, which must be a validated single-column reference to `public.tasks(id) ON DELETE CASCADE`. CI #302 also injects an extra NOT VALID FK from each checklist task_id to `auth.users(id)` in a transaction and confirms the assertion rejects the schema before the transaction is rolled back. The job log explicitly confirms the negative test passed. [CI #302](https://github.com/mohith-krishnaa/personal-os/actions/runs/44563968200) passed the full 18-migration PostgreSQL 17 replay, Organization/RLS assertions, read-only preflight, negative FK test, reconciliation conflict report, hierarchy concurrency, 58/58 application tests, typecheck, and production build.

No migration was added; the branch remains at 18 SQL migrations. The negative test is disposable PostgreSQL evidence, not a production restore or live PostgREST test. Production remains read-only and rollout remains blocked by the owner-controlled complete schema/data/roles backup and successful isolated restore, followed by authenticated two-user PostgREST CRUD/isolation testing.


## Project/task foreign-key recovery guard — 2026-11-19

The branch now contains the forward-only migration `20261119000300_ensure_project_task_foreign_keys.sql`. It checks the exact contracts for `tasks.project_id`, `tasks.parent_task_id`, and `projects.goal_id`. It adds a missing relationship only if no FK uses the source column, validates a sole exact NOT VALID FK, and aborts if any wrong, duplicate, or composite FK is present. It never removes or rewrites constraints automatically.

CI #309 passed on exact code/test head `020877abbbf63719716a9d0c615160a097744716`, including full 19-migration PostgreSQL 17 replay, FK guard idempotence, missing-FK repair, NOT VALID validation, unexpected-FK rejection, Organization/RLS assertions, read-only preflight, checklist reconciliation tests, hierarchy concurrency, 58/58 application tests, typecheck, and production build. Documentation checkpoints CI #310 and #311 also passed.

Read-only live inspection confirms the three existing project/task FKs already match the expected targets and delete actions and are validated. The migration is not applied to production. The live ledger remains at 8 versions; all 9 public tables have RLS enabled and report zero rows. Production still lacks `projects.name`, both checklist tables, Organization validation triggers, and `goals.unit/target`.

Do not apply the branch migration until the owner-controlled complete schema/data/roles backup has been successfully restored in an isolated environment and the authenticated two-user PostgREST acceptance tests are complete. No production DDL or PR merge is authorized by this run.


## Authenticated PostgREST acceptance

The SQL preflight above is read-only and does not prove real JWT/PostgREST behavior. After the owner-controlled complete schema/data/roles backup is restored and verified in an isolated environment, follow [the isolated two-owner PostgREST acceptance runbook](organization-v1-postgrest-acceptance.md). The harness refuses the known production project ref, uses only an anon/publishable key, and never applies migrations. Do not execute it until the restore and checklist-conflict review are complete.
