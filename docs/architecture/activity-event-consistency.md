# Current event contract — migration 27 (2026-11-21)

This section supersedes earlier SECURITY INVOKER and authenticated SELECT/INSERT descriptions below. Historical checkpoint sections remain as records of the contract at those commits.

## Trusted writer boundary

Migration `20261121000500_trusted_activity_event_writers.sql` makes `public.record_task_activity_event()` a postgres-owned SECURITY DEFINER trigger function with fixed `search_path = pg_catalog, public`. It is attached to task INSERT/UPDATE/DELETE and cannot be directly executed by authenticated clients. The trigger checks that a non-null `auth.uid()` matches `NEW.user_id` for INSERT/UPDATE; DELETE emits only when `auth.uid() = OLD.user_id`. Event insertion remains part of the task statement transaction, so event-write failure rolls back the mutation or cascade.

Authenticated users now have owner-scoped SELECT only on `activity_events`; the INSERT policy is removed and direct authenticated INSERT privilege is revoked. The task trigger writes as its postgres owner. `service_role` retains SELECT/INSERT as a trusted backend role, and `claim_due_reminders(integer)` remains a postgres-owned SECURITY DEFINER RPC executable only by service_role. This blocks ordinary clients from fabricating their own event history without changing the trusted server contract.

## Current event/entity metadata contract

| Event type | Entity type and identifier | Metadata |
|---|---|---|
| `TASK_CREATED` | `TASK` / task UUID | `source=database`, `recurring` boolean |
| `TASK_RECURRENCE_GENERATED` | `TASK` / occurrence UUID | `source_task_id` UUID |
| `TASK_UPDATED` | `TASK` / task UUID | `source=database`; no field-level diff |
| `TASK_COMPLETED` | `TASK` / task UUID | new `status` only |
| `TASK_STATUS_CHANGED` | `TASK` / task UUID | new `status` only; previous status omitted |
| `TASK_DELETED` | `TASK` / deleted task UUID | title, status, project, parent and recurrence-parent snapshot |
| `REMINDER_DELIVERED` | `REMINDER` / reminder UUID | task UUID and delivery channel |

The task trigger is the only task-event writer. The reminder delivery RPC is the reminder-event writer. No application TypeScript module directly inserts or reads `activity_events`.

## Schema limits and analytics implications

- `event_type` is TEXT NOT NULL without a CHECK constraint or event catalog.
- `entity_type` and UUID `entity_id` are nullable; there is no pair CHECK. Current trusted writers always set both.
- `entity_id` intentionally has no FK. A `TASK_DELETED` event must retain the deleted task UUID; task deletion and Auth-account cleanup have different retention semantics.
- `metadata` is JSONB NOT NULL but is not constrained to an object shape.
- There is no generic event idempotency key. Retry safety is provided by domain-specific task-create request IDs/hashes, recurring-occurrence uniqueness, reminder row locking/delivery markers and notification uniqueness. Task no-op updates do not emit duplicate events; repeated deletes do not affect a row.
- `TASK_UPDATED` and status events do not contain before/after field diffs. Analytics cannot reconstruct every field change or infer time spent.
- Service-role/Auth-account cleanup intentionally skips per-task DELETE events. No historical backfill, event reader or retention schedule exists.
- Event counts are database-observed transitions, not direct measurements of intent, effort, or productivity.

CI #448 passed on final checkpoint HEAD `c179e331f75ba3a490043eb0b90c047a89ca0a3b` (17/17 preflight tests, 27 migrations plus reapplication, 147/147 app tests, typecheck, production build, npm audit 0 vulnerabilities). CI #445 passed on fail-closed follow-up `fbb3be06e3c21156ce8e4f3d72c408d657af7d45`: 27 migration replay and migration 27 reapplication, 17/17 PostgREST preflight tests, 147/147 application tests, typecheck, production build, and npm audit with 0 vulnerabilities.

Read-only preflight query 20 reports these schema and idempotency properties. On the legacy production baseline it correctly reports the task trigger and task-create key absent while the reminder writer, recurrence uniqueness and reminder-notification uniqueness are present.

---

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

