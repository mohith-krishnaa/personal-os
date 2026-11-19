# Organization V1 — Live Preflight and Recovery Runbook

Last verified: 2026-11-19  
Supabase project: gujzvkyytxsnervovvrt (ap-southeast-1, PostgreSQL 17.11.0.003)  
Application rollout: BLOCKED — no recoverable backup has been produced.

This runbook records the live read-only inspection and the safe path to complete Organization V1. It does not authorize production DDL or a PR merge.

## Verified checkpoint — 2026-11-19

The live project was rechecked read-only: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, 8 applied migrations, and 9 public application tables with RLS enabled. Both checklist tables and the task-organization trigger are still absent; `projects.name`, `goals.unit`, and `goals.target` are also absent. The live migration ledger remains unchanged.

The repository branch contains 18 numbered migrations: the 8 live versions plus 10 local-only migrations (7 Organization, 1 Progress compatibility, 2 RLS performance). [CI #241](https://github.com/mohith-krishnaa/personal-os/actions/runs/44480778181) passed on branch head `d697ff9b3249e7b1795a52ded88829260fae51b4`: full PostgreSQL 17 migration replay/RLS assertions, hierarchy concurrency integration, application tests, typecheck, and production build.

Fresh advisor results: security and health returned no lints. Performance reports 4 unindexed foreign keys, 14 auth_rls_initplan warnings, 13 unused-index findings, and 4 overlapping permissive policies on goals. The branch-only migrations address three Organization/compatibility indexes, remove the four redundant goal policies, and convert ten reminder/notification/progress policy expressions to initplan-safe forms. None has been applied to production. `notifications.task_id` remains a separate unindexed FK outside Organization V1.

PR #11 is open, unmerged, non-draft, and mergeable. PR #12 remains an open superseded draft. The Personal-OS Builder automation is enabled; it continues safe repository work but cannot create an owner-controlled backup or prove live API isolation.

No production DDL, migration, RLS change, data write, restore, or PR merge occurred. The production rollout gate remains a private schema/data/roles backup that has been successfully restored in isolation, followed by authenticated two-user PostgREST verification.

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

The seven Organization migrations remain local-only and unapplied:

1. 20260905170000_organization_v1.sql
2. 20260905170100_organization_v1_checklists.sql
3. 20261015000100_harden_checklist_ownership.sql
4. 20261015000200_reconcile_checklist_tables.sql
5. 20261015000300_prevent_task_hierarchy_cycles.sql
6. 20261016000100_projects_name_title_compatibility.sql
7. 20261117000200_harden_checklist_select_ownership.sql

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
- Performance advisor snapshot (2026-11-18):
  - 4 unindexed foreign keys: notifications.task_id, projects.goal_id, tasks.parent_task_id, tasks.project_id.
  - 14 auth_rls_initplan warnings.
  - 13 unused-index findings. Do not drop indexes solely because they are currently unused.
  - 4 multiple-permissive-policy findings on goals because goals_owner overlaps the four command-specific policies.
- A fresh read-only index probe confirmed that the expected index names `notifications_task_id_idx`, `projects_goal_id_idx`, `tasks_parent_task_id_idx`, and `tasks_project_id_idx` are absent from the live database.
- The pending migration chain already creates the latter three indexes: the two task indexes in `20260905170000_organization_v1.sql`, and the conditional project-goal index in `20261016000100_projects_name_title_compatibility.sql`. The full migration replay assertion now checks that each exists and is valid/ready. They remain absent from production until the migrations are approved and applied.
- `notifications.task_id` has no corresponding pending migration and remains outside Organization V1; track it for reminder/production hardening.

Do not change live policies or indexes as part of this preflight. Review each finding against the query workload and migration history after a verified backup.

## Read-only SQL preflight

Run supabase/operations/organization-v1-preflight.sql in the Supabase SQL Editor. It contains SELECT statements only and reports the migration ledger, required table/column presence, RLS flags, policies, triggers, constraints, and indexes. Re-run it immediately before and after any approved rollout.

## Safe rollout sequence

1. Produce and restore-test the manual backup described above.
2. Run supabase migration list --remote and confirm the eight applied versions exactly match the reconstructed repository files. Resolve any discrepancy locally; do not repair the remote ledger by guesswork.
3. Review all seven Organization migrations against the live schema snapshot and test them against a disposable database matching that schema.
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
