# Activity-event consistency

**Status:** Interim operational contract; durable task-event design deferred  
**Audited:** 2026-11-20  
**Scope:** Task create, update, status change, recurring occurrence generation, and the existing reminder-delivery event path.

## Findings

### Schema and authorization

The core migration defines `public.activity_events` with:

- UUID primary key.
- Required `user_id` referencing `auth.users(id)` with cascade deletion.
- Required free-text `event_type`.
- Nullable `entity_type` and `entity_id`.
- Required `occurred_at`, `metadata`, and `created_at` defaults.
- An owner RLS policy for **ALL** operations.

The schema does not provide an entity foreign key for `entity_id`, an append-only policy, an event idempotency key, or a uniqueness rule that deduplicates a retried domain action. It is an owner-scoped activity-history table, not a tamper-resistant audit log.

### Task mutation writers

In `src/lib/tasks.ts`:

- `createTask` checks the task INSERT and recurring-parent link UPDATE, then awaits `TASK_CREATED` insertion without inspecting the returned `error`.
- `updateTaskForUser` checks the owner-scoped task UPDATE, then awaits `TASK_UPDATED` insertion without inspecting the returned `error`.
- `setTaskStatus` checks the status UPDATE and recurring occurrence INSERT, but does not inspect returned errors from `TASK_RECURRENCE_GENERATED` or the final `TASK_COMPLETED`/`TASK_STATUS_CHANGED` inserts.

These are separate PostgREST requests, not one transaction.

Two failure modes follow:

1. A normal Supabase response containing `{ error }` is ignored by the current callers. The task mutation can return success while its activity event is absent.
2. If the request promise rejects after the database committed the event but before the response reaches the caller, the task mutation has already committed while the action can surface an error. Retrying can create a duplicate event because there is no request/idempotency key.

For completion, the status update uses a guard that avoids repeating a transition to `COMPLETED`. If the completion event insert returns an error after the status commit, a repeated completion call returns the current task before attempting the event again. The missing completion event is not repaired by that retry.

### Reminder delivery is different

Migration `20261120000300_atomic_reminder_delivery.sql` writes the notification, `REMINDER_DELIVERED` event, and reminder `delivered_at` inside the same database function transaction. An error rolls back all three effects. This is a durable delivery-state contract, not evidence that the task mutation writers have the same guarantee.

## Product requirement evidence

The README states that activity events are retained for historical analysis, and the roadmap plans productivity analytics and behavioral insights. The reviewed product/architecture documentation does not specify whether every task mutation must produce exactly one event or what a client should observe if event persistence fails.

## Interim contract

Until a durable writer is implemented:

- Task mutation events are **best-effort and non-atomic**.
- They must not be described as a complete, exactly-once audit stream.
- Analytics must not use them as a complete source of truth or infer that absence of an event means absence of a task mutation.
- Do not throw an event-insert error after a task write has committed as a superficial fix; that would report failure for a mutation that already happened and encourage ambiguous retries.
- Keep reminder delivery's existing atomic transaction contract unchanged.

This is a limitation statement, not a claim that best-effort history satisfies the long-term product vision.

## Recommended durable design before event-backed Analytics

Implement one consistent database transaction boundary for task creation, update, status transitions, and recurring occurrence generation. The domain mutation and its event must commit or roll back together. Include a stable idempotency/request key so retrying a request after a lost response cannot create duplicate events.

The design must preserve authenticated ownership/RLS, the current task relationship and active-project constraints, recurrence uniqueness, and existing API response semantics. Prefer narrow RPCs or a transactionally written outbox with explicit delivery/uniqueness semantics; do not add a generic SECURITY DEFINER bypass. Test both returned SQL errors and connection-loss/retry behavior on disposable PostgreSQL before adopting the design.

## Verification record

- Starting branch: `feature/organization-v1`.
- Starting PR head: `736882c5b42945356106efdcf7d2cb4f6b7cadc0`.
- Starting-head CI: [#404](https://github.com/mohith-krishnaa/personal-os/actions/runs/44783219198), successful before this audit.
- Audit documentation commit `cc6493df0bbb080eb2c18fa53f0d5ae4c9254b9c` passed [CI #405](https://github.com/mohith-krishnaa/personal-os/actions/runs/44790955563): 17/17 PostgREST safety tests, all 22 PostgreSQL 17 migrations and Organization/RLS/concurrency assertions, 132/132 application tests, typecheck, production build, and npm install audit with 0 vulnerabilities. No lint script is configured.
- Files inspected: `src/lib/tasks.ts`, `src/lib/tasks.test.ts`, `supabase/migrations/20260829182309_create_personal_os_core.sql`, `supabase/migrations/20261120000300_atomic_reminder_delivery.sql`, `src/app/api/reminders/deliver/route.ts`, `README.md`, `PROJECT_ROADMAP.md`, and `docs/architecture/organization-v1.md`.
- No application code, migration, test, RLS policy, or production database was changed.
- Local working-tree status is unverified because a fresh clone failed when this environment could not resolve `github.com`; the remote branch and PR metadata were inspected.
