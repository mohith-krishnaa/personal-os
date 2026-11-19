> **Verified checkpoint — 2026-11-19 (remote state reconciliation after Organization FK recovery guard).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; last fully CI-verified branch head before this documentation-only refresh: `1d0ad43319e3a85f6280632e1d663c8d0c4e3b16`. The branch is 347 commits ahead of `main` and 0 behind. PR #11 is open, unmerged, non-draft, and mergeable.
>
> The branch contains 19 numbered SQL migrations: 8 versions match the live Supabase ledger and 11 are branch-only (8 Organization, 1 Progress compatibility, 2 RLS performance). The new `20261119000300_ensure_project_task_foreign_keys.sql` guard enforces the exact project/task FK contracts, repairs a missing FK only when no FK uses the source column, validates a sole exact NOT VALID FK, and fails closed on conflicting, duplicate, or composite definitions without dropping existing constraints.
>
> Code/test commit `020877abbbf63719716a9d0c615160a097744716` passed [CI #309](https://github.com/mohith-krishnaa/personal-os/actions/runs/44576380568): full 19-migration PostgreSQL 17 replay, Organization/RLS assertions, read-only preflight, FK guard idempotence and recovery cases, checklist reconciliation tests, hierarchy concurrency, 58/58 application tests, typecheck, and production build. Documentation checkpoints [CI #310](https://github.com/mohith-krishnaa/personal-os/actions/runs/44576780590) and [CI #311](https://github.com/mohith-krishnaa/personal-os/actions/runs/44577071600) passed. The pre-refresh branch HEAD `1d0ad43319e3a85f6280632e1d663c8d0c4e3b16` passed [CI #319](https://github.com/mohith-krishnaa/personal-os/actions/runs/44587907725); every configured job step completed successfully, including migration replay, RLS assertions, hierarchy checks, application tests, typecheck, and build. CI #313 through #318 also passed on intervening documentation checkpoints. No lint script is configured.
>
> Fresh read-only Supabase verification: project `gujzvkyytxsnervovvrt` is `ACTIVE_HEALTHY` on PostgreSQL 17.11.0.003; the live migration ledger has exactly 8 versions. All 9 public tables have RLS enabled and currently report zero rows. `projects.name`, `checklist_items`, `task_checklist_items`, Organization user-defined triggers, `goals.unit`, and `goals.target` are absent. The existing `tasks.project_id`, `tasks.parent_task_id`, and `projects.goal_id` foreign keys were inspected read-only; each has the expected target, delete action, and `convalidated=true`.
>
> Personal-OS Builder is enabled. Its recorded last run `2137c85a-2500-832c-b819-9896e93be753` is marked `in_progress`, started at `2026-11-19T18:17:03Z`, and has no completion timestamp. Latest stored result `603cd95a-511c-8321-9ad7-6459f2953f51` was created at `2026-11-19T17:29:05Z` and belongs to an older run. The in-progress marker does not prove worker liveness.
>
> No local checkout is attached, so local `git status` cannot be verified. No production migration, DDL/DML, RLS change, backup/restore, or PR merge was performed. Production rollout remains blocked on an owner-controlled complete schema/data/roles backup successfully restored in isolation, checklist conflict review against that restore, and authenticated two-user PostgREST CRUD/isolation tests.
>
> **Next task:** continue a read-only static audit of the 19-migration sequence and its preflight against the verified 8-migration legacy schema; do not retry unavailable backup tooling. The owner must provide the complete private backup and isolated-restore evidence before production rollout. Keep Analytics queued until Organization acceptance is genuinely complete.
>
> ---

# Personal OS — Project Roadmap & Mind Map

> Single source of truth for project direction. Verify GitHub/Supabase/CI before making claims.
> Last reconciled: 2026-11-19. CI #318 passed on documentation checkpoint head `67dcae2913bd904a1dec0fb641bd0353bde63478`; CI #309 passed on the 19-migration code/test commit.

## Current position

**Completed:** Core productivity, Recurring Tasks V1, and Reminders V1. Progress & Streaks V1 application implementation is complete, but live schema compatibility repair remains pending.

**In progress:** Organization V1 remains under review on `feature/organization-v1` / PR #11. The 19-migration PostgreSQL 17 replay and all configured checks passed on code/test commit [CI #309](https://github.com/mohith-krishnaa/personal-os/actions/runs/44576380568). The pre-refresh documentation checkpoint head passed [CI #318](https://github.com/mohith-krishnaa/personal-os/actions/runs/44587631127), including migration replay, Organization/RLS assertions, hierarchy checks, application tests, typecheck, and production build. The current commit only reconciles this roadmap checkpoint and requires its own CI result. The new forward-only guard handles missing/exact NOT VALID project/task FKs and aborts on conflicting or duplicate definitions without dropping constraints.

**Production acceptance blocked:** live Supabase still has only 8 migrations applied, lacks `projects.name`, both checklist tables, Organization triggers, and goal metric columns. No complete owner-controlled schema/data/roles backup has been restored in isolation, and authenticated two-user live PostgREST verification is outstanding. No production changes or PR merge were made.

**Queued:** Analytics V1 follows Organization production acceptance. AI Assistant, Research Agent, Adaptive Scheduling, and broader production hardening remain later milestones.

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
3. Progress & Streaks V1 — application implementation complete; live `goals.unit` / `goals.target` compatibility repair pending
4. **Organization V1 — IN PROGRESS:** branch implementation and 19-migration disposable PostgreSQL verification pass; production backup/restore and live authenticated API gates remain open
5. Analytics V1 — queued until Organization production acceptance
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
- PR #11 is the intended review path and remains open, unmerged, non-draft, and mergeable. PR #12 is an open superseded draft; do not merge it separately.
- The branch contains 18 migrations: 8 match the live ledger and 10 are local-only (7 Organization, 1 Progress compatibility, 2 RLS performance).
- [CI #241](https://github.com/mohith-krishnaa/personal-os/actions/runs/44480778181) passed on head `d697ff9b3249e7b1795a52ded88829260fae51b4`. [CI #244](https://github.com/mohith-krishnaa/personal-os/actions/runs/44486737299) passed on test commit `bd31ebe48d13f4ddf0c65192cb18bd3f175dfa06` after strengthening migration assertions to verify all ten optimized policies preserve their authenticated role, command, owner predicate, and progress-to-goal ownership check; it also asserts `goals_owner` remains initplan-safe. CI #244 replayed all 18 migrations on PostgreSQL 17, passed hierarchy concurrency integration, **58/58 application tests**, typecheck, production build, and npm install audit reported 0 vulnerabilities.
- Application implementation includes owner-scoped projects/tasks, task/project association, subtasks, checklists, dashboard failure-state recovery, and task relationship preflight. Partial relationship updates preserve omitted links and honor explicit null unlinks.
- Live Supabase remains at 8 applied migrations. It lacks `projects.name`, both checklist tables, the task-organization validation trigger, and `goals.unit` / `goals.target`. All 9 public application tables have RLS enabled.
- Current performance advisor findings remain live until reviewed migrations are applied: 4 unindexed foreign keys, 14 auth_rls_initplan warnings, 13 unused-index findings, and 4 overlapping permissive goal policies. The pending migrations address three Organization/compatibility indexes, four redundant goal policies, and ten reminder/notification/progress policy expressions. `notifications.task_id` remains a separate hardening item.
- Production rollout is blocked on a private schema/data/roles backup that has been restored successfully in isolation, followed by authenticated two-user PostgREST verification. No production DDL, migration, RLS change, data write, restore, or PR merge has occurred.
- Next: continue static compatibility review and migration assertions while waiting for the owner-controlled recovery artifact. Do not start Analytics until Organization production acceptance passes.
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
- 2026-11-17: Keep Organization V1 fail-closed until a private logical backup is restore-tested, all local migrations are replayed against that restored snapshot, concurrent hierarchy-cycle behavior is tested, and authenticated two-user live PostgREST isolation passes. Disposable full-chain/RLS and concurrency tests now pass in CI; Free Plan scheduled backups are unavailable.


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


### Organization authorization regression — 2026-11-17
- Expanded the disposable migration replay to seed valid legacy checklist rows for both owners and verify canonical reconciliation for both; malformed cross-owner task associations are excluded.
- Added reciprocal two-owner visibility checks and direct SQL UPDATE/DELETE attempts in both directions across projects, tasks, and both checklist tables. Every cross-owner mutation must affect zero rows.
- [CI #207](https://github.com/mohith-krishnaa/personal-os/actions/runs/44055203271) passed the full migration replay, hierarchy concurrency, application tests, typecheck, and production build on `a9f73bfc26de818679c101974544793a839f2c74`.
- This strengthens Organization's CI acceptance evidence only; it is not a live PostgREST test or a production rollout.


### Organization direct-API relationship regression — 2026-11-17
- Added reciprocal Owner B attempts to spoof a project owner, attach a task to Owner A's project, insert canonical/legacy checklist items for Owner A's task, and reassign Owner B task/checklist relationships to Owner A records.
- The fixture fails if any prohibited operation succeeds. Existing two-owner UPDATE/DELETE denial checks remain reciprocal.
- [CI #209](https://github.com/mohith-krishnaa/personal-os/actions/runs/44064242592) passed the 15-migration PostgreSQL 17 replay, Organization RLS assertions, hierarchy concurrency, 58 application tests, typecheck, and production build.
- These are disposable-database checks only. They do not replace a restore-tested production backup or live PostgREST JWT isolation.


### Organization checklist SELECT ownership hardening — 2026-11-17
- Added a forward-only migration that scopes canonical and legacy checklist SELECT policies to both the checklist row owner and the referenced task owner.
- The PostgreSQL 17 replay seeds malformed canonical and legacy checklist rows owned by Owner A but attached to Owner B's task. Owner A must not be able to read either row; valid checklist rows remain visible.
- [CI #211](https://github.com/mohith-krishnaa/personal-os/actions/runs/44065216491) passed the 16-migration replay, hierarchy concurrency, 58 application tests, typecheck, and production build. [CI #212](https://github.com/mohith-krishnaa/personal-os/actions/runs/44065285214) passed the corrected test assertion message.
- This is disposable-database verification only. Production still lacks the checklist tables and policy migration; backup/restore and live JWT/API checks remain required.


### Organization anonymous-role denial — 2026-11-17
- The disposable migration fixture now grants table-level SELECT/INSERT/UPDATE/DELETE to `anon` as well as authenticated/service roles, so the test cannot pass merely because anonymous SQL privileges are missing.
- With an empty JWT subject, `anon` sees zero rows in projects, tasks, canonical checklists, and legacy checklists. Anonymous inserts are rejected on all four tables; updates and deletes affect zero authenticated rows.
- [CI #216](https://github.com/mohith-krishnaa/personal-os/actions/runs/44072614729) passed the full 16-migration PostgreSQL 17 replay, authenticated RLS checks, anonymous denial checks, hierarchy concurrency, application tests, typecheck, and production build.
- This remains disposable-database evidence only. Production schema, backup/restore, and live PostgREST authorization gates remain unchanged. No production change was made.


## Latest checkpoint — complete anonymous Organization CRUD denial matrix (2026-11-17)

- Code-bearing commit [fba0eee](https://github.com/mohith-krishnaa/personal-os/commit/fba0eeeda2b824afd8525d9f941050dca08e6a6a) extends the anonymous RLS fixture from representative write checks to the complete CRUD matrix.
- The test explicitly grants `anon` table-level SELECT, INSERT, UPDATE, and DELETE on `projects`, `tasks`, `checklist_items`, and `task_checklist_items`. Under an empty JWT subject it verifies zero visible rows, denied inserts, zero-row updates, and zero-row deletes on every table.
- [GitHub Actions run 44082207231](https://github.com/mohith-krishnaa/personal-os/actions/runs/44082207231) completed successfully: full 16-migration PostgreSQL 17 replay, task-hierarchy concurrency test, 58/58 application tests, TypeScript typecheck, production build, and npm audit with 0 vulnerabilities. No lint script/configuration exists.
- This is disposable PostgreSQL verification only. Live Supabase remains unchanged: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, 8 applied migrations, 8 local-only migrations, and 9 RLS-enabled public application tables with zero rows. The seven Organization migrations and one Progress compatibility migration remain unapplied.
- No production DDL, migration, RLS change, data write, restore, or PR merge was performed. Private backup/restore and live authenticated PostgREST verification remain the rollout blockers.


## Latest checkpoint — 2026-11-18 (foreign-key index verification)

Organization remains the active milestone. The full local migration replay now fails if the three indexes already defined by the pending Organization/compatibility migrations are missing, invalid, or not ready. CI #222 passed the 16-migration replay, hierarchy concurrency, 58 application tests, typecheck, production build, and npm audit (0 vulnerabilities). The read-only live preflight confirms those indexes and the separate notifications.task_id index are still absent in production. This is test/preflight coverage, not a production index change. Backup/restore and live authenticated PostgREST acceptance remain open; Analytics stays queued.

## Verified checkpoint — 2026-11-19 (project/task foreign-key contract)

- Branch: `feature/organization-v1`; code/test commit: `9805fe3d24279cf38dfa688f8132c1b942cea7cb`; PR #11 remains open and unmerged. The code commit changes only `supabase/tests/organization-migration-assertions.sql` and `supabase/operations/organization-v1-preflight.sql`.
- Migration replay assertions now require exactly one single-column FK for each relationship: `tasks.project_id -> projects.id ON DELETE SET NULL`, `tasks.parent_task_id -> tasks.id ON DELETE CASCADE`, and `projects.goal_id -> goals.id ON DELETE SET NULL`. Each must target the exact table/column and be validated. This catches an incorrect pre-existing FK that the Organization migration's current column-based existence check could otherwise mistake for the required constraint.
- Read-only preflight query 11 reports each expected relationship, the matching constraint definition, validation state, and the count of single-column FKs on that source column. It contains SELECT/catalog inspection only.
- No migration was added or modified. The repository tree contains 18 numbered SQL migration files; the migration-count fixture remains 18.
- Live read-only verification against Supabase project `gujzvkyytxsnervovvrt`: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, exactly 8 applied migration versions, and 9 public tables with RLS enabled. The three live FK definitions match the expected target columns, are validated, and have the expected SET NULL/CASCADE actions. No production write or DDL was executed.
- Current live advisors: security 0 lints; health 0 lints; performance still reports 4 unindexed FKs, 14 auth-RLS initialization-plan warnings, 13 unused-index findings, and 4 overlapping permissive goals-policy findings. Pending branch migrations are not applied to production.
- CI #298 passed on the preceding head `38a1a730ae6151753122a429c80fdf63aaf9f27c`. CI #299 passed on exact code/test commit `9805fe3d24279cf38dfa688f8132c1b942cea7cb`: npm install, PostgreSQL-client installation, full 18-migration PostgreSQL 17 replay, Organization RLS assertions, read-only preflight execution including query 11, task-hierarchy concurrency checks, 58/58 application tests, TypeScript typecheck, and production build all succeeded. No lint script/configuration is present.
- The current execution environment has no attached repository checkout, no `psql`, `pg_dump`, Docker, or Supabase CLI. Local working-tree status and local execution cannot be verified. The remote branch/PR are authoritative for this checkpoint.
- Production rollout remains blocked on an owner-controlled complete schema/data/roles backup successfully restored in isolation, followed by authenticated two-user PostgREST CRUD/isolation tests. The available Supabase connector exposes no backup/export workflow. No production migration, DDL, DML, RLS change, backup/restore, or PR merge was performed.

**Next action:** verify CI #299 on the exact code head. If it passes, retain this assertion/preflight improvement and continue the Organization recovery gate; if it fails, inspect the failing step and fix only the regression introduced by this commit. Do not start Analytics or alter production before the Organization acceptance gates pass.
