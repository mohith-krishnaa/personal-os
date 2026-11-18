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
