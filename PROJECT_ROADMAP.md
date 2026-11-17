# Personal OS — Project Roadmap & Mind Map

> Single source of truth for project direction. Verify GitHub/Supabase/CI before making claims.
> Last reconciled: 2026-11-17. Code-bearing head `3c23e01e3574b4fc91d15a1929e7c5e37eb16988` passed CI #189; the project-state/roadmap/handoff/runbook documentation checkpoint `ef49a03e948e27617f5522beb1370167e936555b` passed CI #195. Both verified full 15-migration replay, authenticated two-owner RLS, hierarchy concurrency, 58 tests, typecheck, production build, and npm audit with 0 vulnerabilities. This roadmap refresh is documentation-only.

## Current position

**Completed:** Core productivity, Recurring Tasks V1, and Reminders V1. Progress & Streaks V1 application code exists, but live schema compatibility is pending a forward-only repair; do not treat its production data contract as verified yet.

**In progress:** Organization V1 remains the highest-priority incomplete milestone on `feature/organization-v1`; production acceptance is still blocked. The branch now replays all 15 local SQL migrations and tests two-owner RLS behavior in disposable PostgreSQL 17; CI #189, #191, and #195 passed. Live Supabase is ACTIVE_HEALTHY in ap-southeast-1 on PostgreSQL 17.11.0.003 with 8 applied migrations and 7 local-only migrations pending (6 Organization + 1 Progress compatibility repair). Live `projects` has `title` but no `name`; both checklist tables and the task validation trigger are absent; `goals` lacks `unit` and `target`. All 9 public application tables have RLS enabled and zero rows. The Free Plan has no scheduled backups and no manual logical backup/restore test exists. No production changes were made. Analytics remains queued until a private backup/restore and authenticated direct-API isolation against the restored snapshot pass.

## Mind map

```text
PERSONAL OS
│
├── CORE PRODUCTIVITY [DONE]
│   ├── Authentication / Dashboard / Tasks
│   ├── Status / Priority / Duration
│   ├── Activity events
│   └── Day / Week / Month calendar
│
├── TIME & SCHEDULING [PARTIAL]
│   ├── Due date/time [DONE]
│   ├── Scheduled start/end [DONE]
│   ├── Recurring tasks [DONE — PR #5]
│   ├── Reminders [DONE — PR #7]
│   └── Conflict-aware scheduling [LATER]
│
├── GOALS & PROGRESS [IMPLEMENTED — LIVE SCHEMA REPAIR PENDING]
│   ├── Generic measurable goals
│   ├── Custom units
│   ├── Progress history
│   ├── Current + longest streaks
│   └── Batched dashboard loading
│
├── ORGANIZATION [IN PROGRESS — production rollout gated]
│   ├── Projects
│   ├── Subtasks
│   ├── Checklists
│   └── Core organization workflows
│
├── ORGANIZATION EXTENSIONS [DEFERRED]
│   ├── Notes / advanced tags
│   └── Attachments (evaluate separately)
│
├── ANALYTICS [PLANNED]
│   ├── Daily / Weekly / Monthly reviews
│   ├── Planned vs actual time
│   ├── Completion + progress trends
│   └── Behavioral insights
│
├── AI ASSISTANT [LATER]
│   ├── Brain dump → tasks
│   ├── Task breakdown
│   ├── Daily briefing / review
│   └── Validated tool-based actions
│
├── RESEARCH AGENT [LATER]
│   ├── Web research
│   ├── Source extraction
│   └── Source-backed resources
│
└── ADAPTIVE PERSONAL OS [FUTURE]
    ├── Learn actual duration
    ├── Detect overload/procrastination
    ├── Predict workload
    └── Adapt schedules from behavior
```

## Execution order

1. Recurring Tasks V1 — DONE
2. Reminders V1 — DONE
3. Progress & Streaks V1 — implementation exists; live `goals.unit`/`target` repair pending
4. **Organization V1 — IN PROGRESS (15-migration replay and simulated two-owner RLS pass; production backup/restore and live API gates pending)**
5. Analytics V1
6. AI Assistant V1
7. Research Agent V1
8. Adaptive Scheduling
9. Production hardening

## Definition of done — every feature

1. Data model/schema
2. Authorization/RLS
3. Backend/application logic
4. Edge cases/failure states
5. Unit/integration/regression tests
6. UI/UX
7. CI/build
8. Migration/recovery implications
9. Documentation + `PROJECT_STATE.md`

