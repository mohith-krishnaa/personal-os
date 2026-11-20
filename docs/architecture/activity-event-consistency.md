# Activity Event Consistency

## Implemented on `feature/organization-v1`

Migration `20261121000100_durable_task_activity_events.sql` installs `public.record_task_activity_event()` as a `SECURITY INVOKER` trigger function with `search_path = pg_catalog, public`. Migration `20261121000300_task_delete_activity_events.sql` extends the trigger to `AFTER INSERT OR UPDATE OR DELETE`; all task events are inserted in the same PostgreSQL statement transaction.

Event mapping:

- INSERT with no `recurrence_parent_id`: `TASK_CREATED` (covers tasks and subtasks).
- INSERT with a `recurrence_parent_id`: `TASK_RECURRENCE_GENERATED`, with the nearest earlier task in the series recorded as `metadata.source_task_id`.
- UPDATE with a status change to COMPLETED: `TASK_COMPLETED`.
- UPDATE with another status change: `TASK_STATUS_CHANGED`.
- Other meaningful UPDATE: `TASK_UPDATED`.
- DELETE when `auth.uid() = OLD.user_id`: `TASK_DELETED`, with a snapshot of title, status, project ID, parent-task ID, and recurrence-parent ID.

The trigger skips updates that change only non-domain bookkeeping fields (for example `updated_at`) and skips the one-time recurring-root self-link initialization. A failure inserting the event aborts and rolls back the task INSERT/UPDATE/DELETE statement, including all task descendants deleted by `ON DELETE CASCADE`. This is statement-level atomicity, not a separate asynchronous outbox.

The application no longer inserts task activity events separately in `src/lib/tasks.ts`. The trigger therefore also covers direct authenticated PostgREST task writes, subtask inserts, owner-context deletes, and descendant deletes, subject to existing table privileges and RLS. The trigger is not SECURITY DEFINER: authenticated activity-event INSERT remains governed by the existing `activity_events_owner` RLS policy. EXECUTE is revoked from PUBLIC/anon and granted to authenticated/service_role.

`setTaskStatusForUser` now retries recurrence generation when a task is already COMPLETED. This repairs the case where the parent completion committed but a later recurrence-occurrence INSERT/event transaction failed. The existing `tasks_recurring_occurrence_unique` index makes a repeated occurrence attempt safe.

## Task create request idempotency

Migration `20261121000200_task_create_request_idempotency.sql` adds a non-null `tasks.client_request_id`, a nullable SHA-256 `client_request_hash`, the unique constraint `(user_id, client_request_id)`, hash-format validation, and a SECURITY INVOKER trigger that prevents request identity mutation. Existing task rows receive opaque server-generated UUIDs; non-first-party/internal inserts retain a generated-key default.

The first-party task editor, quick-add action, and subtask manager generate one client UUID for an unchanged form payload and retain it after an ambiguous failure. A changed payload receives a new key. The server normalizes the UUID, hashes a canonical representation of the validated create payload, looks up an existing owner/request row before checking mutable project/parent state, then uses Supabase upsert with `ignoreDuplicates` to handle concurrent duplicates. If another request wins the unique key, the server reads the winning row under the same owner scope and compares the stored hash. Same-key/same-payload retries return the existing task; same-key/different-payload reuse is rejected. The request hash and key are not included in create-action return values.

The request key is unique per owner, so two owners may independently use the same UUID. The database trigger makes the stored identity immutable. Internal recurrence occurrence inserts continue to use generated keys; `tasks_recurring_occurrence_unique` remains the recurrence-specific idempotency guard. A task deletion removes the key with the task row, so a very late retry after deletion is not protected by a durable tombstone ledger.

## Remaining event and audit limitations

