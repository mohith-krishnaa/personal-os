# Supabase migration history

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

The seven Organization V1 migrations, one Progress goal-metrics compatibility migration, and two RLS performance migrations are local-only (10 local-only migrations total) and are not present in the live ledger. The branch contains 18 numbered SQL migrations: 8 matching the live ledger plus those 10 pending migrations. They must not be applied until a verified backup exists and the migration sequence has been tested against the live legacy schema.

The duplicate 20260830181600_reminder_notifications.sql file was not present in the live ledger and was removed. Its additional policy/index definitions must not be reintroduced without a reviewed migration.

Use the Supabase CLI migration list --remote command to verify local/remote version alignment after linking the project. Do not run migration repair, migration up, or a remote reset to make the histories appear aligned.


## Organization hierarchy concurrency guard

The local-only `20261015000300_prevent_task_hierarchy_cycles.sql` migration now uses owner-scoped transaction advisory locks to serialize task relationship writes and prevent concurrent transactions from creating an indirect cycle. The lock is transaction-scoped and owner transfers acquire both lock keys in deterministic order. CI #173 validates this function against a disposable PostgreSQL 17 fixture, including a two-session READ COMMITTED race. This migration is still unapplied in the live project; the test does not replace full migration-chain, backup/restore, RLS, or authenticated two-user isolation checks.

The trigger also prevents moving a parent task to a different owner or project when that would leave existing direct children inconsistent. CI #176 verifies these parent-mutation checks alongside the two-session concurrent-cycle test. The migration remains local-only and unapplied in the live project.


## Full migration-chain verification

CI now replays every numbered SQL migration in a disposable PostgreSQL 17 database. The fixture bootstraps the Supabase roles, `auth.users`, `auth.uid()`, and the platform-managed `rls_auto_enable()` function, then replays the eight live migrations followed by the seven Organization migrations and the Progress metrics compatibility repair.

The replay seeds legacy `projects.title` and `task_checklist_items` rows before the compatibility/reconciliation migrations. It verifies that canonical reconciliation copies only same-owner task rows, malformed canonical and legacy checklist rows attached to another owner's task are hidden by SELECT RLS, the project title/name dual-write remains available, and authenticated Owner A/Owner B sessions cannot read or mutate one another's Organization records. This is a disposable PostgreSQL test, not a production backup restore or a live PostgREST test.

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