The application no longer inserts task activity events separately in `src/lib/tasks.ts`. The trigger therefore also covers direct authenticated PostgREST task writes, subtask inserts, owner-context deletes, and descendant deletes, subject to existing table privileges and RLS. The trigger is not SECURITY DEFINER: authenticated activity-event INSERT remains governed by the `activity_events_insert_owner` RLS policy; owner-scoped SELECT uses `activity_events_select_owner`. EXECUTE is revoked from PUBLIC/anon and granted to authenticated/service_role.

`setTaskStatusForUser` now retries recurrence generation when a task is already COMPLETED. This repairs the case where the parent completion committed but a later recurrence-occurrence INSERT/event transaction failed. The existing `tasks_recurring_occurrence_unique` index makes a repeated occurrence attempt safe.

## Task create request idempotency

Migration `20261121000200_task_create_request_idempotency.sql` adds a non-null `tasks.client_request_id`, a nullable SHA-256 `client_request_hash`, the unique constraint `(user_id, client_request_id)`, hash-format validation, and a SECURITY INVOKER trigger that prevents request identity mutation. Existing task rows receive opaque server-generated UUIDs; non-first-party/internal inserts retain a generated-key default.

The first-party task editor, quick-add action, and subtask manager generate one client UUID for an unchanged form payload and retain it after an ambiguous failure. A changed payload receives a new key. The server normalizes the UUID, hashes a canonical representation of the validated create payload, looks up an existing owner/request row before checking mutable project/parent state, then uses Supabase upsert with `ignoreDuplicates` to handle concurrent duplicates. If another request wins the unique key, the server reads the winning row under the same owner scope and compares the stored hash. Same-key/same-payload retries return the existing task; same-key/different-payload reuse is rejected. The request hash and key are not included in create-action return values.

The request key is unique per owner, so two owners may independently use the same UUID. The database trigger makes the stored identity immutable. Internal recurrence occurrence inserts continue to use generated keys; `tasks_recurring_occurrence_unique` remains the recurrence-specific idempotency guard. A task deletion removes the key with the task row, so a very late retry after deletion is not protected by a durable tombstone ledger.

## Remaining event and audit limitations

- UPDATE retries are event-idempotent when the retry is a no-op; meaningful repeated changes are distinct committed mutations.
- Recurrence occurrence uniqueness prevents a second row/event for the same series occurrence.
- Authenticated owner-context task DELETE and parent/descendant cascades now produce `TASK_DELETED` events. Service-role/admin deletes and Auth-account cascades intentionally skip per-task deletion events because `tasks.user_id` and `activity_events.user_id` both cascade from `auth.users`; inserting an event for an account being deleted could violate the existing FK and block account cleanup.
- `activity_events` is application-role append-only after migration 26: authenticated and service_role retain SELECT/INSERT only, anon has no table privileges, and no application role has UPDATE/DELETE/TRUNCATE. The table owner `postgres` retains maintenance privileges; `auth.users` deletion still cascades through the existing FK. This is not tamper-proof against the table owner and no retention schedule has been defined.
- `entity_id` remains polymorphic without an entity FK, and no event-idempotency key exists for arbitrary event types.
- Direct API clients that need retry guarantees must supply a stable `client_request_id`; the database default preserves compatibility but creates a new key for each omitted-key insert.
- No historical event backfill is attempted. Past missing events cannot be reconstructed reliably from the current schema.

Analytics must not interpret activity counts as counts of user intent, nor infer that an absent event proves no task deletion occurred before migration 25, for service-role/Auth-account cleanup, or where mutable event rows have been removed. Use current task rows as the source of truth until event retention/immutability requirements are designed and tested.

## Verification

The disposable PostgreSQL regression `supabase/tests/task-activity-events.sql` injects failures for TASK_CREATED, TASK_UPDATED, TASK_COMPLETED, and TASK_RECURRENCE_GENERATED. It verifies statement rollback, successful retry, no-op update behavior, recurring-root self-link suppression, recurrence uniqueness/source metadata, trigger SECURITY INVOKER/search_path/grants, and Owner A/B event isolation.

