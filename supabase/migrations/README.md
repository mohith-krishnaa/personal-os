> **Verified checkpoint — 2026-11-21 (transactional task activity events).** Branch `feature/organization-v1`; code HEAD `e288c55768bca52e906d51fd6b9580f3ba0cff33`; [CI #408](https://github.com/mohith-krishnaa/personal-os/actions/runs/44802872792) passed on code HEAD; [CI #409](https://github.com/mohith-krishnaa/personal-os/actions/runs/44803558307) passed on final documentation HEAD `7ff05d1c407c5f6e65b409806db55fc7a28fcf4a`. PR #11 remains open/unmerged.
>
> Repository inventory: **23 migrations**. Fresh read-only inspection reconfirmed eight live ledger versions, so 15 are branch-only. The new local-only migration is `20261121000100_durable_task_activity_events.sql`.
>
> The migration installs a SECURITY INVOKER AFTER INSERT/UPDATE trigger on tasks. Task creation, meaningful updates, status changes, and recurrence occurrence inserts write their activity events in the same statement transaction. Failure rolls back the task statement. The trigger retains existing activity_events RLS and grants no SECURITY DEFINER bypass. Read-only preflight query 16 reports its security/privilege contract.
>
> Disposable PostgreSQL tests inject failures for TASK_CREATED, TASK_UPDATED, TASK_COMPLETED, and TASK_RECURRENCE_GENERATED; verify rollback/retry, no-op update behavior, recurrence uniqueness/source metadata, and Owner A/B event isolation. CI #408 passed 23/23 migration replay, task-event tests, migration reapplication, Organization/RLS and concurrency assertions, 133/133 application tests, typecheck, production build, and npm audit with 0 vulnerabilities. CI #411 also passed on documentation checkpoint `014bd50e4a4d4835927daa762cf1cc53c615b545`.
>
> Task-create request idempotency and DELETE events remain incomplete; activity_events is mutable and polymorphic, not an immutable audit log. No historical backfill was added. No production migration, DDL/DML, RLS change, backup, restore, or PR merge occurred. Complete owner-controlled backup, isolated restore, checklist conflict review, and authenticated two-owner PostgREST acceptance remain rollout gates.
>
> **Next task:** stable client-generated request IDs for task/subtask creation, with per-owner uniqueness and retry/concurrency tests. Keep Analytics queued.
---

> **Verified checkpoint — 2026-11-20 (owner backup/restore and checklist reconciliation audit).** Repository: mohith-krishnaa/personal-os; branch: feature/organization-v1; inspected starting HEAD: 0632d89c17c67a66fea01d880f5de2b45748e8c3. CI #392 passed on that exact starting HEAD. PR #11 is open, unmerged, and its head matches the branch; PR #12 remains an open superseded draft. This run changes documentation only; the new documentation commit must receive its own CI result.
>
> Fresh read-only Supabase inspection: project gujzvkyytxsnervovvrt is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 in ap-southeast-1. The live migration ledger contains exactly eight versions (20260829182309, 20260830085036, 20260830103327, 20260830114218, 20260830120132, 20260830123420, 20260830141616, 20260905162251); the branch has 22 migrations, 14 pending relative to that ledger. No production DDL/DML, migration, RLS change, backup, restore, or merge occurred.
>
> Read-only source snapshot: all nine public application tables have zero rows; auth.users=0; storage.buckets=0; storage.objects=0; vault.secrets=0. auth.schema_migrations has 84 platform-managed rows and storage.migrations has 81; these are provider metadata, not application records to copy into a new project. Installed non-plpgsql extensions are pg_stat_statements 1.11, pgcrypto 1.3, supabase_vault 0.3.1, and uuid-ossp 1.1. There are no deployed Edge Functions and no RLS policies in auth/storage.
>
> The restore audit found one custom managed-schema object that the default Supabase CLI dump omits: auth.users.on_auth_user_created invokes public.handle_new_user(). The function is SECURITY INVOKER with search_path=public and inserts public.profiles. Its trigger DDL is in the already-applied baseline migration 20260829182309_create_personal_os_core.sql, so it must be explicitly restored/verified on the isolated copy; a schema diff against that same eight-migration baseline may not emit it. The other 11 non-internal auth/storage triggers are Storage platform triggers owned by supabase_storage_admin and must not be copied manually.
>
> The existing backup instructions were incomplete: they assumed supabase link from the repository despite no supabase/config.toml, did not preserve the supabase_migrations history separately, and did not call out the auth trigger, installed extensions, Vault root-key boundary, or Storage object bytes. The preflight and PostgREST runbooks now specify the exact artifact set, isolated restore sequence, evidence manifest, migration-history check, conflict report review, and harness gate.
>
> No backup was created. The automation container has no repository checkout, Docker, Supabase CLI, pg_dump, or psql; the connected Supabase tools expose read-only inspection but no backup-export action. The last recorded Dashboard check says the Free Plan has no scheduled backups; recheck billing at the time of the owner action. Analytics remains queued.
>
> **Next owner action:** from a private owner-controlled workstation, create roles/schema/data and migration-history exports; capture the custom auth.users trigger and any managed-schema customizations; record SHA-256 hashes and a source manifest; restore to a separate isolated Supabase project; verify extension versions, exact eight-version history, row counts, RLS/catalog contracts, and the auth trigger; then apply only the 14 branch-only migrations to that isolated target, run the checklist conflict report, and execute the two-owner PostgREST harness. Never use production for these tests.

---

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
# Supabase migration history

## Previous verified branch checkpoint — 2026-11-20

- Reminder/notification ownership migration `20261120000200_enforce_reminder_notification_ownership.sql` and authenticated regression commit `8fbf83e18fa15dc60a9a8bc8ab58563738d00df0` passed [CI #375](https://github.com/mohith-krishnaa/personal-os/actions/runs/44719688076). PostgreSQL 17 replayed 21/21 migrations; Owner A/B reminder INSERT/UPDATE, notification UPDATE, BYPASSRLS service-role, migration reapplication, unexpected-FK negative tests, Organization/RLS, archive lifecycle, and hierarchy/project concurrency checks passed; 90/90 application tests, typecheck, and production build passed. npm install reported 0 vulnerabilities. No lint script is configured.

The first code/test attempt `0336eef34d4dfffd7bc498d896aadfbc1af31128` failed CI #374 because Owner A's negative notification UPDATE reused Owner B's reminder that already had a notification; the pre-existing `notifications_reminder_unique` index correctly rejected the duplicate before the new composite FK was evaluated. The test fixture was corrected by adding unused foreign-owner reminder IDs and targeting those IDs, so the regression now isolates the composite owner FK. No production data was involved. Corrected code/test commit `8fbf83e18fa15dc60a9a8bc8ab58563738d00df0` passed CI #375. Documentation checkpoint `4329dc2c88a528d2caaacba88ddd5dafaf34866d` passed CI #376 on the exact documentation HEAD.
- The migration adds unique keys on `tasks(id,user_id)` and `reminders(id,user_id,task_id)`, replaces `reminders.task_id` with an owner-aware composite FK, and replaces `notifications.reminder_id` with an owner/task-aware composite FK. Existing delete cascades remain; RLS policies are unchanged. The migration preflight rejects existing mismatched data and fails closed on unexpected additional foreign keys.
- Authenticated Owner A/B tests prove same-owner reminder creation/reassignment and notification-pair reassignment succeed; cross-owner task/reminder references and mismatched same-owner notification pairs fail without changing prior links. A BYPASSRLS service-role fixture proves valid worker inserts still work and invalid cross-owner writes remain rejected.
- The live policy catalog still checks only `user_id` for reminder INSERT/UPDATE and notification UPDATE, and live FKs remain single-column. Therefore the live schema currently admits cross-owner associations through direct authenticated writes; no production write was attempted. The new composite migration is branch-only.
- Migration count is **21**: 8 versions match the live ledger and 13 are branch-only (10 Organization/related, 1 Progress compatibility, 2 RLS performance). No production schema or data was changed.
- PR #11 remains open and unmerged. Complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation remain rollout gates. No local checkout is attached, so local working-tree status is unverified.
- Next task: audit the service-role reminder delivery worker's notification upsert and retry/claim path against the composite FK contract; verify valid delivery and duplicate idempotency. Keep Analytics queued.



The eight migrations already recorded in the live project were reconstructed from the exact SQL statements stored in supabase_migrations.schema_migrations on 2026-11-17.

The filenames below use the exact live version and name. Do not change their timestamps or rewrite their SQL without a deliberate migration-history decision.

- 20260829182309_create_personal_os_core.sql
- 20260830085036_add_task_recurrence_v1.sql
- 20260830103327_add_recurring_occurrence_idempotency.sql
- 20260830114218_create_reminders.sql
- 20260830120132_reminder_notifications_v1.sql
- 20260830123420_atomize_reminder_delivery_claim.sql
- 20260830141616_progress_goals_v1.sql
- 20260905162251_restrict_rls_auto_enable_execute.sql

The twelve Organization V1/related migrations, one Progress goal-metrics compatibility migration, and two RLS performance migrations are local-only (15 local-only migrations total) and are not present in the last verified live ledger. The branch contains 23 numbered SQL migrations: 8 matching the last verified ledger plus those 15 pending migrations. They must not be applied until a complete owner-controlled backup is restored and the migration sequence has been tested against that isolated legacy-schema copy.

- 20261121000100_durable_task_activity_events.sql — installs transactional task INSERT/UPDATE activity events with a SECURITY INVOKER trigger; includes fault-injection/retry assertions and read-only preflight query 16.

The duplicate 20260830181600_reminder_notifications.sql file was not present in the live ledger and was removed. Its additional policy/index definitions must not be reintroduced without a reviewed migration.

Use `supabase migration list` after linking the project to verify local/remote version alignment. Do not run migration repair, migration up, or a remote reset to make the histories appear aligned.


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

## Organization hierarchy concurrency guard

The local-only `20261015000300_prevent_task_hierarchy_cycles.sql` migration now uses owner-scoped transaction advisory locks to serialize task relationship writes and prevent concurrent transactions from creating an indirect cycle. The lock is transaction-scoped and owner transfers acquire both lock keys in deterministic order. CI #173 validates this function against a disposable PostgreSQL 17 fixture, including a two-session READ COMMITTED race. This migration is still unapplied in the live project; the test does not replace full migration-chain, backup/restore, RLS, or authenticated two-user isolation checks.

The trigger also prevents moving a parent task to a different owner or project when that would leave existing direct children inconsistent. CI #176 verifies these parent-mutation checks alongside the two-session concurrent-cycle test. The migration remains local-only and unapplied in the live project.


## Full migration-chain verification

CI now replays every numbered SQL migration in a disposable PostgreSQL 17 database. The fixture bootstraps the Supabase roles, `auth.users`, `auth.uid()`, and the platform-managed `rls_auto_enable()` function, then replays all 20 migrations: the eight live-ledger migrations, nine Organization migrations, one Progress metrics compatibility repair, and two RLS policy/performance migrations.

The replay seeds legacy `projects.title` and `task_checklist_items` rows before the compatibility/reconciliation migrations. It verifies that canonical reconciliation copies only same-owner task rows, malformed canonical and legacy checklist rows attached to another owner's task are hidden by SELECT RLS, the project title/name dual-write remains available, and authenticated Owner A/Owner B sessions cannot read or mutate one another's Organization records. The assertion script verifies the exact 13-policy Organization matrix across projects, tasks, and both checklist tables, including authenticated roles, command scopes, owner predicates, and task-owner link checks. It also verifies the ten optimized reminder/notification/progress policies preserve their authenticated role, command, owner predicate, and progress-to-goal ownership check; the canonical `goals_owner` policy must remain initplan-safe.

This is a disposable PostgreSQL test, not a production backup restore or a live PostgREST test.

## Progress goal metrics compatibility repair

The live core `goals` table was created before Progress V1 and lacks `unit` and `target`, while the original Progress V1 migration used `CREATE TABLE IF NOT EXISTS` and therefore did not add those columns to the existing table. The forward-only `20261117000100_reconcile_progress_goal_metrics.sql` migration adds nullable columns and validation checks without rewriting the already-applied migration or inventing metrics for legacy goals. New measurable goals continue to require both values in the application; legacy goals remain readable and do not expose progress logging until metrics exist.

The migration is branch-only and has not been applied to Supabase production.


## Two-owner checklist mutation regression

The full migration replay fixture now seeds valid legacy checklist rows for Owner A and Owner B plus one malformed Owner A row attached to Owner B's task. It asserts that both valid rows reconcile and the malformed row does not. Separate authenticated JWT subjects verify reciprocal visibility and that neither owner can UPDATE or DELETE the other's project, task, canonical checklist row, or legacy checklist row. Each cross-owner mutation must affect zero rows.

[CI #207](https://github.com/mohith-krishnaa/personal-os/actions/runs/44055203271) passed the full 15-migration PostgreSQL 17 replay, hierarchy integration, application tests, typecheck, and production build on a9f73bfc26de818679c101974544793a839f2c74. This remains disposable-database verification only; no production migration was applied.


## Checklist SELECT ownership hardening

The local-only 20261117000200_harden_checklist_select_ownership.sql migration replaces SELECT policies on both checklist tables. A visible row must have the authenticated caller as its user_id and reference a task owned by that same caller. This prevents malformed legacy or canonical rows from exposing a foreign task association through PostgREST.

CI #211 replays all 16 migrations in disposable PostgreSQL 17 and verifies that malformed canonical and legacy checklist rows owned by Owner A but attached to Owner B's task are invisible to Owner A. Valid rows remain visible. The migration is not applied to production; backup/restore and live JWT/API verification remain required.

## Goals policy deduplication

The live performance advisor identified four overlapping permissive policies on
`public.goals`: the core `goals_owner` policy already authorizes all commands
for the authenticated owner, while four later command-specific policies repeat
the same ownership rule. The forward-only
`20261119000100_deduplicate_goals_owner_policies.sql` migration removes only
those four redundant policies and retains the canonical `goals_owner` policy.
The migration replay assertion verifies that the canonical policy remains and
the four duplicates are absent. This is branch-only until backup/restore and
production rollout gates are satisfied; no live policy has been changed.

## Reminder and progress RLS initialization-plan optimization

The live advisor also reported 10 initialization-plan warnings across reminder,
notification, and progress ownership policies. The forward-only
`20261119000200_optimize_reminder_progress_rls.sql` migration recreates those
same ten policies with scalar `(select auth.uid())` expressions. It preserves
the existing authenticated role, command scope, owner equality, and the
progress-entry-to-goal ownership check. The migration replay assertion checks
that all ten expected policies exist and no direct per-row `auth.uid()`
expression remains in their USING/WITH CHECK definitions.

This is branch-only until the backup/restore and production rollout gates pass.


## Current migration and CI checkpoint — 2026-11-19

The branch contains 18 numbered migrations: 8 applied in the live ledger and 10 local-only. GitHub Actions [CI #235](https://github.com/mohith-krishnaa/personal-os/actions/runs/44479898572) passed on commit `e89f8355be18d66a7f8b287dceb2a7be154690d9`, including full PostgreSQL 17 migration replay/RLS assertions, hierarchy integration, application tests, typecheck, and production build. The two newest local-only migrations are `20261119000100_deduplicate_goals_owner_policies.sql` and `20261119000200_optimize_reminder_progress_rls.sql`. Neither has been applied to production.

## Notifications task foreign-key index — fresh live evidence

Read-only inspection on 2026-11-19 confirms `notifications_task_id_fkey` is `FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE`. The `notifications` table has only `notifications_pkey`, `notifications_reminder_unique` on `reminder_id`, and `notifications_user_created_at_idx` on `(user_id, created_at DESC)`; there is no index beginning with `task_id`. A dedicated B-tree index on `notifications(task_id)` is justified to support referenced-task delete/cascade checks and task relationship lookups. This is a recommendation only: no production index was created. Add it through a new reviewed migration using `supabase migration new`, include a replay assertion for validity/readiness, and rerun CI before any production rollout.


## Read-only rollout preflight in CI — 2026-11-19

The disposable migration bootstrap creates a minimal `supabase_migrations.schema_migrations(version, name)` fixture. After replay and RLS assertions, `supabase/tests/organization-migrations.sh` runs `supabase/operations/organization-v1-preflight.sql` with `ON_ERROR_STOP=1`. This checks that the same SELECT-only preflight used by operators parses and executes against the resulting PostgreSQL 17 schema. Query 5 includes Organization tables plus goals, reminders, notifications, and progress_entries so the ten reminder/notification/progress policy optimizations and canonical goals policy can be inspected after an approved rollout. This test is disposable-database verification only; it does not connect to or alter production.


The preflight execution change passed [CI #257](https://github.com/mohith-krishnaa/personal-os/actions/runs/44495009597) on test commit `c492e6e89f46e65f695d1bddd7439c9f0d01fd92`; [CI #261](https://github.com/mohith-krishnaa/personal-os/actions/runs/44495199082) passed on the subsequent checkpoint-start PR head `e1c8737cebaef61de88602d938978113b2c5255d`. Both completed migration replay, read-only preflight execution, hierarchy concurrency, application tests, typecheck, and production build successfully.


## Checklist reconciliation ID collisions — 2026-11-19

The forward-only reconciliation migration `20261015000200_reconcile_checklist_tables.sql` intentionally uses `ON CONFLICT (id) DO NOTHING`. This prevents a legacy row from overwriting an existing canonical row, including a row owned by another user. It also means the conflicting legacy row is not copied into the app-facing canonical table; it remains in the retained legacy table. Treat this as a non-destructive conflict, not as a fully reconciled row.

The disposable fixture now seeds a same-ID collision across owners/tasks and asserts that the canonical record's owner, task, title, completion state, and position remain unchanged, while the legacy source record remains intact. Owner-specific visibility assertions ensure neither owner can see the other table's conflicting row.

Run `supabase/operations/checklist-reconciliation-conflicts.sql` only after both checklist tables exist. It is SELECT-only and reports conflicting IDs plus owner/task/payload mismatch flags without exposing titles or modifying rows. The general `organization-v1-preflight.sql` remains safe before migrations; the dedicated conflict report is deliberately separate because the checklist tables do not exist in the live legacy schema yet.

[CI #290](https://github.com/mohith-krishnaa/personal-os/actions/runs/44514046666) passed the full 18-migration PostgreSQL 17 replay, conflict assertions/report execution, hierarchy concurrency, 58 application tests, typecheck, and production build. The live migration ledger still has 8 entries and both checklist tables are absent. No production data or schema was changed.


## Checklist reconciliation compatibility boundary

`20261015000200_reconcile_checklist_tables.sql` is a one-time copy, not ongoing synchronization. The legacy `task_checklist_items` table is retained, but a later legacy write is not automatically copied into canonical `checklist_items`. The read-only `supabase/operations/checklist-reconciliation-conflicts.sql` report detects unresolved legacy rows as `missing_task`, `task_owner_mismatch`, `missing_canonical`, or `canonical_id_collision`.

CI #293 seeds a valid legacy-only write after reconciliation and verifies that the report returns it as `missing_canonical`, while still excluding valid legacy rows successfully copied during migration. This is disposable PostgreSQL verification only. Do not add a synchronization trigger, freeze legacy writes, or repair production rows without the complete backup/isolated-restore gate and an explicit compatibility decision.



## Checklist task foreign-key assertion — 2026-11-19

The full migration replay assertions verify that both `checklist_items.task_id` and `task_checklist_items.task_id` remain NOT NULL and have a validated single-column foreign key to `public.tasks(id)` with `ON DELETE CASCADE`. The conflict report's `missing_task` category is defensive detection for constraint/schema drift, not an expected state under this contract. No migration was added; the migration count remains 18.

The assertion is on code/test commit `7e3d75f46214d078cfc1d4ba7a416584127aa05b`; [CI #296](https://github.com/mohith-krishnaa/personal-os/actions/runs/44542112681) passed the full configured workflow, and [CI #297](https://github.com/mohith-krishnaa/personal-os/actions/runs/44542401798) passed on documentation head `ab6a3381109d50496e1171494f9191f304b03298`.

## Project/task/checklist foreign-key contract assertions — 2026-11-19

The full migration replay verifies five exact relationships: project and parent-task links, the project-to-goal link, and both canonical/legacy checklist `task_id` links to `tasks(id)`. The checklist columns must be NOT NULL and participate in exactly one FK; that FK must be validated, single-column, and use `ON DELETE CASCADE`. The source-column count includes composite FKs, preventing an extra composite constraint from being overlooked.

Read-only preflight query 11 reports the same five contracts, including exact target, validation, delete action, and the count of all FKs containing the source column. A negative CI fixture adds duplicate NOT VALID checklist task FKs inside a disposable transaction and confirms the migration assertion rejects the schema.

[CI #302](https://github.com/mohith-krishnaa/personal-os/actions/runs/44563968200) passed on code head `f0c8a250c617b7bb3342671275582b78a9dab781`: full 18-migration PostgreSQL 17 replay, Organization/RLS assertions, preflight, negative FK test, reconciliation conflict report, hierarchy concurrency, 58/58 application tests, TypeScript typecheck, and production build. No migration was added; the chain remains 18 SQL files. Production checklist tables remain absent, and no production DDL was performed.


## Project/task foreign-key recovery guard — 2026-11-19

The branch-only forward migration `20261119000300_ensure_project_task_foreign_keys.sql` closes a gap in the earlier conditional FK creation checks. It verifies the exact source/target columns and delete action for:

- `tasks.project_id -> projects.id ON DELETE SET NULL`
- `tasks.parent_task_id -> tasks.id ON DELETE CASCADE`
- `projects.goal_id -> goals.id ON DELETE SET NULL`

If no FK uses the source column, the migration creates the expected relationship. If exactly one expected relationship exists but is NOT VALID, it validates it. If a wrong, duplicate, or composite FK uses the source column, it raises and leaves every existing constraint untouched for explicit review. It never drops or rewrites an unexpected constraint.

CI #309 passed on exact branch head `020877abbbf63719716a9d0c615160a097744716`. The disposable PostgreSQL 17 test replay verified the migration can be reapplied, repairs a missing FK inside a rollback-only transaction, validates an exact NOT VALID FK inside a rollback-only transaction, and rejects an unexpected additional FK. Full 19-migration replay, Organization/RLS assertions, read-only preflight, checklist conflict tests, hierarchy concurrency, 58/58 application tests, typecheck, and production build all passed.

The live Supabase ledger remains at 8 versions. Read-only inspection confirms the three existing live project/task FKs already match these contracts. This migration remains unapplied in production; no production DDL was performed. Production rollout remains blocked on a complete owner-controlled schema/data/roles backup successfully restored in isolation and authenticated two-user PostgREST verification.


## Progress goal-metric compatibility regression — 2026-11-20

The disposable migration replay now runs `supabase/tests/progress-goal-compatibility.sql` after the full chain. It verifies that `goals.unit` remains nullable text and `goals.target` remains nullable numeric for legacy non-measurable goals; both named check constraints must exist and be validated. Positive measurable values are accepted, whitespace-only units are rejected, and zero/negative targets are rejected. The test is wrapped in a transaction and rolls back. CI #321 passed this test as part of the full replay. This does not establish that the migration has been applied to production; the live ledger remains at eight versions and the columns are absent.


## Project archive lifecycle migration — 2026-11-20

`20261120000100_enforce_active_project_task_links.sql` depends on the Organization task-link validation trigger from `20261015000300_prevent_task_hierarchy_cycles.sql`. It fails closed if that trigger or required columns are absent. The migration is forward-only and idempotent: it creates/replaces the SECURITY INVOKER function, replaces one named trigger, and does not rewrite task rows or project statuses.

The new trigger rejects task INSERTs and actual owner/project reassignment into COMPLETED or ARCHIVED projects. Unchanged existing links remain valid, so archiving a project does not detach tasks. A row-level `FOR SHARE` lock serializes new assignments with concurrent project status updates. CI replays and reapplies this migration, then runs the rollback-only project archive lifecycle assertions. A separate two-session race test remains the next verification task.


## Atomic reminder delivery — 2026-11-20

Local-only migration `20261120000300_atomic_reminder_delivery.sql` replaces the existing `claim_due_reminders(integer)` body without changing its signature. The function inserts or validates/reuses the unique reminder notification, inserts the activity event, then commits the delivered marker in the same transaction. It retains `FOR UPDATE SKIP LOCKED`, preserves an existing notification's read state, and raises on an existing notification whose owner/task does not match. SECURITY DEFINER uses `search_path = pg_catalog, public`; only service_role can execute it.

The delivery route now calls the RPC once after its existing bearer-secret check. CI #378 passed the full **22/22** PostgreSQL 17 replay, reapplication of the new migration, fault-injected rollback/retry tests for notification and activity-event failures, existing-notification reuse, duplicate-call idempotency, two-session SKIP LOCKED concurrency, **90/90** application tests, typecheck, and production build. This migration remains branch-only and must not be applied to production before the complete owner-controlled backup and isolated restore gates are satisfied.
