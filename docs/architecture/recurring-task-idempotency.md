# Recurring task occurrence idempotency

## Database boundary

Recurring roots initialize recurrence_parent_id to their own task ID. Generated occurrences retain that root ID. Migration 20260830103327_add_recurring_occurrence_idempotency.sql creates the partial unique index tasks_recurring_occurrence_unique on (user_id, recurrence_parent_id, due_at) for rows with a non-null recurrence parent, recurrence rule, and due time.

The unique index is the final concurrency boundary. It scopes occurrence identity to one owner, one recurring root, and one due instant. It does not replace the application's owner-scoped reads or RLS.

## Completion and retry behavior

setTaskStatusForUser marks a task completed with a status guard. A repeated completion still checks whether the next occurrence exists, because the earlier request may have committed completion but failed before generating the occurrence. The next occurrence is inserted with the root ID and calculated due instant.

If two completion requests race, the unique index allows only one occurrence INSERT. The losing request handles SQLSTATE 23505 by looking up the existing row using the authenticated owner, recurrence root, and due instant. If no matching row is found, the original database error is rethrown; an unrelated unique violation is not treated as success.

## Activity-event contract

The task trigger writes TASK_COMPLETED for the single status transition and TASK_RECURRENCE_GENERATED for the winning occurrence. The event INSERT is in the same PostgreSQL statement transaction as its task mutation. A unique-index loser does not execute a successful INSERT trigger, so it cannot emit a second recurrence-generated event.

## Regression coverage

- src/lib/tasks.test.ts verifies that a duplicate-key race resolves to the owner-scoped existing occurrence and that a missing match rethrows the original error.
- supabase/tests/recurring-occurrence-concurrency.sh runs two authenticated PostgreSQL sessions. The first completes the root and inserts the next occurrence while holding its transaction open. The second waits on the root update, then encounters the unique index conflict and resolves to the committed winner. The test asserts one completed event, one occurrence, and one source-linked recurrence-generated event.
- supabase/tests/organization-migrations.sh runs the concurrency test after the full migration replay and task activity-event checks.

These tests exercise PostgreSQL transaction/index behavior and the application's error-resolution branch separately. They are not a hosted Supabase/PostgREST end-to-end test and do not replace the required owner-controlled backup and isolated restoration.

No migration or production schema change is introduced by this test coverage.