[CI #408](https://github.com/mohith-krishnaa/personal-os/actions/runs/44802872792) passed on code HEAD `e288c55768bca52e906d51fd6b9580f3ba0cff33`; [CI #411](https://github.com/mohith-krishnaa/personal-os/actions/runs/44804065396) passed on the later documentation checkpoint `014bd50e4a4d4835927daa762cf1cc53c615b545`. The verified checks include 23/23 PostgreSQL 17 migrations, task-event fault-injection/retry assertions, migration reapplication, Organization/RLS and concurrency assertions, 133/133 application tests, typecheck, production build, and npm audit with 0 vulnerabilities. No lint script is configured.

## Production rollout

The task-event migrations remain branch-only. Fresh read-only production inspection reconfirmed eight live migration-ledger versions versus 26 repository migrations (18 branch-only), nine RLS-enabled public application tables, no task activity trigger, no `client_request_id` column, and the existing owner `FOR ALL` activity-event policy. Read-only preflight query 18 confirmed the production task-parent, task-owner, and activity-owner cascade FKs are present while the new task activity trigger is absent. Authenticated and service_role have activity-event INSERT privilege. No production write or schema change was performed.

The complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist reconciliation review, and authenticated two-owner PostgREST acceptance remain required before production migration.


## DELETE-event verification — migration 25

Migration `20261121000300_task_delete_activity_events.sql` extends the existing trigger without changing RLS or FK actions. The DELETE branch records only when the authenticated JWT subject matches `OLD.user_id`; service-role/Auth-account cleanup skips the event so the existing Auth FK cascades continue to work.

The disposable regression `supabase/tests/task-delete-activity-events.sql` covers direct delete success and failure rollback, repeated delete behavior, three-level parent/descendant cascades, failure of a descendant event rolling back the entire cascade, Owner A/B delete and event visibility isolation, and Auth-account deletion cleanup. The migration runner now expects 25 migrations and reapplies migration 25 after the earlier activity-event migration to verify idempotence.

[CI #438](https://github.com/mohith-krishnaa/personal-os/actions/runs/44810205162) passed on code/test HEAD `2ee721b051f52174fada5a803da6690ed5a9806e`: 17/17 PostgREST safety preflight tests, 25/25 PostgreSQL 17 migrations, task DELETE and existing activity/idempotency/concurrency assertions, 147/147 application tests, TypeScript typecheck, production build, and npm audit with 0 vulnerabilities. No lint script is configured. CI #436/#437 failures were fixture UUID collisions and were corrected before #438.


## Append-only application access audit — migration 26 (2026-11-21)

A branch-head source audit inspected all 29 TypeScript modules under `src/lib`, all 17 dashboard modules, the reminder delivery route, login/page/layout/error modules, and the project type module. No application module reads `activity_events` directly or issues UPDATE/DELETE against it. Task events are written by the SECURITY INVOKER task trigger; reminder delivery writes its event inside the existing SECURITY DEFINER RPC.

The database-test audit found two direct DELETE cleanup callers: `reminder-delivery-concurrency.sh` and `task-create-idempotency-concurrency.sh`. Both explicitly default `PGUSER=postgres`, so the migration preserves their cleanup capability through the table owner's privileges. Other activity-event tests only insert, select, or install/drop fault-injection triggers. No scheduled retention job, retention interval, archival table, or user-facing event reader is defined in the current repository or roadmap.

Migration `20261121000400_activity_events_append_only.sql` replaces the broad owner `FOR ALL` policy with separate authenticated owner-scoped SELECT and INSERT policies. It revokes all table privileges from PUBLIC and anon, and resets authenticated/service_role to SELECT and INSERT only. The `postgres` table owner retains controlled UPDATE/DELETE/TRUNCATE privileges for future owner-approved maintenance. The existing `auth.users ON DELETE CASCADE` remains intact; account deletion can still remove that user's events. This is application-role append-only protection, not a tamper-proof or immutable audit log.

The disposable regression `supabase/tests/activity-event-append-only.sql` checks exact policy scope, authenticated owner isolation, rejected cross-owner INSERT, rejected authenticated/service_role UPDATE and DELETE, denied TRUNCATE privileges, preserved owner maintenance privileges, and Auth-account cascade cleanup. Read-only preflight query 19 reports the policy/privilege matrix. CI #442 passed on code/test HEAD `03217aefdefb88fee593629f217d7efaf36d538d`: 26/26 PostgreSQL 17 migrations, 17/17 PostgREST preflight tests, 147/147 application tests, typecheck, production build, and npm audit with 0 vulnerabilities. Production remains read-only; its current FOR ALL policy and broad grants are unchanged until the owner backup/restore and rollout approvals are complete.
