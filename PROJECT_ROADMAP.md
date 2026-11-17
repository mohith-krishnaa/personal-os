# Personal OS — Project Roadmap & Mind Map

> Single source of truth for project direction. Verify GitHub/Supabase/CI before making claims.
> Last reconciled: 2026-11-17.

## Current position

**Completed:** Core productivity, Recurring Tasks V1, Reminders V1, and Progress & Streaks V1.

**In progress:** Organization V1 remains in PR #11. The dashboard supports projects, direct subtask listing/completion, and checklist create/list recovery. The latest code change hardens project-list reads by requiring an authenticated caller and explicitly filtering by that user's ID. CI #143 passed on code-bearing commit `1106efd1b3a1be9e3b5aac18bd8a6e714476cb9f` with 45 tests, typecheck, production build, and 0 vulnerabilities; CI #147 passed on latest documentation checkpoint `b86056d20ca3f9ed470709ad4baebcfa711e9ea6` with the same checks. No lint script/configuration exists. Live migration/schema inspection and authenticated end-to-end verification remain blocked.

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
├── GOALS & PROGRESS [DONE — PR #8]
│   ├── Generic measurable goals
│   ├── Custom units
│   ├── Progress history
│   ├── Current + longest streaks
│   └── Batched dashboard loading
│
├── ORGANIZATION [IN PROGRESS — PR #11]
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
3. Progress & Streaks V1 — DONE
4. **Organization V1 — IN PROGRESS (PR #11; live database verification pending)**
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

### P1 — Organization V1
- Implementation exists in PR #11: owner-scoped projects, task/project association, subtasks, checklists, ownership validation, cycle prevention, compatibility migrations, tests, and dashboard UI. The dashboard subtask panel reads direct children on demand and supports completion updates through the existing owner-scoped task action.
- Project-list reads now resolve the authenticated server-side user, reject unauthenticated calls before database access, and filter by user_id. Optional status filtering and newest-first ordering are preserved.
- CI #143 passed on code-bearing commit `1106efd1b3a1be9e3b5aac18bd8a6e714476cb9f`: 45/45 tests, typecheck, production build, and install output with 0 vulnerabilities. CI #147 passed on latest documentation checkpoint `b86056d20ca3f9ed470709ad4baebcfa711e9ea6` with the same checks. No lint script/configuration exists.
- Highest-priority remaining work is live database verification and safe rollout, followed by authenticated CRUD and cross-user isolation tests. The current UI exposes one level of subtasks; recursive hierarchy UX is not claimed.
- Do not start Analytics until Organization V1's database and authorization acceptance criteria are verified.

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
