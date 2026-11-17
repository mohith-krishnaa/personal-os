# Organization V1 — Architecture Contract

Status: implementation is under review in PR #11. This document records repository-level design decisions; it does not certify the live Supabase schema or deployment.

## Trust boundaries

1. Dashboard server actions create a server-side Supabase client and resolve the caller with `auth.getUser()`.
2. Application services derive project ownership from the authenticated session for project creation and constrain project updates by both project ID and authenticated user ID.
3. Subtask and checklist services validate parent/task ownership before writes and reads.
4. PostgreSQL row-level security (RLS) and task-link validation triggers are the intended authoritative persistence boundary. Application checks are defense in depth, not a substitute for RLS.
5. Never expose service-role credentials to browser code. User-facing operations must use the authenticated server-side client.

## Organization invariants

- Every project belongs to one authenticated user.
- A task's `project_id`, when present, must reference a project owned by the same user as the task.
- A subtask's parent must belong to the same user, and the subtask must use the same project as its parent.
- Task hierarchy must not contain self-links or indirect cycles.
- A checklist item must belong to the same user as its task.
- The application uses `public.checklist_items` as its canonical checklist table.
- The legacy `public.task_checklist_items` table is retained and reconciled forward; it is not dropped as part of Organization V1.
- The application-facing project field is `projects.name`. Where a legacy `projects.title` column exists, the compatibility migration backfills and dual-writes the two fields rather than dropping the legacy column.

## Migration and recovery decisions

- Migrations must be reviewed against the live migration ledger and live table definitions before execution.
- Historical notes and repository migration files are not evidence that a migration is or is not applied in production.
- No Organization migration may be applied while live schema state is unknown.
- Before production DDL, confirm a usable backup/recovery path and document the rollback or forward-fix plan.
- Do not drop legacy tables or columns as part of this milestone.

## Verification boundaries

- Unit tests using mocked Supabase clients verify application validation and query construction only. They do not prove PostgreSQL RLS, trigger behavior, authenticated integration, or cross-user isolation.
- CI on the current PR head must pass dependency installation, `npm run test`, `npm run typecheck`, and `npm run build`.
- The repository currently has no lint script or linter configuration; do not report a lint pass.
- Production acceptance still requires live migration-ledger/schema inspection, security/performance advisors, and authenticated CRUD plus cross-user isolation tests with separate users.

## Decision record

- **Use layered ownership enforcement:** validate in server actions/services and enforce again with database RLS/constraints/triggers.
- **Preserve compatibility:** keep the legacy checklist table and project title column while the application moves to the canonical checklist table and project name field.
- **Fail closed on unknown production state:** do not apply migrations, merge, or start Analytics based only on repository code when the live database cannot be inspected.


## Subtask read path and dashboard behavior

- The dashboard calls `listSubtasksAction` only when a task's subtask panel is expanded; it does not fetch child rows for every task during initial page rendering.
- The server action resolves the caller through the authenticated server-side Supabase client. It never accepts a caller-supplied owner ID.
- `listSubtasks` first verifies that the parent task is visible to and owned by the caller, then filters child tasks by both `user_id` and `parent_task_id`.
- Completion toggles reuse the existing `toggleTaskAction`, preserving the existing owner-scoped task status update and activity-event behavior.
- Service tests assert the owner/parent query filters and reject a foreign-owned parent before the child query. These mocked tests do not prove live RLS or cross-user isolation.
- The dashboard currently renders direct children only. Recursive hierarchy navigation is a separate UI requirement and is not claimed as complete.

## Additional decision record — 2026-11-17

- **Lazy-load subtasks through an authenticated server action:** avoid adding per-task child queries to the dashboard's initial load. Keep the caller identity server-derived and enforce both parent ownership and child owner filters in the service.
- **Reuse the task status action for subtask completion:** preserve existing owner-scoped update and activity-event semantics rather than introducing a second completion path.
- **Keep production rollout fail-closed:** this UI/service improvement does not remove the requirement to inspect live migrations/schema and verify RLS with separate authenticated users before merging.


## Subtask create/list consistency

- If the direct-child list was already loaded successfully, a newly created subtask is appended locally without an extra read.
- If the initial list read failed, creation retains the newly created row but does not mark the partial list as complete; it immediately retries the owner-scoped list action.
- If that refresh also fails, the panel remains retryable and keeps the newly created row visible until a later successful refresh.
- The create control is disabled while a list read is in flight to avoid overlapping reads racing with a create.
- The refresh uses the same authenticated server action and owner/parent filters; no client-supplied identity or database privilege changes are introduced.


## Checklist create/list consistency decision — 2026-11-17

- The checklist dashboard must not treat a locally appended item as proof that the checklist list is complete when its most recent read failed.
- `ChecklistManager` tracks successful list loading. After creating an item into an incomplete list, it retains the new item and reloads through the existing authenticated `listChecklistItemsAction`.
- If that refresh fails, the created item remains visible, the list remains marked incomplete, and the user can retry. Add is disabled while a list read is in flight.
- The client-side state helper mirrors service ordering (`position`, then `created_at`) for locally appended rows on a successfully loaded list.
- This change does not alter the server trust boundary: server actions still derive identity with `auth.getUser()`; services validate task ownership and constrain checklist operations by `user_id` and `task_id`. It introduces no client-supplied owner ID, elevated credential, schema change, or RLS change.
- Regression tests verify state transitions and ordering, but mocked/application tests do not prove live PostgreSQL RLS or cross-user isolation.


