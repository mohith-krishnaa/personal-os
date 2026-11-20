#!/usr/bin/env bash
set -euo pipefail

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export PGDATABASE="${PGDATABASE:-personal_os_migration_test}"

psql -X -v ON_ERROR_STOP=1 -c 'select 1' >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/organization-migration-bootstrap.sql

expected_migrations=24
actual_migrations="$(find supabase/migrations -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')"

if [[ "$actual_migrations" -ne "$expected_migrations" ]]; then
  echo "Expected $expected_migrations migration files, found $actual_migrations."
  exit 1
fi

applied_migrations=0
for migration in supabase/migrations/*.sql; do
  migration_name="$(basename "$migration")"
  echo "Replaying $migration_name"
  psql -X -v ON_ERROR_STOP=1 -f "$migration"
  applied_migrations=$((applied_migrations + 1))

  if [[ "$migration_name" == "20260905170100_organization_v1_checklists.sql" ]]; then
    echo "Seeding legacy projects and checklist rows before reconciliation"
    psql -X -v ON_ERROR_STOP=1 -f supabase/tests/organization-migration-seed-legacy-checklist.sql
  fi
done

if [[ "$applied_migrations" -ne "$expected_migrations" ]]; then
  echo "Applied $applied_migrations migrations; expected $expected_migrations."
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 -f supabase/tests/organization-migration-assertions.sql
echo "Verifying transactional task activity events"
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/task-activity-events.sql
echo "Verifying per-owner task creation request idempotency"
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/task-create-idempotency.sql
bash supabase/tests/task-create-idempotency-concurrency.sh
echo "Reapplying task create request idempotency migration to verify idempotence"
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261121000200_task_create_request_idempotency.sql
echo "Reapplying durable task activity event migration to verify idempotence"
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261121000100_durable_task_activity_events.sql
echo "Reapplying atomic reminder delivery migration to verify idempotence"
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261120000300_atomic_reminder_delivery.sql
echo "Reapplying the reminder/notification ownership migration to verify idempotence"
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261120000200_enforce_reminder_notification_ownership.sql

echo "Verifying the reminder ownership migration fails closed on unexpected foreign keys"
set +e
unexpected_reminder_fk_output="$(
  psql -X -v ON_ERROR_STOP=1 2>&1 <<'SQL'
BEGIN;
ALTER TABLE public.reminders
  ADD CONSTRAINT test_unexpected_reminders_task_fk
  FOREIGN KEY (task_id) REFERENCES auth.users(id)
  ON DELETE CASCADE NOT VALID;
\i supabase/migrations/20261120000200_enforce_reminder_notification_ownership.sql
ROLLBACK;
SQL
)"
unexpected_reminder_fk_status=$?
set -e

if [[ "$unexpected_reminder_fk_status" -eq 0 ]] || ! grep -Fq 'Unexpected foreign-key contract for public.reminders.task_id' <<<"$unexpected_reminder_fk_output"; then
  echo "Reminder ownership migration did not fail closed on an unexpected task_id foreign key:"
  printf '%s\n' "$unexpected_reminder_fk_output"
  exit 1
fi

echo "Verifying the notification ownership migration fails closed on unexpected foreign keys"
set +e
unexpected_notification_fk_output="$(
  psql -X -v ON_ERROR_STOP=1 2>&1 <<'SQL'
BEGIN;
ALTER TABLE public.notifications
  ADD CONSTRAINT test_unexpected_notifications_reminder_fk
  FOREIGN KEY (reminder_id) REFERENCES auth.users(id)
  ON DELETE CASCADE NOT VALID;
\i supabase/migrations/20261120000200_enforce_reminder_notification_ownership.sql
ROLLBACK;
SQL
)"
unexpected_notification_fk_status=$?
set -e

if [[ "$unexpected_notification_fk_status" -eq 0 ]] || ! grep -Fq 'Unexpected foreign-key contract for public.notifications.reminder_id' <<<"$unexpected_notification_fk_output"; then
  echo "Notification ownership migration did not fail closed on an unexpected reminder_id foreign key:"
  printf '%s\n' "$unexpected_notification_fk_output"
  exit 1
fi

echo "Verifying the reminder ownership migration rejects a noncanonical ON UPDATE action"
set +e
unexpected_reminder_update_output="$(
  psql -X -v ON_ERROR_STOP=1 2>&1 <<'SQL'
BEGIN;
ALTER TABLE public.reminders DROP CONSTRAINT reminders_task_owner_fkey;
ALTER TABLE public.reminders
  ADD CONSTRAINT reminders_task_id_fkey
  FOREIGN KEY (task_id) REFERENCES public.tasks(id)
  ON DELETE CASCADE ON UPDATE CASCADE NOT VALID;
\i supabase/migrations/20261120000200_enforce_reminder_notification_ownership.sql
ROLLBACK;
SQL
)"
unexpected_reminder_update_status=$?
set -e

if [[ "$unexpected_reminder_update_status" -eq 0 ]] || ! grep -Fq 'Unexpected foreign-key contract for public.reminders.task_id' <<<"$unexpected_reminder_update_output"; then
  echo "The reminder ownership migration accepted a noncanonical ON UPDATE action or failed for an unexpected reason:"
  printf '%s\n' "$unexpected_reminder_update_output"
  exit 1
fi

echo "Noncanonical reminder/task ON UPDATE behavior was rejected as expected."

echo "Verifying the notification ownership migration rejects a noncanonical ON UPDATE action"
set +e
unexpected_notification_update_output="$(
  psql -X -v ON_ERROR_STOP=1 2>&1 <<'SQL'
BEGIN;
ALTER TABLE public.notifications DROP CONSTRAINT notifications_reminder_owner_task_fkey;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_reminder_id_fkey
  FOREIGN KEY (reminder_id) REFERENCES public.reminders(id)
  ON DELETE CASCADE ON UPDATE CASCADE NOT VALID;
\i supabase/migrations/20261120000200_enforce_reminder_notification_ownership.sql
ROLLBACK;
SQL
)"
unexpected_notification_update_status=$?
set -e

if [[ "$unexpected_notification_update_status" -eq 0 ]] || ! grep -Fq 'Unexpected foreign-key contract for public.notifications.reminder_id' <<<"$unexpected_notification_update_output"; then
  echo "The notification ownership migration accepted a noncanonical ON UPDATE action or failed for an unexpected reason:"
  printf '%s\n' "$unexpected_notification_update_output"
  exit 1
fi

echo "Noncanonical notification/reminder ON UPDATE behavior was rejected as expected."

echo "Reapplying the active-project task-link migration to verify idempotence"
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261120000100_enforce_active_project_task_links.sql
echo "Verifying project archive lifecycle and active-project task assignment"
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/project-archive-lifecycle.sql
echo "Verifying Progress goal-metric compatibility"
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/progress-goal-compatibility.sql

echo "Reapplying the project/task FK guard to verify idempotence"
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261119000300_ensure_project_task_foreign_keys.sql

echo "Verifying that a missing expected FK is repaired inside a rollback-only transaction"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
ALTER TABLE public.tasks DROP CONSTRAINT tasks_project_id_fkey;
\i supabase/migrations/20261119000300_ensure_project_task_foreign_keys.sql
DO $assert_repaired_fk$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint con
    WHERE con.conrelid = 'public.tasks'::regclass
      AND con.contype = 'f'
      AND con.confrelid = 'public.projects'::regclass
      AND con.conkey = ARRAY[
        (SELECT attnum FROM pg_attribute
         WHERE attrelid = 'public.tasks'::regclass
           AND attname = 'project_id' AND NOT attisdropped)
      ]::smallint[]
      AND con.confkey = ARRAY[
        (SELECT attnum FROM pg_attribute
         WHERE attrelid = 'public.projects'::regclass
           AND attname = 'id' AND NOT attisdropped)
      ]::smallint[]
      AND con.confdeltype = 'n'
      AND con.convalidated
  ) THEN
    RAISE EXCEPTION 'The missing tasks.project_id foreign key was not restored.';
  END IF;
END
$assert_repaired_fk$;
ROLLBACK;
SQL

echo "Verifying that an exact NOT VALID FK is validated inside a rollback-only transaction"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
ALTER TABLE public.tasks DROP CONSTRAINT tasks_project_id_fkey;
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_project_id_fkey
  FOREIGN KEY (project_id) REFERENCES public.projects(id)
  ON DELETE SET NULL NOT VALID;
\i supabase/migrations/20261119000300_ensure_project_task_foreign_keys.sql
DO $assert_validated_fk$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint con
    WHERE con.conrelid = 'public.tasks'::regclass
      AND con.conname = 'tasks_project_id_fkey'
      AND con.contype = 'f'
      AND con.convalidated
  ) THEN
    RAISE EXCEPTION 'The existing NOT VALID tasks.project_id foreign key was not validated.';
  END IF;
END
$assert_validated_fk$;
ROLLBACK;
SQL

echo "Verifying that an unexpected additional FK fails closed without being removed"
set +e
unexpected_fk_output="$(
  psql -X -v ON_ERROR_STOP=1 2>&1 <<'SQL'
BEGIN;
ALTER TABLE public.tasks
  ADD CONSTRAINT test_unexpected_tasks_project_fk
  FOREIGN KEY (project_id) REFERENCES auth.users(id)
  ON DELETE SET NULL NOT VALID;
\i supabase/migrations/20261119000300_ensure_project_task_foreign_keys.sql
ROLLBACK;
SQL
)"
unexpected_fk_status=$?
set -e

if [[ "$unexpected_fk_status" -eq 0 ]]; then
  echo "The project/task FK guard accepted an unexpected additional foreign key."
  exit 1
fi

if ! grep -Fq 'Unexpected foreign-key contract for public.tasks.project_id' <<<"$unexpected_fk_output"; then
  echo "The project/task FK guard failed for an unexpected reason:"
  printf '%s\n' "$unexpected_fk_output"
  exit 1
fi

echo "Unexpected additional project/task foreign keys were rejected as expected."

echo "Verifying the project/task FK guard rejects noncanonical ON UPDATE behavior"
set +e
unexpected_update_fk_output="$(
  psql -X -v ON_ERROR_STOP=1 2>&1 <<'SQL'
BEGIN;
ALTER TABLE public.tasks DROP CONSTRAINT tasks_project_id_fkey;
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_project_id_fkey
  FOREIGN KEY (project_id) REFERENCES public.projects(id)
  ON DELETE SET NULL ON UPDATE CASCADE NOT VALID;
\i supabase/migrations/20261119000300_ensure_project_task_foreign_keys.sql
ROLLBACK;
SQL
)"
unexpected_update_fk_status=$?
set -e

if [[ "$unexpected_update_fk_status" -eq 0 ]] || ! grep -Fq 'Unexpected foreign-key contract for public.tasks.project_id' <<<"$unexpected_update_fk_output"; then
  echo "The project/task FK guard accepted a noncanonical ON UPDATE action or failed for an unexpected reason:"
  printf '%s\n' "$unexpected_update_fk_output"
  exit 1
fi

echo "Noncanonical project/task ON UPDATE behavior was rejected as expected."

echo "Executing read-only Organization rollout preflight against the replayed schema"
psql -X -v ON_ERROR_STOP=1 -f supabase/operations/organization-v1-preflight.sql >/dev/null

echo "Verifying checklist FK assertions reject duplicate task_id foreign keys"
set +e
negative_fk_output="$(
  psql -X -v ON_ERROR_STOP=1 2>&1 <<'SQL'
BEGIN;
ALTER TABLE public.checklist_items
  ADD CONSTRAINT test_duplicate_checklist_items_task_fk
  FOREIGN KEY (task_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;
ALTER TABLE public.task_checklist_items
  ADD CONSTRAINT test_duplicate_task_checklist_items_task_fk
  FOREIGN KEY (task_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;
\i supabase/tests/organization-migration-assertions.sql
ROLLBACK;
SQL
)"
negative_fk_status=$?
set -e

if [[ "$negative_fk_status" -eq 0 ]]; then
  echo "Checklist FK assertions accepted duplicate task_id foreign keys."
  exit 1
fi

if ! grep -Fq 'Each checklist task_id must be NOT NULL and participate in exactly one validated single-column foreign key to public.tasks(id) ON DELETE CASCADE.' <<<"$negative_fk_output"; then
  echo "Checklist FK negative test failed for an unexpected reason:"
  printf '%s\n' "$negative_fk_output"
  exit 1
fi

echo "Duplicate checklist task_id foreign keys were rejected as expected."

echo "Seeding a valid legacy-only write after one-time reconciliation"
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/organization-migration-seed-post-reconciliation.sql

echo "Executing read-only checklist reconciliation conflict report"
conflict_report="$(psql -X -v ON_ERROR_STOP=1 -A -t -f supabase/operations/checklist-reconciliation-conflicts.sql)"
printf '%s\n' "$conflict_report"

if ! grep -Fq '30000000-0000-4000-8000-000000000002|task_owner_mismatch|' <<<"$conflict_report"; then
  echo "Checklist conflict report did not identify the legacy row linked to another owner's task."
  exit 1
fi

if ! grep -Fq '30000000-0000-4000-8000-000000000005|canonical_id_collision|' <<<"$conflict_report"; then
  echo "Checklist conflict report did not identify the non-identical canonical ID collision."
  exit 1
fi

if ! grep -Fq '30000000-0000-4000-8000-000000000006|missing_canonical|' <<<"$conflict_report"; then
  echo "Checklist conflict report did not identify a valid legacy-only write after reconciliation."
  exit 1
fi

reported_conflicts="$(printf '%s\n' "$conflict_report" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
if [[ "$reported_conflicts" -ne 3 ]]; then
  echo "Expected exactly three seeded checklist reconciliation conflicts, found $reported_conflicts."
  exit 1
fi


echo "Verifying atomic reminder delivery concurrency"
bash supabase/tests/reminder-delivery-concurrency.sh
