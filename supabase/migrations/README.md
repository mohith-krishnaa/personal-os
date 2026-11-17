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

The six Organization V1 migrations that follow these versions are local-only and are not present in the live ledger as of the inspection date. They must not be applied until a verified backup exists and the migration sequence has been tested against the live legacy schema.

The duplicate 20260830181600_reminder_notifications.sql file was not present in the live ledger and was removed. Its additional policy/index definitions must not be reintroduced without a reviewed migration.

Use the Supabase CLI migration list --remote command to verify local/remote version alignment after linking the project. Do not run migration repair, migration up, or a remote reset to make the histories appear aligned.


## Organization hierarchy concurrency guard

The local-only `20261015000300_prevent_task_hierarchy_cycles.sql` migration now uses owner-scoped transaction advisory locks to serialize task relationship writes and prevent concurrent transactions from creating an indirect cycle. The lock is transaction-scoped and owner transfers acquire both lock keys in deterministic order. CI #173 validates this function against a disposable PostgreSQL 17 fixture, including a two-session READ COMMITTED race. This migration is still unapplied in the live project; the test does not replace full migration-chain, backup/restore, RLS, or authenticated two-user isolation checks.