## Quality rules

- PostgreSQL/Supabase is the source of truth for persisted data.
- Never invent schema or authorization behavior.
- Preserve activity history for future analytics/adaptive scheduling.
- AI uses validated application tools rather than direct database writes.
- Merge only after CI is green.
- Security/performance findings are fixed or explicitly tracked.
- Project state must be reconciled after each milestone.

## Current engineering priorities

### P0 — Product correctness
- Keep `main` green.
- Verify authentication and owner isolation.
- Maintain regression coverage for task, recurrence, reminder and progress flows.
- Live Supabase `public.goals` lacks `unit` and `target`, while the dashboard progress service selects both on every load. A forward-only migration and null-safe legacy rendering are now branch-tested; production compatibility remains pending backup and migration approval.

### P1 — Organization V1
- PR #11 is the intended Organization V1 review path. This automation run did not merge it; recheck the live PR page for current state/head before any merge. PR #12 was previously marked as a superseded draft; do not merge it separately.
- Application implementation includes owner-scoped projects/tasks, task/project association, subtasks, checklists, dashboard failure-state recovery, and task relationship preflight. Partial relationship updates preserve omitted links and honor explicit null unlinks.
- [CI #176](https://github.com/mohith-krishnaa/personal-os/actions/runs/44038758029) passed on `d872a6e6f530a9ee87e8851a1cf5465197240379`: PostgreSQL 17 hierarchy integration test, 56/56 application tests, TypeScript check, production build, and 0 npm audit vulnerabilities. No lint script/configuration exists.
- [CI #189](https://github.com/mohith-krishnaa/personal-os/actions/runs/44047023836) passed on code head `3c23e01e3574b4fc91d15a1929e7c5e37eb16988`; [CI #191](https://github.com/mohith-krishnaa/personal-os/actions/runs/44047078890) passed on documentation head `d7c5fc12b40afc1f69b28591bca0db0c77039ce9`. Both replayed all 15 local SQL migrations in disposable PostgreSQL 17, checked legacy checklist reconciliation, project title/name dual-write, authenticated two-owner RLS isolation, hierarchy concurrency, 58/58 tests, typecheck, production build, and 0 npm audit vulnerabilities.
- Live Supabase read-only inspection now succeeds. The exact eight applied core migration statements have been restored into version-matched repository files; the duplicate non-ledger reminder migration was removed. Six Organization migrations and one Progress compatibility migration remain local-only.
- Live schema gap: projects has title but no name; checklist_items and task_checklist_items are absent; tasks has project/parent foreign keys but no Organization validation trigger; goals lacks the `unit` and `target` columns required by the branch's Progress V1 query. The branch migration now defines the owner-locking trigger function and rejects parent changes that would invalidate existing children, but it remains unapplied. All nine public application tables have RLS enabled and zero rows; auth.users and storage.objects also have zero rows.
- Security and health advisors report no lints. Performance findings: 4 unindexed foreign keys, 14 auth_rls_initplan warnings, 13 unused-index findings, and 4 overlapping permissive-policy findings on goals.
- Recovery remains blocked: Free Plan has no scheduled backups and no manual logical backup exists. No production DDL, migration, RLS change, data write, or merge was performed.
- Next: create and restore-test a private schema/data/role backup; test the full six-migration sequence against a disposable database matching the live schema; verify authenticated two-user CRUD and direct API relationship isolation; then re-run advisors and current-head CI before any production rollout or merge. A focused PostgreSQL 17 test now verifies the trigger function's owner lock and concurrent cycle rejection, but does not replace the full-chain or live RLS tests.
- Do not start Analytics until Organization V1's recovery, migration, database authorization, and authenticated isolation acceptance criteria are verified.
### P2 — Production hardening
- Review foreign-key indexes and query performance.
- Complete timezone/DST semantics for reminders when scheduling requirements are defined.
- Add observability and recovery documentation.

## Branch map

- `main` — stable integrated product.
- Historical feature branches remain for traceability; do not treat them as current work unless GitHub confirms an active PR.

## Decision log

- 2026-08-30: Established persistent project-state hierarchy and mind tree.
- 2026-08-30: Scheduler/calendar integrated.
- 2026-08-30: Progress/streaks designed as a generic system rather than book-specific logic.
- 2026-09-05: Recurring Tasks V1, Reminders V1 and Progress & Streaks V1 verified as merged.
- 2026-09-05: Security issue #6 remediated and closed; security verification reported 0 lints.
- 2026-09-05: Organization V1 promoted to the next roadmap milestone.
- 2026-11-17: Keep Organization V1 fail-closed until a private logical backup is restore-tested, the six unapplied migrations are exercised against a disposable database, concurrent hierarchy-cycle behavior is tested, and authenticated two-user direct-API isolation passes. Free Plan scheduled backups are unavailable.


## Historical checkpoint — 2026-10-16

- Organization V1 implementation is under review in PR #11 (`feature/organization-v1`), not yet merged.
- GitHub Actions run #95 passed after the checklist migration was made repeat-safe, and run #96 passed `npm install`, `npm run test`, and `npm run build` on docs commit `04b185b0afc744a61b0a20ad5a7b169874952dd1` (https://github.com/mohith-krishnaa/personal-os/actions/runs/38873921256). Re-check CI against the current PR head before merge. Organization RLS policies use `(select auth.uid())`; the compatibility migration conditionally indexes legacy `projects.goal_id` when present. Live database rollout and authenticated end-to-end CRUD/isolation checks remain pending.
- Live database access is restored for the intended Supabase project `gujzvkyytxsnervovvrt` (`puttamohithkrishnaa@gmail.com's Project`, ACTIVE_HEALTHY). The live ledger does not yet include Organization V1 migrations; `projects` has legacy `title` and supports `COMPLETED` status.
- Next steps: finish migration review; plan a safe rollout with recovery checks; apply/verify migrations only after preflight; run Supabase security/performance advisors; then exercise authenticated owner-isolation and CRUD flows. Do not mark Organization V1 complete until these checks pass.
- Scope after Organization V1: Analytics V1, AI Assistant V1, Research Agent V1, Adaptive Scheduling, and production hardening. Each milestone needs schema/RLS, application logic, edge-case tests, UI, CI, and recovery documentation.


## Current checkpoint — 2026-11-16

- GitHub confirms PR #11 is open, unmerged, non-draft, and mergeable. The branch is `feature/organization-v1`, targeting `main`; the verified head at checkpoint start was `aa26a556cd6627a0ccd19efd914fe62be76f0ed9`.
- CI run #104 (ID `43928396020`) passed on commit `f2b9e43564663c74ac51e7f1e2356163633e21c3`: install, tests, explicit typecheck, and production build all succeeded. The following documentation refresh triggers a new CI run; verify the latest head before merge.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but migration listing, table introspection, read-only SQL, and advisor calls time out; advisors also report the project as hibernated. The live migration ledger and schema are currently unknown.
- No migrations or production data changes were made. The next safe action is to restore supported DB connectivity, inspect the live ledger/schema, confirm backup/recovery readiness, then apply reviewed migrations and test authenticated owner isolation.
- Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain behind Organization V1 in the execution order.

## Decision log

- 2026-11-16: Keep Organization V1 as the active milestone. Do not infer live schema from repository migrations or stale October notes.
- 2026-11-16: Do not apply production DDL, create a replacement database, or merge PR #11 while the live migration ledger/schema and authenticated isolation behavior are unverified.
- 2026-11-16: Make TypeScript checking an explicit CI step (`tsc --noEmit`) rather than relying only on the Next.js production build to surface type errors.


## Current checkpoint — 2026-11-17

- PR #11 remains the active Organization V1 review: open, unmerged, non-draft, and mergeable status must be rechecked live before any merge. PR #12 is still an open draft explicitly marked superseded by PR #11; do not merge it separately.
- CI run #115 (ID `43938573918`) passed on PR head `91cd88fedef768a65286381c361b72f46d67ee29`: dependency installation, `npm run test`, `npm run typecheck`, and `npm run build` all succeeded. The run includes the new project owner-boundary tests.
- Added `docs/architecture/organization-v1.md` to record ownership boundaries, compatibility decisions, migration/recovery rules, and verification limits.
- Added service-level regression coverage proving project creation derives `user_id` from the authenticated session, updates filter by both project ID and authenticated owner, and unauthenticated updates stop before database access. These mocked-client tests do not prove live RLS or cross-user database isolation.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but repeated migration listing and verbose table inspection still fail with database connection timeouts. Read-only SQL probes time out, and advisor calls report the project as hibernated. The live migration ledger and schema remain unknown.
- No production migrations, schema changes, data changes, or PR merge were performed. Do not start Analytics until Organization's live schema, RLS, CRUD, recovery, and CI gates are verified.
- No lint script or linter configuration exists in the repository; lint is not a verified check.
- Next action: restore supported Supabase database access, inspect the live migration ledger and Organization tables, confirm recovery readiness, then continue authenticated CRUD and cross-user isolation testing.

Architecture note: [docs/architecture/organization-v1.md](docs/architecture/organization-v1.md).


## Current checkpoint — 2026-11-17 (subtask visibility)

- PR #11 remains open and unmerged; PR #12 remains an open draft superseded by PR #11.
- Added an authenticated `listSubtasksAction`. It resolves the current user server-side, validates ownership of the parent task, and reads children filtered by both `user_id` and `parent_task_id`.
- Updated the dashboard subtask panel to load children only when expanded, display their completion state, and toggle completion through the existing task-status server action. Existing create behavior remains available.
- Added service tests proving the child query includes both owner and parent filters and that a foreign-owned parent is rejected before child listing.
- CI run #120 (ID `43947823009`) passed on implementation commit `b8a686664e5e39b2ebc042192a9ea291c6d1bec7`: 33 tests passed, typecheck passed, production build passed, and npm audit reported 0 vulnerabilities. Documentation changes after that commit require the current PR head's checks to remain green.
- Lint remains unavailable because the repository has no lint script/configuration.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but migration listing, verbose table introspection, and read-only SQL still time out; security/performance advisors report hibernation. The live schema and migration ledger remain unknown.
- No production migration, schema/data write, or PR merge was performed.

Decision: keep Organization V1 active; do not begin Analytics or merge until live schema/RLS, recovery readiness, migration rollout, advisors, and authenticated cross-user CRUD are verified.


## Current checkpoint — 2026-11-17 (subtask create/list consistency)

- Live GitHub inspection confirms PR #11 is open, unmerged, non-draft, and mergeable; current pre-change head was `b466ee0ba32cae5b4a1763db50360a69e132ca28`. PR #12 remains an open draft explicitly superseded by PR #11.
- Found a UI state bug: if the initial lazy-load failed and the user then created a subtask, the component marked its partial local list as fully loaded. That hid any pre-existing subtasks until a page refresh.
- Added a small state transition helper. After creation, an already-loaded list is appended locally; an incomplete list remains marked incomplete and is refreshed through the authenticated owner-scoped read action. A failed refresh keeps the created row visible and leaves retry available.
- Disabled the Add control during an in-flight list read to prevent overlapping read/create races.
- Added regression tests for both loaded and incomplete list transitions. CI run #122 (ID `43959430815`) passed on implementation commit `3de585c8a2ba7e511f50ed0cd0be8c37d9bd1bf2`: 35/35 tests, typecheck, and production build passed; npm install reported 0 vulnerabilities. Lint is unavailable.
- No database schema or authorization behavior changed.
- Live Supabase database calls continue to fail; live migration ledger/schema remain unknown. No migration, production data/schema write, or PR merge was performed.


## Verification follow-up — 2026-11-17

- CI run #122 passed on the subtask create/list consistency implementation commit: 35 tests passed, typecheck passed, production build passed, and npm install reported 0 vulnerabilities.
- A documentation-only reconciliation follows that implementation commit; verify the resulting latest PR head's CI before merge.


## Current checkpoint — 2026-11-17 (checklist consistency)

- Organization V1 remains the active milestone in PR #11. PR #12 remains an open draft superseded by PR #11.
- Fixed a checklist UI consistency defect: creating an item after a failed list read previously displayed only the newly created row and could hide pre-existing rows. The component now refreshes the authenticated checklist list when the prior read was incomplete, retains the new row if refresh fails, exposes retry, and blocks create while loading.
- Added `src/lib/checklist-state.ts` and three regression tests for canonical ordering and incomplete-list recovery. No schema or authorization behavior changed.
- The checklist service continues to use `public.checklist_items`, verifies task ownership, and filters records by authenticated `user_id` and `task_id`.
- Latest code changes require CI verification on the current PR head. Lint remains unavailable because the repository has no lint script/configuration.
- Supabase metadata reports `ACTIVE_HEALTHY`, but live migration listing and verbose table introspection timed out again. Live schema/ledger remain unknown; no migrations or production writes were performed.
- Next priority remains database inspection and safe Organization rollout, not Analytics. Do not merge PR #11 until live schema/RLS, recovery readiness, advisors, authenticated CRUD, cross-user isolation, and current-head CI are verified.


## Verification checkpoint — 2026-11-17 (checklist recovery)

- PR #11 remains the active Organization V1 implementation; PR #12 remains superseded.
- Checklist create/list recovery is implemented and covered by three new tests. A create after an incomplete list read refreshes the authenticated canonical list, retains the created row if refresh fails, and keeps retry available. Loaded lists preserve server ordering.
- CI #128 (ID `43969545168`) passed on head `4bb083fe94fd36419f47149c3951bc9b594c98aa`: 38 tests passed, typecheck passed, production build passed, and install reported 0 vulnerabilities.
- Lint remains unavailable. Supabase metadata is `ACTIVE_HEALTHY`, but live migration/table/SQL/advisor calls fail with timeout or hibernation responses; live schema and ledger remain unknown.
- No production migration, data change, or merge was performed. Organization remains the priority; Analytics stays queued until live schema/RLS, recovery, migration, advisor, authenticated CRUD, and cross-user isolation gates pass.


## Verification checkpoint — checklist ownership coverage (2026-11-17)

- Added four service-level regression tests for checklist task-owner validation, list filters/order, foreign-task rejection, owner assignment on insert, and owner-scoped completion/deletion mutations.
- No production service, UI, schema, migration, RLS policy, or credential behavior changed in this task; only `src/lib/checklists.test.ts` changed.
- Current PR #11 head is `adfffa6f5e125ff9224e618a89ec177144663c9f`. CI #131 (ID `43978680326`) was queued at last check; test/typecheck/build results for this commit are pending.
- CI #130 passed on the parent head with 38 tests, typecheck, production build, and 0 npm audit vulnerabilities.
- Supabase project metadata is `ACTIVE_HEALTHY`; migration listing, verbose table inspection, and read-only SQL timed out. Security/performance/health advisors report hibernation. Live schema and migration ledger remain unknown.
- No production DDL, data changes, or PR merge occurred.

Organization remains the active milestone. Analytics must not start until live schema/RLS, recovery, migration, advisor, authenticated CRUD, and cross-user isolation gates are verified.


## Latest verification — checklist ownership regression coverage (2026-11-17)

- Added four checklist service tests for owner/task list filters, foreign-task rejection, owner assignment on create, and owner-scoped completion/deletion.
- CI #135 passed on current PR #11 head `bc82493c8c5533148e3d82aaf667374fd33b9ee1`: 42 tests passed, 0 failed; typecheck and production build passed; install audited 43 packages with 0 vulnerabilities.
- Initial CI #131/#132 failures were caused by missing imports in the new test file. The import correction is included in the verified head.
- Supabase project metadata remains `ACTIVE_HEALTHY`, but live migration/table/SQL calls time out and advisors report hibernation. Live schema and migration ledger remain unknown.
- No production database changes or PR merge occurred. Organization remains in progress; Analytics remains blocked behind its production acceptance gates.

- 2026-11-17: Failed subtask-list refreshes now mark the client list incomplete while retaining visible rows; the next create forces a canonical reload. Regression coverage passed in CI #140 (43 tests, typecheck, production build). This is a UI consistency rule, not an authorization or RLS substitute.


## Organization V1 checkpoint — authenticated project-list boundary (2026-11-17)

- PR #11 remains the active Organization V1 work; PR #12 is a superseded draft. main is 2b42dd17796b75dca79434a81d4e1f0cbf0fa043 and the pre-change PR #11 head was dd18922b228f0bb44a6a01e404e33d3b4d0444bd.
- Added explicit server-side caller resolution and user_id filtering to listProjects. Optional status filtering and descending creation ordering are unchanged. Added tests for owner/status filtering and fail-closed unauthenticated reads.
- Latest prior CI #142 passed on the pre-change head; CI for this new code is pending. Lint remains unavailable because the repository has no lint script/configuration.
- Supabase metadata reports ACTIVE_HEALTHY, but migration listing, verbose table introspection and read-only SQL time out; advisors report hibernation. Live schema and applied migration ledger remain unknown. No production DDL/data change was made.
- Highest-priority remaining work remains database connectivity, live ledger/schema inspection, recovery readiness, safe migration review, advisors, and authenticated two-user CRUD/isolation. Analytics remains blocked behind Organization V1 acceptance.

## Verification — authenticated project-list boundary (2026-11-17)

- CI #143 passed on the code-bearing commit 1106efd1b3a1be9e3b5aac18bd8a6e714476cb9f: 45/45 tests, typecheck, production build, and install audit output with 0 vulnerabilities.
- CI #144 passed on documentation checkpoint 2c618299c5bd3db2bf03aad7f4afecc6ab2521a7: 45/45 tests, typecheck, production build, and install audit output with 0 vulnerabilities.
- No lint script/configuration exists. The live Supabase migration ledger/schema remain unverified because migration/table/SQL operations time out and advisors report hibernation despite ACTIVE_HEALTHY project metadata.
- Organization V1 remains incomplete. Do not advance to Analytics until live database inspection, recovery readiness, migration review/rollout, advisors, authenticated CRUD and two-user RLS isolation pass.


## Task-list ownership boundary — 2026-11-17

- Organization task reads now apply an explicit application-level owner filter in addition to PostgreSQL RLS.
- `listTasks` resolves the user with `auth.getUser()` on the same server-side Supabase client used for the query and fails closed when the session is missing or invalid.
- The extracted `listTasksForUser` query applies `user_id = authenticated user id`, preserves the optional project filter, and retains the existing due-date ascending / creation-time descending ordering.
- Added three mocked-client tests for owner + project filtering, optional project filtering, and rejecting a missing owner before database access. These tests verify query construction only; they do not prove PostgreSQL RLS or two-user isolation.
- Code-bearing commit `8f5eac4fd9d314a9fb3125de46789fe7858beac3` passed CI #150 (run ID `44002396846`): 48 tests passed, 0 failed; TypeScript check and production build passed; npm install audited 43 packages and reported 0 vulnerabilities.
- No lint script or linter configuration exists. No schema, migration, RLS policy, privilege, production data, or production infrastructure was changed.
- Fresh Supabase inspection: project metadata remains `ACTIVE_HEALTHY`, while migration listing, verbose public-table introspection, and a read-only information_schema query time out. Security, performance, and health advisor calls report the project as hibernated. The live migration ledger and schema remain unknown.
- PR #11 remains open and unmerged; PR #12 remains an open draft explicitly superseded by PR #11. The live PR page is authoritative for the current documentation head.
- Next safe action: restore supported database connectivity, inspect the actual migration ledger and Organization tables, confirm backup/recovery readiness, then run authenticated CRUD and cross-user isolation against the live database before migration rollout or merge.


## Engineering checkpoint — task relationship ownership preflight (2026-11-17)

- Organization V1 remains the active milestone.
- Task creation and relationship-changing updates now preflight project and parent ownership through the authenticated server-side Supabase client. Parent and task must belong to the same user and project; direct self-parenting is rejected before the write.
- The PostgreSQL validation trigger remains the authoritative protection against races and indirect cycles. The new checks are defense in depth, not a replacement for RLS/constraints.
- Six mocked-client tests were added. They do not verify live PostgreSQL RLS or cross-user isolation. CI for the new PR head is pending.
- The live Supabase migration ledger/schema remains unknown: project metadata is ACTIVE_HEALTHY, but migration listing, verbose table introspection and read-only SQL time out; advisors report hibernation.
- Next: verify current-head CI; restore database access; inspect actual migrations/schema; confirm backup/recovery; then complete authenticated CRUD and two-user isolation. Analytics remains blocked behind Organization V1.


## Verification checkpoint — task relationship ownership preflight (2026-11-17)

- Organization V1 remains the highest-priority incomplete milestone.
- Task creation and relationship-changing updates now validate project/parent ownership in application code before writing. The current task relationship is loaded with task ID + owner filters when an update changes either relationship field.
- Six new mocked-client tests cover valid links, foreign parent, cross-project parent, foreign project, direct self-parent, and missing owner.
- [CI #153](https://github.com/mohith-krishnaa/personal-os/actions/runs/44009478456) passed on code-bearing commit `9bdaa29e60afddc893a7e6fa5a1e43ee37469a7d`: **54 tests passed, 0 failed**; `npm run typecheck` and `npm run build` passed; `npm install` audited 43 packages and reported 0 vulnerabilities. No lint script or linter configuration exists, so lint remains unavailable.
- The database trigger remains authoritative for concurrent writes and indirect hierarchy cycles. These tests do not prove live RLS or two-user isolation.
- Live Supabase migration/schema inspection remains blocked by connection timeouts and advisor hibernation despite project metadata reporting ACTIVE_HEALTHY. Do not merge or begin Analytics until this is resolved and the remaining Organization acceptance criteria pass.


## Latest live database checkpoint — 2026-11-17

Read-only access has recovered. The live ledger contains eight applied core migrations and the repository now contains exact versioned copies of their SQL statements. The six Organization migrations are still unapplied. The live schema has the legacy project title field, no checklist tables, and no Organization task-link trigger. The Free Plan has no scheduled backup and no manual backup has been created. See [Organization V1 preflight and recovery runbook](docs/operations/organization-v1-preflight.md) and [read-only SQL preflight](supabase/operations/organization-v1-preflight.sql).

CI #163 through #168 passed on successive migration/documentation checkpoints; each run completed 56 tests, typecheck, production build, and 0 npm audit vulnerabilities. Latest verified documentation checkpoint: 0fe10995fbd3d5cb2e74c5a07d2257bc8ff623cc; the live PR page is authoritative for any later docs-only head. Organization remains the active milestone; Analytics is not started.


## Latest engineering checkpoint — concurrent task hierarchy protection (2026-11-17 12:47 IST)

- Updated the unapplied `20261015000300_prevent_task_hierarchy_cycles.sql` migration to acquire an owner-scoped transaction advisory lock before validating project/parent links and walking ancestors. Relationship-changing writes for one owner serialize until commit. Owner transfers acquire old/new owner lock keys in deterministic order; hash collisions can only add serialization, not bypass validation.
- Added a disposable PostgreSQL fixture covering valid same-owner/same-project links, direct self-parent rejection, foreign-parent rejection, cross-project rejection, foreign-project rejection, and a sequential indirect cycle.
- Added a two-session READ COMMITTED test. Writer A creates one edge and holds its transaction open; writer B attempts the inverse edge, is observed waiting on the advisory lock, then must fail with the cycle-constraint error after writer A commits.
- CI now provisions PostgreSQL 17 and runs this database integration test before the existing application tests, typecheck, and production build.
- [CI #173](https://github.com/mohith-krishnaa/personal-os/actions/runs/44038158510) passed on `482e1921ada6bc723a65c167b3cbea72b916bcf4`: PostgreSQL integration check passed (including concurrent cycle rejection); 56/56 application tests passed; `npm run typecheck` passed; `npm run build` passed; npm install audited 43 packages and reported 0 vulnerabilities.
- The CI service resolved PostgreSQL 17.12. This is a disposable integration fixture, not a restore test and not a test against the live Supabase database's exact 17.11.0.003 patch level. The fixture validates the trigger function and trigger event contract; it does not apply the full six-migration chain or prove live RLS/two-user PostgREST isolation.
- Live Supabase remains unchanged: ACTIVE_HEALTHY in ap-southeast-1 on 17.11.0.003; the ledger still has 8 applied core migrations; both checklist tables and the Organization trigger remain absent from production. No production DDL, migration, data/RLS change, restore, or PR merge was performed.
- Free Plan scheduled backups remain unavailable and no manual schema/data/role export or restore test exists. PR #11 remains open and unmerged. Analytics remains queued.
- Lint remains unavailable because the repository has no lint script or configuration.

Next safe action: create and restore-test the private logical backup on an owner-controlled machine, then run the full six-migration sequence and authenticated two-user direct-API isolation against a disposable database matching the live legacy schema. Only then consider production rollout or PR #11 merge.

## Latest engineering checkpoint — parent/child invariant hardening (2026-11-17)

- Extended the unapplied task-relationship trigger migration to reject moving a parent task to another project or owner when existing children would be left with a different project or owner. This complements the per-owner transaction advisory lock: parent changes and child relationship writes serialize under the same owner lock, and the trigger checks both the proposed parent link and existing direct children.
- Extended the PostgreSQL integration fixture to verify that a parent project move and an owner transfer are rejected while existing children would become inconsistent.
- [CI #176](https://github.com/mohith-krishnaa/personal-os/actions/runs/44038758029) passed on `d872a6e6f530a9ee87e8851a1cf5465197240379`: PostgreSQL 17 hierarchy integration (including the two-session cycle race and parent/child mutation checks), 56/56 application tests, typecheck, production build, and npm install audit with 0 vulnerabilities.
- Two intermediate CI attempts failed before the corrected run: #172 used shell connection defaults that were accidentally escaped as literals; #175 had malformed dollar-quoted SQL in the newly added DO blocks. Both were corrected in subsequent commits. #173 passed the original concurrency test, and #176 passed the expanded test suite on the latest code head.
- Live Supabase remains unchanged: ACTIVE_HEALTHY in ap-southeast-1 on PostgreSQL 17.11.0.003; 8 applied core migrations; 6 Organization migrations remain unapplied; live projects.name, checklist tables, and the Organization task trigger are still absent. No production DDL, migration, RLS/data write, restore, or PR merge occurred.
- The CI fixture is a disposable PostgreSQL 17.12 service and exercises the actual migration function with the trigger event definition. It does not apply the full six-migration sequence, restore a production backup, or prove live RLS/PostgREST two-user isolation.
- Free Plan scheduled backups remain unavailable and no manual schema/data/role export or restore test exists. PR #11 remains open and unmerged; PR #12 remains a superseded draft. Analytics remains queued. Lint is not configured.

Next safe action: create and restore-test the private logical backup on an owner-controlled machine, then run the full six-migration sequence and authenticated two-user direct-API isolation against a disposable database matching the live legacy schema. Only then consider production rollout or PR #11 merge.

Documentation verification: [CI #177](https://github.com/mohith-krishnaa/personal-os/actions/runs/44039076954) passed on latest PR head `74979439c63e9ba27009a786cf2d929c4a15e68e`; this docs-only checkpoint preserves the code-bearing verification from CI #176.

- CI now replays the complete 15-file local migration chain on a disposable legacy-schema fixture and verifies two-owner RLS behavior. This does not restore production or test live PostgREST. Next: create and restore-test a private schema/data/role backup, replay migrations against that restored snapshot, verify authenticated direct-API isolation against the restored database, then re-run advisors before any production rollout or merge.


## Latest engineering checkpoint — full migration replay and progress schema repair (2026-11-17)

- Re-inspected the live Supabase project: `ACTIVE_HEALTHY`, ap-southeast-1, PostgreSQL 17.11.0.003; the authoritative migration ledger still has 8 applied migrations. The live public schema has 9 application tables, all with RLS enabled and zero rows. The six Organization migrations and the new Progress compatibility migration remain unapplied.
- Added a PostgreSQL 17 CI replay harness for all 15 local SQL migrations. It bootstraps Supabase roles/auth helpers, seeds legacy project/checklist records before the relevant migrations, verifies owner-safe checklist reconciliation, validates project title/name dual-write, and exercises authenticated Owner A/Owner B read/write isolation.
- The hierarchy concurrency test remains separate and continues to verify the two-session READ COMMITTED cycle race and parent/child invariant checks.
- Live schema inspection found a second concrete mismatch: `public.goals` has no `unit` or `target`, but `getGoalsWithProgress` selects both. The original Progress V1 `CREATE TABLE IF NOT EXISTS` skipped those columns because the core migration had already created `goals`. Added forward-only migration `20261117000100_reconcile_progress_goal_metrics.sql`; it adds nullable metrics without inventing values for legacy goals. The dashboard now renders such goals safely and omits progress logging until metrics are present.
- Added regression coverage for null-target legacy goal summaries. CI #189 and #191 passed: 15-migration replay, authenticated two-owner RLS checks, hierarchy concurrency, 58/58 tests, typecheck, production build, and 0 npm audit vulnerabilities. Lint remains unconfigured.
- Security advisor returned no lints. Performance advisor still reports 4 unindexed foreign keys, 14 auth RLS initialization-plan warnings, 13 unused-index findings, and 4 overlapping permissive policies on `goals`.
- The Free Plan has no scheduled backups. No manual logical backup or restore test exists. No production DDL, migration, RLS change, data write, restore, or PR merge was performed.

Next safe action: create and restore-test a private logical backup, run the migration chain against the restored production snapshot, and test authenticated direct-API isolation there. Keep production read-only until those gates and explicit rollout approval are satisfied. Analytics remains queued behind Organization.
