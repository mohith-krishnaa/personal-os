# Organization V1 — Live Preflight and Recovery Runbook

Last verified: 2026-11-17  
Supabase project: gujzvkyytxsnervovvrt (ap-southeast-1, PostgreSQL 17.11.0.003)  
Application rollout: BLOCKED — no recoverable backup has been produced.

This runbook records the live read-only inspection and the safe path to complete Organization V1. It does not authorize production DDL or a PR merge.

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

The six Organization migrations remain local-only and unapplied:

1. 20260905170000_organization_v1.sql
2. 20260905170100_organization_v1_checklists.sql
3. 20261015000100_harden_checklist_ownership.sql
4. 20261015000200_reconcile_checklist_tables.sql
5. 20261015000300_prevent_task_hierarchy_cycles.sql
6. 20261016000100_projects_name_title_compatibility.sql

Do not run migration up or migration repair until the local/remote history has been reviewed using the Supabase CLI and the rollout plan has been approved.

## Backup gate — Free Plan

The Supabase Dashboard confirms that the Free Plan does not include scheduled project backups. No manual backup has been created by this automation.

The supported Supabase CLI db dump command runs pg_dump in a container and excludes Supabase-managed schemas such as auth and storage. It does not include table data or custom roles in the default schema dump; those require separate data-only and role-only exports. See the [Supabase CLI db dump reference](https://supabase.com/docs/reference/cli/supabase-db-dump).

On an owner-controlled Windows machine with Docker Desktop and the Supabase CLI installed, use the current CLI v3 syntax:

    supabase login
    supabase link --project-ref gujzvkyytxsnervovvrt
    supabase db dump --remote --file backups/personal-os-schema.sql
    supabase db dump --remote --data-only --file backups/personal-os-data.sql
    supabase db dump --remote --role-only --file backups/personal-os-roles.sql
    supabase migration list --remote

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
- Performance advisor:
  - 4 unindexed foreign keys: notifications.task_id, projects.goal_id, tasks.parent_task_id, tasks.project_id.
  - 14 auth_rls_initplan warnings.
  - 13 unused-index findings. Do not drop indexes solely because they are currently unused.
  - 4 multiple-permissive-policy findings on goals because goals_owner overlaps the four command-specific policies.

Do not change policies or indexes as part of this preflight. Review each finding against the query workload and migration history after a verified backup.

## Read-only SQL preflight

Run supabase/operations/organization-v1-preflight.sql in the Supabase SQL Editor. It contains SELECT statements only and reports the migration ledger, required table/column presence, RLS flags, policies, triggers, constraints, and indexes. Re-run it immediately before and after any approved rollout.

## Safe rollout sequence

1. Produce and restore-test the manual backup described above.
2. Run supabase migration list --remote and confirm the eight applied versions exactly match the reconstructed repository files. Resolve any discrepancy locally; do not repair the remote ledger by guesswork.
3. Review all six Organization migrations against the live schema snapshot and test them against a disposable database matching that schema.
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