## Verification record — 2026-11-17

- CI #128 passed on PR #11 head `4bb083fe94fd36419f47149c3951bc9b594c98aa`: 38 unit tests passed, TypeScript check passed, and production build passed.
- The tests cover application state transitions and service query construction only. They do not establish live PostgreSQL RLS, trigger execution, or two-user isolation.
- Live migration ledger/schema remain unknown because supported migration listing, table introspection, read-only SQL, and advisor calls still time out or report hibernation.


## Checklist service ownership verification — 2026-11-17

- The checklist service's read path first selects the task using both task ID and owner ID, then reads checklist rows filtered by both `user_id` and `task_id` and ordered by `position`, then `created_at`.
- The create path validates task ownership before insert and explicitly sets `user_id` from the trusted server-derived service argument. The completion and deletion paths constrain mutations by both checklist item ID and owner ID.
- Four mocked Supabase service tests were added to assert these query/payload invariants and reject a foreign-owned task before querying checklist rows.
- These tests improve application-level regression coverage only. They do not exercise authenticated server actions, PostgreSQL RLS, triggers, or cross-user isolation against the live database.
- No production implementation, schema, migration, RLS, or credential change was made in this test-only checkpoint.
- CI #131 for commit `adfffa6f5e125ff9224e618a89ec177144663c9f` was queued at last check. The previous head's CI #130 passed with 38 tests, typecheck, and production build.


## Latest verification — checklist ownership tests (2026-11-17)

- CI #135 passed on current PR #11 head `bc82493c8c5533148e3d82aaf667374fd33b9ee1`: 42 tests passed, typecheck passed, production build passed, and npm install reported 0 vulnerabilities.
- The test-only checkpoint initially failed because two checklist service functions were not imported in the test module. The missing imports were added; the passing CI run is on the corrected head.
- The four new tests assert application service query/payload boundaries. They do not prove RLS or cross-user isolation in PostgreSQL.
- Live schema and migration ledger remain unknown: supported migration listing, table introspection, and read-only SQL time out; security/performance/health advisors report project hibernation.


## Client list-state consistency

- A subtask list is considered complete only after a successful canonical server read.
- If a refresh fails, keep already-visible rows for continuity but mark the list incomplete. A subsequent create must request the canonical owner-scoped list again rather than treating the retained rows as exhaustive.
- The state transition is covered by a pure helper regression test and does not alter server authorization, ownership checks, or the PostgreSQL RLS boundary.
- This UI rule applies to recovery from transient read failures; it is not evidence of live database availability or cross-user isolation.


## Decision — authenticated project-list reads (2026-11-17)

Project list reads must enforce the same explicit application-level owner boundary as project writes:

1. Resolve the caller from the server-side Supabase session using auth.getUser().
2. Reject the request before querying if the session is missing or invalid.
3. Add an explicit user_id = authenticated user id filter to the projects query.
4. Preserve optional status filtering and deterministic newest-first ordering.

This is defense in depth, not a replacement for PostgreSQL RLS. The new unit tests assert the generated query filters and unauthenticated fail-closed behavior using mocked clients; they do not prove live RLS enforcement or cross-user isolation. Those still require authenticated tests against the actual database once connectivity is restored.

Verification note (2026-11-17): CI #143 passed on code-bearing commit 1106efd1b3a1be9e3b5aac18bd8a6e714476cb9f with 45 tests, typecheck, and production build; CI #144 passed on documentation checkpoint 2c618299c5bd3db2bf03aad7f4afecc6ab2521a7. These are mocked application-service tests only; live PostgreSQL RLS and two-user isolation remain unverified.


Latest verification (2026-11-17): code-bearing commit 1106efd1b3a1be9e3b5aac18bd8a6e714476cb9f passed CI #143 (45 tests, typecheck, production build); latest documentation checkpoint b86056d20ca3f9ed470709ad4baebcfa711e9ea6 passed CI #147. Live PostgreSQL RLS and authenticated two-user isolation remain unverified.


## Decision — authenticated task-list reads (2026-11-17)

Task listing must enforce the same explicit application-level owner boundary as project, subtask, and checklist reads:

1. Resolve the caller with `auth.getUser()` on the same authenticated server-side Supabase client used for the read.
2. Reject a missing or invalid session before querying tasks.
3. Filter task rows by `user_id = authenticated user id`.
4. Preserve the optional project filter and existing due-date / creation-time ordering.

The query is isolated in `src/lib/task-queries.ts` so owner filtering and ordering can be regression-tested without importing the Next.js server runtime. Tests use mocked Supabase clients and establish query construction only. PostgreSQL RLS and cross-user isolation still require live authenticated database tests.

Verification: CI #150 passed on code-bearing commit `8f5eac4fd9d314a9fb3125de46789fe7858beac3` with 48 tests, typecheck, and production build. No database schema or policy was changed.
