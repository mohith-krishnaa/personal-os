# Organization V1 — migration dependency and baseline audit

**Audit date:** 2026-11-20  
**Repository:** `mohith-krishnaa/personal-os`  
**Branch:** `feature/organization-v1`  
**Starting HEAD:** `5569c23a8ea61d002af782653429c726e0e1d5b5`  
**Code/test HEAD:** `b91e63bddb1decace36be78b3849dce02133fb9b`  
**Verification:** [CI #396](https://github.com/mohith-krishnaa/personal-os/actions/runs/44762846651)

## Scope and method

Compared the branch's complete `supabase/migrations/*.sql` tree with the live Supabase migration ledger, then inspected the live PostgreSQL catalog for the baseline columns, foreign keys, indexes, RLS policies, triggers, function ACL, and extensions that the branch-only migrations depend on.

This is a static/catalog audit plus disposable PostgreSQL CI replay. It is **not** a restored-copy test and does not authorize production migration.

## Migration ledger reconciliation

The live project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 in `ap-southeast-1`.

The eight live ledger versions match the first eight branch migration filenames:

| Version | Name |
|---|---|
| `20260829182309` | `create_personal_os_core` |
| `20260830085036` | `add_task_recurrence_v1` |
| `20260830103327` | `add_recurring_occurrence_idempotency` |
| `20260830114218` | `create_reminders` |
| `20260830120132` | `reminder_notifications_v1` |
| `20260830123420` | `atomize_reminder_delivery_claim` |
| `20260830141616` | `progress_goals_v1` |
| `20260905162251` | `restrict_rls_auto_enable_execute` |

The branch contains 22 numbered SQL migrations: **8 live versions + 14 branch-only versions**.

## Live baseline catalog observed

- All nine public application tables have RLS enabled and currently report zero rows.
- `projects.title` and `projects.status` exist; `projects.name` does not.
- `goals.unit` and `goals.target` do not exist.
- `checklist_items` and `task_checklist_items` do not exist.
- `tasks.project_id` and `tasks.parent_task_id` exist.
- The baseline project/task/goal/reminder/notification foreign keys exist and are validated.
- The six inspected baseline FKs use MATCH SIMPLE, are NOT DEFERRABLE, and use ON UPDATE NO ACTION. Their ON DELETE actions are:
  - `tasks.project_id → projects.id`: SET NULL
  - `tasks.parent_task_id → tasks.id`: CASCADE
  - `projects.goal_id → goals.id`: SET NULL
  - `reminders.task_id → tasks.id`: CASCADE
  - `notifications.reminder_id → reminders.id`: CASCADE
  - `notifications.task_id → tasks.id`: CASCADE
- `notifications_reminder_unique` is a valid unique index on `notifications(reminder_id)`.
- `auth.users.on_auth_user_created` exists and invokes `handle_new_user()`.
- `rls_auto_enable()` is SECURITY DEFINER with `search_path=pg_catalog`; effective EXECUTE is denied to PUBLIC, anon, and authenticated and granted to service_role.
- Installed extensions observed: pg_stat_statements 1.11, pgcrypto 1.3, supabase_vault 0.3.1, and uuid-ossp 1.1.

The managed Auth trigger and Vault/extension details remain part of the backup/restore gate. They are not recreated by the Organization migrations.

## Branch-only migration dependency matrix

| Migration | Required earlier contract | Effect and ordering assessment |
|---|---|---|
| `20260905170000_organization_v1.sql` | Core `projects`, `tasks`, `goals`; task owner columns and existing project/parent columns | Adds owner-scoped project/checklist behavior and the initial task-link validation trigger. Correctly follows the core schema. |
| `20260905170100_organization_v1_checklists.sql` | Core `tasks` and Auth users | Creates the transitional legacy checklist table and owner-scoped RLS. Follows the canonical checklist creation. |
| `20261015000100_harden_checklist_ownership.sql` | Canonical `checklist_items` and `tasks` | Tightens canonical checklist INSERT/UPDATE task-owner checks. |
| `20261015000200_reconcile_checklist_tables.sql` | Canonical and legacy checklist tables plus `tasks` | Copies only same-owner legacy rows; `ON CONFLICT (id) DO NOTHING` preserves existing canonical IDs. The runner seeds legacy rows after table creation and before this migration. |
| `20261015000300_prevent_task_hierarchy_cycles.sql` | Initial `validate_task_organization_links` trigger and task parent/project columns | Replaces the trigger function with ancestor-cycle detection and owner-scoped advisory serialization. |
| `20261016000100_projects_name_title_compatibility.sql` | Baseline `projects.title/status` | Adds/backfills `name`, validates it, and installs title/name dual-write compatibility. This is required because the live baseline has title but no name. |
| `20261117000100_reconcile_progress_goal_metrics.sql` | Baseline `goals` table from Progress V1 | Adds nullable `unit/target` and guarded checks; legacy non-metric goals remain valid. |
| `20261117000200_harden_checklist_select_ownership.sql` | Both checklist tables and `tasks` | Requires both checklist-row ownership and task ownership for SELECT visibility. |
| `20261119000100_deduplicate_goals_owner_policies.sql` | Core `goals_owner` plus the four legacy command-specific goals policies | Removes redundant permissive policies while retaining the core owner policy. |
| `20261119000200_optimize_reminder_progress_rls.sql` | Baseline reminders, notifications, progress_entries and their named policies | Recreates the existing owner/relationship predicates with initplan-safe `(select auth.uid())` expressions. |
| `20261119000300_ensure_project_task_foreign_keys.sql` | `tasks.project_id`, `tasks.parent_task_id`, `projects.goal_id`, referenced tables | Repairs missing exact FKs, validates exact NOT VALID FKs, and fails closed on unexpected source-column FKs. It now also requires ON UPDATE NO ACTION. |
| `20261120000100_enforce_active_project_task_links.sql` | Initial/cycle-safe task-link validation trigger plus `projects.status` | Adds the ACTIVE-only new-link guard while preserving unchanged historical links after completion/archive. |
| `20261120000200_enforce_reminder_notification_ownership.sql` | Baseline tasks/reminders/notifications, single-column FK names, and existing owner/task columns | Adds composite owner-aware keys and replaces reminder/task and notification/reminder links. Legacy FK recognition now requires ON UPDATE NO ACTION. |
| `20261120000300_atomic_reminder_delivery.sql` | Reminders, notifications, activity_events, `notifications_reminder_unique`, `service_role`, existing claim function signature | Replaces the claim RPC with atomic notification/event/delivered-marker writes and service_role-only execution. |

All required branch-only prerequisites appear earlier in timestamp order. No missing dependency or ordering inversion was found in the reviewed sequence.

## Fail-closed foreign-key contract finding

The live baseline FKs all use ON UPDATE NO ACTION. Before this audit, two branch guards checked the referenced table/columns and ON DELETE action but did not include ON UPDATE action when deciding whether an existing legacy FK was exact:

- `20261119000300_ensure_project_task_foreign_keys.sql`
- `20261120000200_enforce_reminder_notification_ownership.sql`

A noncanonical `ON UPDATE CASCADE` FK could therefore be accepted as the expected old relationship. In the reminder migration, that old FK could then be replaced by a new composite FK whose default update action is NO ACTION, silently changing an unexpected pre-existing contract.

The branch guards now require ON UPDATE NO ACTION when recognizing the baseline relationship. Read-only preflight query 11 reports the expected update action as well. The migration count did not change.

The migration runner now includes rollback-only negative cases that replace the expected project/task, reminder/task, and notification/reminder FKs with NOT VALID ON UPDATE CASCADE variants. Each migration must reject the variant with its expected contract error; the transaction is rolled back.

This was a **branch migration guard weakness**, not a detected production schema mismatch: the freshly inspected live baseline already uses ON UPDATE NO ACTION.

## CI evidence

[CI #396](https://github.com/mohith-krishnaa/personal-os/actions/runs/44762846651) passed on code/test HEAD `b91e63bddb1decace36be78b3849dce02133fb9b`.

- Isolated PostgREST safety preflight: 17/17 passed.
- PostgreSQL 17 migration replay: 22/22 passed.
- Organization/RLS assertions and project archive lifecycle: passed.
- Task hierarchy and two-session concurrency checks: passed.
- New noncanonical ON UPDATE rejection cases: passed as part of the migration replay step.
- Application tests: 119/119 passed.
- TypeScript typecheck: passed.
- Production build: passed.
- npm install audited 43 packages and reported 0 vulnerabilities.
- No lint script/workflow step is configured.

Expected SQL errors from the negative fixtures appear in the PostgreSQL logs; the runner matched the intended error messages and the workflow step succeeded.

## Rollout boundary and remaining acceptance

No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred during this audit.

Still required before any production schema rollout:

1. Owner-controlled complete backup of schema, data, and roles.
2. Successful restore into a separate isolated Supabase project.
3. Verification of migration history, extensions, roles, RLS, the custom Auth profile trigger, and other reviewed customizations.
4. Checklist reconciliation conflict report review against the restored copy.
5. Authenticated two-owner PostgREST CRUD and cross-owner isolation run against the isolated copy.

The static audit and disposable CI replay do not replace these requirements.

**Next action:** complete the owner-controlled backup/restore gate, then apply the 14 branch-only migrations only to the isolated target and run the checklist report and two-owner PostgREST harness. If that owner action remains unavailable, continue with a static audit of runtime task/project create and update callers against the active-project and ownership triggers; do not retry production operations.
