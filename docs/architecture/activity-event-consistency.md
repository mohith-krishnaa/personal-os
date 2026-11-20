# Activity Event Consistency

## Implemented on `feature/organization-v1`

Migration `20261121000100_durable_task_activity_events.sql` installs `public.record_task_activity_event()` as a `SECURITY INVOKER` trigger function with `search_path = pg_catalog, public`. An `AFTER INSERT OR UPDATE` trigger on `public.tasks` inserts the corresponding activity event in the same PostgreSQL statement transaction.

Event mapping:

- INSERT with no `recurrence_parent_id`: `TASK_CREATED` (covers tasks and subtasks).
- INSERT with a `recurrence_parent_id`: `TASK_RECURRENCE_GENERATED`, with the nearest earlier task in the series recorded as `metadata.source_task_id`.
- UPDATE with a status change to COMPLETED: `TASK_COMPLETED`.
- UPDATE with another status change: `TASK_STATUS_CHANGED`.
- Other meaningful UPDATE: `TASK_UPDATED`.

The trigger skips updates that change only non-domain bookkeeping fields (for example `updated_at`) and skips the one-time recurring-root self-link initialization. A failure inserting the event aborts and rolls back the task INSERT/UPDATE statement. This is statement-level atomicity, not a separate asynchronous outbox.

The application no longer inserts task activity events separately in `src/lib/tasks.ts`. The trigger therefore also covers direct authenticated PostgREST task writes and subtask inserts, subject to existing table privileges and RLS. The trigger is not SECURITY DEFINER: authenticated activity-event INSERT remains governed by the existing `activity_events_owner` RLS policy. EXECUTE is revoked from PUBLIC/anon and granted to authenticated/service_role.

`setTaskStatusForUser` now retries recurrence generation when a task is already COMPLETED. This repairs the case where the parent completion committed but a later recurrence-occurrence INSERT/event transaction failed. The existing `tasks_recurring_occurrence_unique` index makes a repeated occurrence attempt safe.

## Remaining idempotency and audit limitations

This implementation guarantees that each committed task INSERT/meaningful UPDATE has its matching event, or the task statement does not commit. It does **not** yet guarantee one task per user intent:

- Task and subtask creation do not yet accept a stable client-generated request ID. A client retry after an ambiguous response can create another task row and another truthful `TASK_CREATED` event.
- UPDATE retries are event-idempotent when the retry is a no-op; meaningful repeated changes are distinct committed mutations.
- Recurrence occurrence uniqueness prevents a second row/event for the same series occurrence.
- DELETE is not covered by this trigger. Task deletion/cascade does not currently produce a `TASK_DELETED` event.
- `activity_events` remains owner-scoped but mutable: its owner policy is `FOR ALL`, `entity_id` is polymorphic without an entity FK, and there is no append-only or event-idempotency constraint.
- No historical event backfill is attempted. Past missing events cannot be reconstructed reliably from the current schema.

Therefore, Analytics must not interpret event counts as counts of user intent, nor infer that an absent event proves no task deletion occurred. Use current task rows as the source of truth until stable create request idempotency, DELETE semantics, and retention/immutability requirements are designed and tested.

## Verification

The disposable PostgreSQL regression `supabase/tests/task-activity-events.sql` injects failures for TASK_CREATED, TASK_UPDATED, TASK_COMPLETED, and TASK_RECURRENCE_GENERATED. It verifies statement rollback, successful retry, no-op update behavior, recurring-root self-link suppression, recurrence uniqueness/source metadata, trigger SECURITY INVOKER/search_path/grants, and Owner A/B event isolation.

[CI #408](https://github.com/mohith-krishnaa/personal-os/actions/runs/44802872792) passed on `e288c55768bca52e906d51fd6b9580f3ba0cff33`: 23/23 PostgreSQL 17 migrations, task-event fault-injection/retry assertions, migration reapplication, Organization/RLS and concurrency assertions, 133/133 application tests, typecheck, production build, and npm audit with 0 vulnerabilities. No lint script is configured.

## Production rollout

The migration is branch-only. The last verified live migration ledger contained eight versions; production was not queried during this implementation run. The complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist reconciliation review, and authenticated two-owner PostgREST acceptance remain required before production migration. No production schema/data/RLS changes or migration were performed.
