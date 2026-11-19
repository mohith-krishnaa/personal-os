# Organization V1 — Live Preflight and Recovery Runbook

Last verified: 2026-11-19  
Supabase project: gujzvkyytxsnervovvrt (ap-southeast-1, PostgreSQL 17.11.0.003)  
Application rollout: BLOCKED — no recoverable backup has been produced.

This runbook records the live read-only inspection and the safe path to complete Organization V1. It does not authorize production DDL or a PR merge.

## Latest verified checkpoint — 2026-11-19

Immediately before this documentation-only refresh, remote branch `feature/organization-v1` was at `1d0ad43319e3a85f6280632e1d663c8d0c4e3b16`, which passed CI #319. PR #11 is open and unmerged; verify its post-refresh head in GitHub. The branch was 354 commits ahead of `main`, 0 behind. It contains 19 migrations: 8 exact live-ledger versions and 11 branch-only migrations (8 Organization, 1 Progress compatibility, 2 RLS performance).

[CI #309](https://github.com/mohith-krishnaa/personal-os/actions/runs/44576380568) passed on the code/test commit, including the full 19-migration PostgreSQL 17 replay, Organization/RLS assertions, FK recovery/idempotence/fail-closed cases, checklist reconciliation tests, hierarchy concurrency, 58/58 application tests, typecheck, and production build. [CI #319](https://github.com/mohith-krishnaa/personal-os/actions/runs/44587907725) passed on the exact pre-refresh branch HEAD; every configured workflow step completed successfully. The current documentation commit requires its own CI result.

Fresh read-only production checks: ACTIVE_HEALTHY on PostgreSQL 17.11.0.003; exactly 8 applied migrations; 9 public tables, all with RLS enabled and all reporting zero rows. `projects.name`, both checklist tables, Organization user-defined triggers, `goals.unit`, and `goals.target` are absent. The existing project/task FKs have the expected definitions and are validated.

No complete owner-controlled schema/data/roles backup or successful isolated restore exists. No authenticated two-user PostgREST CRUD/isolation test has been completed. No production migration, DDL/DML, RLS change, backup/restore, or PR merge was performed. Production rollout remains blocked.

The Personal-OS Builder automation is enabled. Its recorded last run `2137c85a-2500-832c-b819-9896e93be753` remains recorded as in progress without a completion timestamp; latest stored result `603cd95a-511c-8321-9ad7-6459f2953f51` predates that run. This status does not prove worker liveness.

**Next repository task:** continue read-only static review of the 19-migration sequence and preflight against the verified 8-migration legacy schema. The owner must supply a complete private schema/data/roles backup and successful isolated-restore evidence before any production rollout.

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

The eight Organization migrations remain local-only and unapplied:

1. 20260905170000_organization_v1.sql
2. 20260905170100_organization_v1_checklists.sql
3. 20261015000100_harden_checklist_ownership.sql
4. 20261015000200_reconcile_checklist_tables.sql
5. 20261015000300_prevent_task_hierarchy_cycles.sql
6. 20261016000100_projects_name_title_compatibility.sql
7. 20261117000200_harden_checklist_select_ownership.sql
8. 20261119000300_ensure_project_task_foreign_keys.sql

The other three local-only migrations are:

- `20261117000100_reconcile_progress_goal_metrics.sql` — Progress compatibility.
- `20261119000100_deduplicate_goals_owner_policies.sql` — remove four redundant goals policies.
- `20261119000200_optimize_reminder_progress_rls.sql` — optimize ten reminder, notification, and progress policy expressions.

Do not run migration up or migration repair until the local/remote history has been reviewed using the Supabase CLI and the rollout plan has been approved.

## Backup gate — Free Plan

The Supabase Dashboard confirms that the Free Plan does not include scheduled project backups. No manual backup has been created by this automation.

The supported Supabase CLI db dump command runs pg_dump in a container and excludes Supabase-managed schemas such as auth and storage. It does not include table data or custom roles in the default schema dump; those require separate data-only and role-only exports. See the [Supabase CLI db dump reference](https://supabase.com/docs/reference/cli/supabase-db-dump).

On an owner-controlled Windows machine with Docker Desktop and the Supabase CLI installed, authenticate and link the project. Then export roles, schema, and data separately using the linked target explicitly:

    supabase login
    supabase link --project-ref gujzvkyytxsnervovvrt
    supabase db dump --linked -f backups/personal-os-roles.sql --role-only
    supabase db dump --linked -f backups/personal-os-schema.sql
    supabase db dump --linked -f backups/personal-os-data.sql --use-copy --data-only
    supabase migration list

The official CLI reference documents `db dump` as operating on the linked project by default; `--linked` makes the target explicit. The `--role-only` and `--data-only` exports are required because the default dump contains neither custom roles nor table data. `--use-copy` is included for the data export as recommended by Supabase's platform restore guide.

Keep these backup files outside the public repository and protect them as private database artifacts. Do not put database passwords, connection strings, access tokens, or service-role keys in Git or ChatGPT.

The current exact counts for auth.users and storage.objects are both zero. Recheck before backup. If either becomes non-empty, arrange a separate provider-supported export/restore path for that managed data; the CLI dump does not include those schemas.

A dump is not accepted as a recovery gate until:
1. All expected files exist and are non-empty.
2. Their hashes are recorded in a private location.
3. The schema/data/role exports are inspected for expected application objects.
4. A restore is tested against an isolated local database or disposable Supabase project.
5. The restore is verified before production DDL.

The current automation environment has no Docker daemon, pg_dump binary, or database password, so it cannot create or restore this backup itself.

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

Run supabase/operations/organization-v1-preflight.sql in the Supabase SQL Editor. It contains SELECT statements only and reports the migration ledger, required table/column presence, RLS flags, policies, triggers, constraints, and indexes. Query 5 includes Organization, goals, reminders, notifications, and progress_entries so the pending reminder/progress policy optimizations can be reviewed after rollout. The exact preflight file is also executed at the end of the disposable migration replay in CI; the test bootstrap creates only a minimal migration-ledger fixture so the preflight syntax and catalog queries are exercised without connecting to production. Re-run it immediately before and after any approved rollout.

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