- UPDATE retries are event-idempotent when the retry is a no-op; meaningful repeated changes are distinct committed mutations.
- Recurrence occurrence uniqueness prevents a second row/event for the same series occurrence.
- Authenticated owner-context task DELETE and parent/descendant cascades now produce `TASK_DELETED` events. Service-role/admin deletes and Auth-account cascades intentionally skip per-task deletion events because `tasks.user_id` and `activity_events.user_id` both cascade from `auth.users`; inserting an event for an account being deleted could violate the existing FK and block account cleanup.
- `activity_events` remains owner-scoped but mutable: its owner policy is `FOR ALL`, `entity_id` is polymorphic without an entity FK, and there is no append-only or event-idempotency constraint.
- Direct API clients that need retry guarantees must supply a stable `client_request_id`; the database default preserves compatibility but creates a new key for each omitted-key insert.
- No historical event backfill is attempted. Past missing events cannot be reconstructed reliably from the current schema.

Analytics must not interpret activity counts as counts of user intent, nor infer that an absent event proves no task deletion occurred before migration 25, for service-role/Auth-account cleanup, or where mutable event rows have been removed. Use current task rows as the source of truth until event retention/immutability requirements are designed and tested.

## Verification

The disposable PostgreSQL regression `supabase/tests/task-activity-events.sql` injects failures for TASK_CREATED, TASK_UPDATED, TASK_COMPLETED, and TASK_RECURRENCE_GENERATED. It verifies statement rollback, successful retry, no-op update behavior, recurring-root self-link suppression, recurrence uniqueness/source metadata, trigger SECURITY INVOKER/search_path/grants, and Owner A/B event isolation.

[CI #408](https://github.com/mohith-krishnaa/personal-os/actions/runs/44802872792) passed on code HEAD `e288c55768bca52e906d51fd6b9580f3ba0cff33`; [CI #411](https://github.com/mohith-krishnaa/personal-os/actions/runs/44804065396) passed on the later documentation checkpoint `014bd50e4a4d4835927daa762cf1cc53c615b545`. The verified checks include 23/23 PostgreSQL 17 migrations, task-event fault-injection/retry assertions, migration reapplication, Organization/RLS and concurrency assertions, 133/133 application tests, typecheck, production build, and npm audit with 0 vulnerabilities. No lint script is configured.

## Production rollout

The task-event migrations remain branch-only. Fresh read-only production inspection reconfirmed eight live migration-ledger versions versus 25 repository migrations (17 branch-only), nine RLS-enabled public application tables, no task activity trigger, no `client_request_id` column, and the existing owner `FOR ALL` activity-event policy. Read-only preflight query 18 confirmed the production task-parent, task-owner, and activity-owner cascade FKs are present while the new task activity trigger is absent. Authenticated and service_role have activity-event INSERT privilege. No production write or schema change was performed.

The complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist reconciliation review, and authenticated two-owner PostgREST acceptance remain required before production migration.


## DELETE-event verification — migration 25

Migration `20261121000300_task_delete_activity_events.sql` extends the existing trigger without changing RLS or FK actions. The DELETE branch records only when the authenticated JWT subject matches `OLD.user_id`; service-role/Auth-account cleanup skips the event so the existing Auth FK cascades continue to work.

The disposable regression `supabase/tests/task-delete-activity-events.sql` covers direct delete success and failure rollback, repeated delete behavior, three-level parent/descendant cascades, failure of a descendant event rolling back the entire cascade, Owner A/B delete and event visibility isolation, and Auth-account deletion cleanup. The migration runner now expects 25 migrations and reapplies migration 25 after the earlier activity-event migration to verify idempotence.

[CI #438](https://github.com/mohith-krishnaa/personal-os/actions/runs/44810205162) passed on code/test HEAD `2ee721b051f52174fada5a803da6690ed5a9806e`: 17/17 PostgREST safety preflight tests, 25/25 PostgreSQL 17 migrations, task DELETE and existing activity/idempotency/concurrency assertions, 147/147 application tests, TypeScript typecheck, production build, and npm audit with 0 vulnerabilities. No lint script is configured. CI #436/#437 failures were fixture UUID collisions and were corrected before #438.
