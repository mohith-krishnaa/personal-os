# Organization V1 — Architecture Contract

Status: implementation is under review in PR #11. This document records repository-level design decisions; it does not certify the live Supabase schema or deployment.

**Verified checkpoint — 2026-11-20 (authenticated task project reassignment).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `0da6239761d1f2fc1adf9b34d2a418517f9ae458`; PR #11 remains open and unmerged.

Extended `supabase/tests/organization-migration-assertions.sql` so task project assignment and reassignment run under the actual disposable-database `authenticated` role with Owner A's JWT subject and RLS enabled. The fixture creates a second ACTIVE project owned by Owner A and exercises: an unassigned task assigned to an ACTIVE project; reassignment from one owned ACTIVE project to another; rejection of reassignment into a COMPLETED project; rejection of reassignment into an ARCHIVED project; and rejection of reassignment to Owner B's project. Rejected updates must leave the original `project_id` unchanged. The existing authenticated same-link update after archive remains covered, as do cross-owner parent INSERT denials.

[CI #360](https://github.com/mohith-krishnaa/personal-os/actions/runs/44687024395) passed on the exact code/test commit. The workflow replayed all **20/20 migrations** in disposable PostgreSQL 17; Organization/RLS and authenticated/anonymous isolation assertions passed; project archive lifecycle and two-session task hierarchy/project-status concurrency checks passed; **90/90 application tests passed**; TypeScript typecheck passed; and the production build passed. The configured workflow does not run `npm audit`; no lint script is configured. No migration or runtime application code changed, and the repository remains at 20 migration files.

Production Supabase was not accessed or modified during this test-only run. The last documented read-only checkpoint remains 8 live migration-ledger entries with the Organization trigger not deployed; that is not a fresh inspection for this run. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. No local checkout is attached, so local `git status` cannot be certified.

**Next task:** add authenticated-role UPDATE coverage for `parent_task_id` changes: same-owner/same-project parent reassignment should succeed where valid; cross-owner and cross-project parent reassignment must fail without changing the prior relationship; existing historical tasks in completed/archived projects must remain maintainable without weakening the task-link guard. Keep Analytics queued until Organization acceptance is genuinely complete.
---
## Authenticated-role task-link trigger verification — 2026-11-20

The disposable migration assertion now runs under `SET ROLE authenticated` with Owner A and Owner B JWT subjects. It proves the role does not bypass RLS; Owner A can insert a subtask into an ACTIVE project; COMPLETED and ARCHIVED project inserts fail with the dedicated check violation; unchanged historical links remain valid after archive; and foreign-owner parent attempts fail in both directions. This is a disposable PostgreSQL role/RLS test, not a live PostgREST test. [CI #357](https://github.com/mohith-krishnaa/personal-os/actions/runs/44680309313) passed the full 20-migration PostgreSQL 17 replay, Organization/RLS and authenticated/anonymous isolation assertions, archive lifecycle and concurrency checks, 90/90 application tests, typecheck, and production build. No migration was added; the branch remains at 20 migrations. The live Supabase project remains at 8 migrations with no Organization task triggers; production rollout remains blocked on the owner-controlled backup/restore and authenticated PostgREST acceptance gates.

Latest code/test verification (2026-11-20): commit `eb194521e6d1bb12147058530c84ce7315395a44` passed [CI #357](https://github.com/mohith-krishnaa/personal-os/actions/runs/44680309313): all 20 PostgreSQL 17 migrations replayed; Organization/RLS, authenticated Owner A/Owner B and anonymous isolation, archive lifecycle, and hierarchy/concurrency assertions passed; 90/90 application tests, TypeScript typecheck, and production build passed. npm install audited 43 packages and found 0 vulnerabilities. The existing esbuild install-script allowlist warning remains; no lint script is configured. The final documentation HEAD `f3e49a96dd960180204d9e75bc45aca709709005` also passed [CI #358](https://github.com/mohith-krishnaa/personal-os/actions/runs/44680569754).

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

## Runtime task creation path audit — 2026-11-20

- A branch-head audit scanned all 53 TypeScript/TSX modules under `src/`. Runtime `tasks` INSERTs are confined to `src/lib/tasks.ts` (ordinary creation and recurring occurrence generation) and `src/lib/subtasks.ts` (subtask creation). Reminder/checklist services only read tasks for owner validation; the reminder API inserts notifications and activity events, not tasks.
- `createTask` resolves the authenticated user and calls the shared task-link preflight with `requireActiveProject: true`. Recurring occurrence generation checks the owner-scoped project status before inserting; the database trigger remains authoritative if project status changes after that read.
- `createSubtask` now performs the same ACTIVE-project preflight. It selects `id,status` using both project ID and owner ID, rejects COMPLETED/ARCHIVED projects before INSERT, and retains the parent-owner and same-project checks. The trigger still handles races and direct PostgREST writes.
- Three mocked-service regressions cover an allowed ACTIVE-project subtask with owner filters and rejection of COMPLETED/ARCHIVED projects before task insertion. CI #350 verified 90/90 application tests and the full 20-migration PostgreSQL 17 workflow.
- This application preflight does not replace the production trigger or live PostgREST authorization tests. No production migration or database write was performed.

## Project archive/task-assignment concurrency decision — 2026-11-20

- The `require_active_project_for_new_task_links` SECURITY INVOKER trigger takes a `FOR SHARE` lock on the owner-matched project row before accepting a new task link. Project status updates conflict with that lock, so assignment and completion/archive have a deterministic serialization order.
- If assignment wins, the task link commits first and a later archive/completion may commit without detaching the historical link. If completion/archive wins, the waiting assignment must observe the inactive status and fail with the dedicated check violation.
- CI #347 exercises both READ COMMITTED lock orders with separate PostgreSQL sessions, confirms the waiting session is blocked by the expected writer via `pg_blocking_pids`, verifies final project/task state, and checks for lingering sessions. The existing task-hierarchy cycle race remains covered.
- This test runs against a disposable PostgreSQL 17 fixture. It does not prove that the trigger exists in production; the live Supabase project remains at 8 migrations and has no user-defined trigger on `projects` or `tasks`.

## Project name/title compatibility decision — 2026-11-20

- Current application services, project manager, task editor, and dashboard task labels use only canonical `projects.name`; application create/rename requests do not write `title`.
- Legacy clients may still write `title`. The compatibility trigger mirrors title-only writes to name and name-only writes to title.
- If one statement supplies conflicting values for both columns, canonical `name` wins. This is intentional and is now covered for both INSERT and UPDATE by the Organization migration assertion suite.
- The compatibility migration and legacy column remain unchanged; this checkpoint adds regression coverage only. Do not remove `title` until deployed legacy-client usage has been measured over an owner-approved compatibility window and a verified backup/restore gate is satisfied.

## Legacy project status compatibility decision — 2026-11-20

- The core schema allows `ACTIVE`, `COMPLETED`, and `ARCHIVED`; the compatibility migration deliberately does not narrow that vocabulary.
- `ProjectStatus` models all three persisted values so existing completed rows remain accurately typed. `ProjectStatusUpdate` excludes `COMPLETED`: this application change does not add a new completion workflow or reinterpret legacy data.
- The project manager shows ACTIVE projects in the active list and COMPLETED projects in a separate completed section. Completed projects may be archived explicitly; archived projects remain outside these two sections, matching the existing behavior.
- The new-task project selector remains ACTIVE-only. Existing tasks linked to completed projects continue to display their project name because the dashboard's owner-scoped project lookup includes all statuses.
- Regression tests cover status grouping, COMPLETED filtering/preservation, and rejection of a new COMPLETED status update. No database migration or RLS change was made.

## Legacy checklist compatibility contract — 2026-11-19

### Runtime inventory

A branch-head audit inspected all 56 TypeScript/TSX/JavaScript files under `src/` and `lib/`, plus root `middleware.ts`. No runtime module references `task_checklist_items`. The current service in `src/lib/checklists.ts` uses only `checklist_items`; authenticated dashboard actions call `auth.getUser()` and pass the resolved user to that service. Service tests assert the canonical table and owner/task filters.

This establishes the repository's current client behavior only. It does not establish whether an older external or already-deployed client still calls the legacy table.

### Database behavior on the Organization branch

- `20260905170100_organization_v1_checklists.sql` creates `task_checklist_items` with RLS and authenticated owner-scoped SELECT/INSERT/UPDATE/DELETE policies. INSERT and UPDATE require the referenced task to belong to the authenticated owner.
- `20261117000200_harden_checklist_select_ownership.sql` additionally requires the referenced task to belong to the caller for SELECT visibility.
- `20261015000200_reconcile_checklist_tables.sql` performs a one-time copy of same-owner task rows into `checklist_items`. It preserves existing canonical IDs with `ON CONFLICT (id) DO NOTHING`.
- No migration installs a legacy-to-canonical synchronization trigger. A valid legacy write made after reconciliation is not guaranteed to appear in `checklist_items`; the read-only report identifies it as `missing_canonical`.

### Decision

1. `public.checklist_items` is the only supported table for current application code.
2. Keep `public.task_checklist_items` temporarily with its existing owner-scoped policies to avoid an unreviewed compatibility break for unknown older clients. It is a transitional compatibility surface, not a second source of truth.
3. Do not add dual-write/synchronization behavior, change legacy RLS/write permissions, or drop the legacy table in this audit. Those choices require an explicit compatibility window and owner approval.
4. Before a future sunset, inventory deployed clients and observe PostgREST/API logs for legacy-table reads/writes over an owner-approved window after the table exists in the target environment. Review every row returned by the conflict report against a complete backup restored in isolation.
5. A future deprecation should be staged: first restrict legacy writes through a reviewed forward migration while preserving a read/export window and rollback period; remove the table only in a separate later migration after the retention and rollback criteria are met.

### Current production limitation

As of the read-only inspection on 2026-11-19, the live project has 8 applied migrations and neither checklist table exists. Therefore production legacy-table traffic cannot yet be measured, and the branch's compatibility behavior is not deployed. The branch's 19-migration replay and mocked service tests do not replace a production backup restore or authenticated PostgREST isolation test.

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


## Decision — task relationship ownership preflight (2026-11-17)

- Task create and update services preflight any non-null project/parent relationship using the authenticated server-side Supabase client.
- A parent task must be visible to the authenticated owner, and the parent and child must use the same project (including both being unassigned).
- A project link must resolve to a project owned by the authenticated user.
- When an update changes either relationship field, the service first reads the current task's project/parent fields constrained by task ID and owner, then validates the effective resulting pair. This prevents omitted update fields from being treated as null.
- Direct self-parenting is rejected in the application layer. The existing database trigger remains authoritative for concurrent writes and indirect cycles; do not remove or weaken it.
- Six mocked-client tests assert the lookup filters and fail-closed behavior. They do not establish live RLS, trigger execution, or cross-user isolation.
- No schema, migration, RLS, or production data change is part of this decision.


## Verification — task relationship ownership preflight (2026-11-17)

- CI #153 passed on `9bdaa29e60afddc893a7e6fa5a1e43ee37469a7d`: 54 mocked/unit tests passed, TypeScript check passed, and production build passed; npm install audited 43 packages with 0 vulnerabilities.
- The tests cover application-level relationship lookup/query construction and fail-closed behavior. They do not establish PostgreSQL RLS, trigger execution, race behavior, or authenticated cross-user isolation.
- Live Supabase migration/schema inspection remains unavailable; no production migration or schema/data write was made.


## Decision — partial task relationship updates (2026-11-17)

- Resolve the effective task project/parent relationship before validating a partial update. If a field is omitted, retain its current database value; if it is explicitly `null`, treat that as an intentional unlink.
- Keep this resolution in a pure helper used by `updateTask` so its semantics can be regression-tested without importing the Next.js server runtime.
- Continue to run `assertTaskOrganizationLinks` against the resolved relationship using the authenticated owner. This does not replace the database trigger, which remains authoritative for races and indirect cycles.
- Two tests cover omitted-field preservation and explicit-null clearing. They verify application semantics only; they do not prove live RLS or trigger behavior.
- CI #156 passed on code head `b2526b832281e55c3feaaf854341dbf11af94e97`: 56 tests, typecheck, and production build passed.
- Live Supabase migration/schema inspection remains blocked by connection timeouts and advisor hibernation responses. No production migration or data/schema change was made.

## Live Supabase verification — 2026-11-17

Read-only inspection of project gujzvkyytxsnervovvrt now succeeds. The project reports ACTIVE_HEALTHY in ap-southeast-1 on PostgreSQL 17.11.0.003.

- All nine public application tables have RLS enabled. Exact row counts are zero in those tables, auth.users, and storage.objects.
- The live projects table has title, goal_id, priority, start_date, and target_date, but no name column. Its status constraint permits ACTIVE, COMPLETED, and ARCHIVED.
- The live tasks table already has project_id and parent_task_id foreign keys. The public task-organization validation trigger is absent.
- Neither checklist_items nor task_checklist_items exists in the live schema.
- Current project and task policies are legacy owner-wide policies. goals has overlapping owner-wide and command-specific policies.
- The live migration ledger contains eight core migrations. Their exact statements were recovered into version-matched repository files. The six Organization migrations remain unapplied.

The current schema therefore does not satisfy the Organization V1 application contract. In particular, project name compatibility, checklist tables, and the task relationship validation trigger are missing. Application-level owner checks do not replace the missing database enforcement for direct authenticated API writes.

The Free Plan does not include scheduled backups, and no manual logical backup has been produced. No production DDL, migration, RLS change, data write, or merge was performed.

## Decision — fail closed until backup and migration rollout are verified

- Keep PR #11 open and unmerged.
- Do not start Analytics V1.
- Produce a private schema/data/role dump and test its restore before production DDL.
- Reconcile the live migration ledger with repository files before applying Organization migrations.
- Test the Organization migration sequence against a disposable database matching the live legacy schema.
- Verify two-user RLS and direct API relationship isolation after the approved rollout.
- Review the current advisor findings before changing policies or indexes.



## Live production verification — 2026-11-17 11:49 IST

The following is a read-only snapshot of the live project, not a statement that Organization V1 has been deployed:

- Supabase project `gujzvkyytxsnervovvrt` reports ACTIVE_HEALTHY in `ap-southeast-1` on PostgreSQL `17.11.0.003`.
- The live migration ledger contains 8 applied core migrations. The 6 Organization migrations in this branch are not applied.
- All 9 public application tables have RLS enabled. Their exact row counts are zero; `auth.users` and `storage.objects` also have zero rows.
- Live `projects` has the legacy `title` column but no `name`. Neither canonical `checklist_items` nor legacy `task_checklist_items` exists.
- Live `tasks` has `project_id` and `parent_task_id` foreign keys, but the `validate_task_organization_links` trigger is absent.
- Security and health advisors return no lints. Performance findings remain: 4 unindexed foreign keys, 14 auth RLS initialization-plan warnings, 13 unused-index findings, and 4 overlapping permissive policies on `goals`.
- The Free Plan does not include scheduled backups. No manual logical backup or restore test has been completed.

**Security consequence:** current application services preflight project/parent ownership, but those checks do not protect direct PostgREST writes. Until the reviewed Organization migrations are applied and two-user direct-API tests pass, do not claim database-enforced project/parent relationship isolation in production.

## Hierarchy concurrency verification — 2026-11-17

The earlier static-review concern about concurrent hierarchy writes is addressed in the branch migration. The trigger acquires a transaction-scoped owner lock before relationship validation; owner transfers acquire both owner keys in deterministic order. Parent owner/project changes are rejected when they would leave existing direct children inconsistent.

CI #176 passed a PostgreSQL 17 two-session READ COMMITTED race: the second writer waits on the advisory lock and is rejected when its inverse edge would create a cycle. The fixture also checks direct self-parenting, foreign parents/projects, cross-project links, and invalid parent mutations.

CI #183 replayed the then-current 14-migration chain. CI #189 and #195 subsequently replayed all 15 local migrations in a disposable PostgreSQL 17 database and verified Organization RLS behavior with two authenticated test identities, including legacy checklist reconciliation and project title/name compatibility. These tests do not restore a production backup or exercise live Supabase/PostgREST; the Organization migrations remain unapplied in production.

## Decision — 2026-11-17

- Keep Organization V1 as the active milestone and keep PR #11 unmerged until backup/restore, disposable migration testing, trigger concurrency testing, and authenticated two-user direct-API isolation pass.
- Treat the current missing task relationship trigger and checklist tables as production authorization/data-integrity gaps, not merely pending UI work.
- Keep Analytics V1 queued until these Organization acceptance gates pass.


## Decision — serialize task hierarchy writes per owner (2026-11-17)

- The cycle-prevention trigger must serialize writes that can change `user_id`, `project_id`, or `parent_task_id`; otherwise two transactions can validate against incomplete ancestor chains and jointly form a cycle.
- The unapplied `20261015000300_prevent_task_hierarchy_cycles.sql` migration now acquires a transaction-scoped advisory lock in a dedicated key namespace using the owner UUID hash before any relationship validation. A transaction holds the lock until commit/rollback.
- Owner transfers acquire both old/new owner lock keys in deterministic integer-key order. Hash collisions can reduce concurrency by serializing unrelated owners, but cannot weaken validation.
- CI #173 runs the actual migration function against a disposable PostgreSQL 17 fixture and orchestrates two concurrent READ COMMITTED writers. It verifies that the second writer waits for the first transaction and then rejects the inverse edge as a cycle. The same fixture covers direct self-parenting, foreign parents/projects, cross-project links, and a sequential indirect cycle.
- CI #173 passed on `482e1921ada6bc723a65c167b3cbea72b916bcf4`: PostgreSQL integration passed, 56 application tests passed, typecheck and production build passed, and npm audit reported 0 vulnerabilities.
- This is not a test of the complete six-migration sequence, the live Supabase trigger, RLS, or two-user PostgREST isolation. The migration remains unapplied in production; backup/restore and full rollout gates still apply.

## Decision — preserve existing child links when a parent changes (2026-11-17)

- Validating only a task's proposed parent/project links is insufficient: moving a parent task to another project or owner can invalidate already-existing direct children.
- The cycle-prevention trigger now checks existing rows where `child.parent_task_id = new.id` and rejects a parent update if any child would no longer share the parent's owner and project.
- The same owner-scoped advisory transaction lock serializes parent changes and child relationship changes, so the check is not raced by a concurrent child update under READ COMMITTED.
- The PostgreSQL 17 integration fixture verifies both a parent project move and an owner transfer are rejected when a child would be left inconsistent. CI #176 passed this fixture, 56 application tests, typecheck, and production build; npm audit reported 0 vulnerabilities.
- This migration remains unapplied in production. The test does not prove full migration-chain compatibility, live RLS, or two-user PostgREST isolation.

## Direct API mutation isolation regression contract — 2026-11-17

The disposable PostgreSQL migration fixture now exercises both authenticated owners rather than only proving that a foreign row is hidden from SELECT:

- Seed one valid legacy checklist row for each owner and one malformed Owner A checklist row attached to Owner B's task.
- Replay the canonical checklist reconciliation migration; both valid rows must be copied, while the malformed association must be excluded.
- Under separate authenticated JWT subjects, verify each owner sees only its own projects, tasks, canonical checklist rows, and legacy checklist rows.
- As each owner, issue UPDATE and DELETE statements targeting the other owner's project, task, canonical checklist item, and legacy checklist item. Every statement must affect zero rows; both owners must still see their own rows afterward.

CI #207 passed this fixture on a9f73bfc26de818679c101974544793a839f2c74. This is a PostgreSQL 17 disposable-database test, not a live Supabase/PostgREST test. Production acceptance still requires a restore-tested backup and separate live JWT/API checks.


## Reciprocal direct-API relationship isolation — 2026-11-17

The disposable PostgreSQL migration fixture now tests both authenticated owner contexts for insert-time owner/link tampering and tests Owner B's relationship reassignment paths:

- Owner B cannot insert a project while claiming Owner A's user_id.
- Owner B cannot create a task linked to Owner A's project.
- Owner B cannot insert canonical or legacy checklist items attached to Owner A's task.
- Owner B cannot move its task to Owner A's project or parent task.
- Owner B cannot reassign its canonical or legacy checklist item to Owner A's task.
- Existing tests verify Owner A's corresponding insert/link attacks and reciprocal cross-owner UPDATE/DELETE denial for both owners.

The test catches the expected insufficient_privilege error and fails if the operation succeeds. [CI #209](https://github.com/mohith-krishnaa/personal-os/actions/runs/44064242592) passed the full 15-migration PostgreSQL 17 replay, hierarchy concurrency, 58 application tests, typecheck, and production build.

This does not establish live Supabase/PostgREST behavior. Production acceptance still requires a private backup that has been restored successfully and separate authenticated API checks against the live project or a verified restored snapshot.


## Checklist SELECT ownership invariant — 2026-11-17

Checklist visibility now requires two independent ownership conditions: the checklist row's user_id must equal auth.uid(), and the referenced task must also belong to auth.uid(). This is enforced for both public.checklist_items and the retained public.task_checklist_items table.

The extra task-owner predicate matters for malformed legacy rows. A row can carry a caller-owned user_id while referencing another user's task; row-owner-only SELECT policies would expose the foreign task UUID and associated checklist payload. The forward-only migration 20261117000200_harden_checklist_select_ownership.sql replaces both SELECT policies with owner-plus-task checks. It uses the ordinary authenticated role and the tasks table's own RLS policy; it does not introduce SECURITY DEFINER privileges or service-role access.

CI #211 verifies this against a disposable PostgreSQL 17 database by seeding malformed canonical and legacy rows for Owner A that reference Owner B's task. Owner A must not see either row, while valid rows remain visible. This does not replace live PostgREST JWT checks or the backup/restore gate.


## Anonymous-role isolation decision — 2026-11-17

Organization policies are intentionally granted to `authenticated`, not `anon`. The migration integration fixture now explicitly grants `anon` the same table-level SELECT/INSERT/UPDATE/DELETE privileges used by the authenticated test role, then switches to `anon` with an empty JWT subject. This prevents a false-positive test caused by missing SQL grants and verifies the RLS boundary itself: zero visible rows across projects, tasks, canonical checklists, and legacy checklists; denied inserts; and zero-row updates/deletes.

[CI #216](https://github.com/mohith-krishnaa/personal-os/actions/runs/44072614729) passed this check on disposable PostgreSQL 17 together with the full migration replay and existing authenticated owner-isolation tests. This does not establish live Supabase/PostgREST anonymous behavior; production API checks and the backup/restore gate remain required.


## Anonymous Organization CRUD denial matrix — 2026-11-17

The disposable migration fixture now verifies all four RLS operations for the anonymous role on each Organization table. It grants `anon` table-level SELECT/INSERT/UPDATE/DELETE privileges first, sets an empty JWT subject, and asserts: SELECT returns zero rows; INSERT is rejected; UPDATE affects zero rows; DELETE affects zero rows for `projects`, `tasks`, `checklist_items`, and `task_checklist_items`. This closes the earlier test-coverage gap where anonymous UPDATE and DELETE checks covered only a subset of tables.

Code commit [fba0eee](https://github.com/mohith-krishnaa/personal-os/commit/fba0eeeda2b824afd8525d9f941050dca08e6a6a) passed [GitHub Actions run 44082207231](https://github.com/mohith-krishnaa/personal-os/actions/runs/44082207231), including the full 16-migration PostgreSQL 17 replay, hierarchy concurrency, 58 application tests, typecheck, and production build. The result is not a live PostgREST test and does not satisfy the backup/restore gate.

## Foreign-key indexing contract — 2026-11-18

The pending migration chain already creates valid indexes for the Organization task relationships and the legacy project-to-goal relationship:

- `tasks.project_id` → `tasks_project_id_idx` (partial on non-null project IDs).
- `tasks.parent_task_id` → `tasks_parent_task_id_idx` (partial on non-null parent IDs).
- `projects.goal_id` → `projects_goal_id_idx` when the legacy `goal_id` column exists.

The migration replay assertions now verify that all three indexes exist, are ready, and are valid after the complete chain runs. These indexes are **not present in the live database yet**; the current performance advisor still reports those three foreign keys as unindexed until the pending migrations are approved and applied. `notifications.task_id` is the fourth live finding and is outside Organization V1; keep it tracked for reminder/production hardening rather than adding unrelated scope to this milestone.

This is a migration-test and architecture clarification only. It does not create or modify production indexes.


CI #222 passed the full 16-migration PostgreSQL 17 replay with valid/ready assertions for the three pending Organization/compatibility foreign-key indexes, hierarchy concurrency, 58 application tests, typecheck, and production build. This verifies the migration chain in a disposable database only; the read-only live probe confirms the indexes are still absent from production.


## Read-only rollout preflight coverage — 2026-11-19

The read-only `supabase/operations/organization-v1-preflight.sql` query 5 now includes `projects`, `tasks`, both checklist tables, `goals`, `reminders`, `notifications`, and `progress_entries`. This exposes the exact policy definitions relevant to the Organization rollout and the pending 14-policy initplan optimization, rather than omitting the reminder/progress policies from the operator's view.

The disposable migration bootstrap supplies only the minimal `supabase_migrations.schema_migrations(version, name)` catalog shape. After the full migration replay and RLS assertions, `supabase/tests/organization-migrations.sh` executes the exact read-only preflight SQL. This validates all preflight catalog queries against the replayed PostgreSQL 17 schema without contacting or mutating production. [CI #257](https://github.com/mohith-krishnaa/personal-os/actions/runs/44495009597) passed on the test commit, and [CI #261](https://github.com/mohith-krishnaa/personal-os/actions/runs/44495199082) passed on the exact PR head at this checkpoint. Both ran the full configured workflow, including migration replay, preflight execution, hierarchy concurrency, application tests, typecheck, and production build.


## Checklist reconciliation conflict semantics — 2026-11-19

The reconciliation migration is intentionally non-overwriting: `ON CONFLICT (id) DO NOTHING` preserves an existing canonical checklist row. If the same ID exists in both tables with different owner/task/payload values, the canonical row wins and the legacy row remains in `task_checklist_items`; it is not copied into `checklist_items`. This avoids cross-owner overwrite but leaves a legacy item outside the application-facing canonical table. Such rows require explicit review and must not be described as fully reconciled.

The post-migration, SELECT-only `supabase/operations/checklist-reconciliation-conflicts.sql` reports these mismatches. It is separate from the general preflight because the general preflight must remain runnable before the checklist tables are created. CI #290 seeds a cross-owner same-ID collision and verifies canonical preservation, legacy-source preservation, and owner-specific RLS visibility. This is disposable PostgreSQL evidence only; live checklist tables are currently absent.


## Checklist reconciliation is a one-time copy, not ongoing synchronization

The forward reconciliation migration copies valid same-owner legacy rows into `public.checklist_items` once. It intentionally uses `ON CONFLICT (id) DO NOTHING` to avoid overwriting a pre-existing canonical row, and it retains `public.task_checklist_items`. It does not install a trigger that mirrors future legacy writes into the canonical table.

Consequences:
- A valid legacy row written after the migration can remain absent from the canonical table.
- A same-ID collision can leave the legacy source row outside the current application's canonical checklist workflow.
- The read-only post-migration conflict report classifies unresolved rows as `missing_task`, `task_owner_mismatch`, `missing_canonical`, or `canonical_id_collision`.
- The report is diagnostic only. It does not transfer ownership, overwrite either record, delete legacy data, or repair rows.

CI #293 verifies a post-migration legacy-only write and confirms the report detects it as `missing_canonical`. This is disposable PostgreSQL evidence, not live PostgREST or production acceptance.

Before adding ongoing synchronization or freezing legacy writes, inspect every deployed/runtime caller, define the supported compatibility window and conflict semantics, and test the chosen forward/rollback plan against a restored snapshot. Do not infer that retaining the legacy table provides bidirectional compatibility.



## Checklist task foreign-key integrity assertion — 2026-11-19

Both the canonical `checklist_items` table and retained legacy `task_checklist_items` table define `task_id` as NOT NULL with a foreign key to `public.tasks(id) ON DELETE CASCADE`. The disposable full-chain assertion now verifies these exact invariants after migration replay: the column remains NOT NULL, the FK is single-column on `task_id`, references `public.tasks`, is validated, and retains cascade-delete behavior. This matters because the conflict report's `missing_task` category is a defensive signal for schema/constraint drift; it should not be an ordinary data state when the expected FK is valid. No migration was added or changed, and the migration count remains 18. CI #296 passed on code/test commit `7e3d75f46214d078cfc1d4ba7a416584127aa05b`, and CI #297 passed on documentation head `ab6a3381109d50496e1171494f9191f304b03298`; both ran the complete configured migration, RLS, hierarchy, 58-test, typecheck, and production-build workflow.

## Project/task/checklist FK contract verification — 2026-11-19

The migration replay now verifies five exact foreign-key contracts:

- `tasks.project_id -> projects.id ON DELETE SET NULL`
- `tasks.parent_task_id -> tasks.id ON DELETE CASCADE`
- `projects.goal_id -> goals.id ON DELETE SET NULL`
- `checklist_items.task_id -> tasks.id ON DELETE CASCADE`
- `task_checklist_items.task_id -> tasks.id ON DELETE CASCADE`

For both checklist tables, the assertion requires `task_id` to be NOT NULL and participate in exactly one FK; that FK must be a validated single-column reference to `public.tasks(id)` with CASCADE deletion. The source-column count includes composite FKs as well as single-column FKs. A disposable negative test adds a second, NOT VALID FK from each checklist `task_id` to `auth.users(id)`, reruns the assertion, requires the exact contract error, and lets the failed connection roll back the test transaction.

Read-only preflight query 11 reports all five relationships, exact target columns, validation state, delete behavior, and the count of every FK involving each source column. [CI #302](https://github.com/mohith-krishnaa/personal-os/actions/runs/44563968200) passed on exact code head `f0c8a250c617b7bb3342671275582b78a9dab781`: 18-migration PostgreSQL 17 replay, RLS assertions, preflight, negative FK test, checklist conflict report, hierarchy concurrency, 58/58 application tests, typecheck, and production build. This remains disposable-database verification; the checklist tables are absent from production.


## Project/task foreign-key recovery guard — 2026-11-19

The earlier Organization migration conditionally adds project/task FKs when it cannot find any FK whose definition mentions the source column. A drifted schema could therefore contain a wrong or composite FK and cause the original migration to skip the required relationship. The branch-only `20261119000300_ensure_project_task_foreign_keys.sql` now closes that gap after the existing migration sequence.

The guard accepts exactly one FK per source column when it targets the specified single target column and has the specified delete action. It creates the expected FK only when no FK uses the source column, validates an exact but unvalidated FK, and fails closed when any conflicting, duplicate, or composite FK is present. It does not drop or rewrite constraints; unexpected definitions require operator review. CI #309 verifies idempotent replay, missing-FK repair, NOT VALID validation, and conflict rejection on disposable PostgreSQL 17.

This guard is branch-only and is not authorization to apply production DDL. Production still requires a complete owner-controlled schema/data/roles backup restored successfully in isolation, followed by authenticated two-user PostgREST CRUD and isolation tests.


## Project archive lifecycle and active task links — 2026-11-20

- A project status of `COMPLETED` or `ARCHIVED` is terminal for new task assignment. New task INSERTs and actual changes to `tasks.project_id` or task ownership must resolve to an ACTIVE project owned by the task owner.
- The database trigger `require_active_project_for_new_task_links` is SECURITY INVOKER and runs before task INSERT or updates to `user_id`/`project_id`. It uses a `FOR SHARE` row lock so project status changes and task-link creation/reassignment serialize. The existing `validate_task_organization_links` trigger remains responsible for owner and hierarchy validation.
- An unchanged historical project link is not a new assignment. Archiving/completing a project does not detach tasks; existing task content and same-project parent maintenance remain available. The dashboard still loads the full owner-scoped project list so existing task labels resolve for archived projects.
- The task editor and server preflight expose only ACTIVE projects for new links. Direct authenticated PostgREST writes are covered by the database trigger, not just the UI filter.
- Recurring task completion does not create another occurrence for a COMPLETED/ARCHIVED project. If a project is archived concurrently after the application read, the dedicated check-violation is treated as the expected end of that recurrence; unrelated insert errors still propagate.
- `supabase/tests/project-archive-lifecycle.sql` verifies preserved links, allowed existing-task edits/parent maintenance, rejected new tasks/reassignments into inactive projects, and accepted ACTIVE assignments. The migration runner replays and reapplies the migration to verify idempotence. The row-lock race itself is a separate pending two-session regression.


## Direct subtask INSERT lifecycle regression — 2026-11-20

- `supabase/tests/project-archive-lifecycle.sql` now tests direct database subtask INSERTs that bypass application preflight. A subtask under an ACTIVE project succeeds and retains its exact project and parent IDs; equivalent INSERTs under COMPLETED and ARCHIVED projects fail with the expected check violation and leave no task row.
- The fixture verifies an existing child remains attached to its archived project and parent. Existing foreign-owner, cross-project parent, self-parenting, and hierarchy-cycle checks remain in `organization-task-hierarchy.sql` and the concurrency runner.
- The full migration runner already executes the lifecycle fixture after replay; no migration-count or workflow change was needed. The branch remains at 20 migrations. CI #354 passed on code/test commit `91075f588cd42f88b7014bb7e8d9eab8a32e3ab6`.
- Fresh read-only production inspection still shows 8 live migrations, legacy `projects.title/status`, task project/parent columns, RLS enabled on projects/tasks, and no user-defined triggers on those live tables. The active-project trigger is branch-only. No production DDL, migration, RLS change, backup, restore, or merge occurred.
- Next: verify the same inactive-project subtask behavior through the authenticated role in the two-owner migration fixture, while retaining existing owner/parent relationship denial assertions. Production rollout remains gated by a complete owner-controlled schema/data/roles backup and isolated restore, checklist conflict review, and authenticated two-user PostgREST CRUD/isolation.
