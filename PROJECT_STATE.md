# Personal-OS — Persistent Project State

> Canonical recovery checkpoint. Read this before making project claims or changes.
> Last verified: 2026-11-17 (GitHub PR/branch and CI rechecked; live database operations still timing out).

## Current verified state

- Stable integration branch: `main`
- Current `main` commit: `2b42dd17796b75dca79434a81d4e1f0cbf0fa043` (`docs: reconcile roadmap after V1 completion`).
- Recurring Tasks V1 — **merged** (PR #5).
- Reminders V1 — **merged** (PR #7).
- Progress & Streaks V1 — **merged** (PR #8).
- Security issue #6 — **closed/completed** after client execution was revoked for `public.rls_auto_enable()` and security verification reported 0 lints.
- Open GitHub issue backlog — **0** at last verification.
- Latest verified CI for the Organization implementation change — **successful** on commit `b8a686664e5e39b2ebc042192a9ea291c6d1bec7` (run #120, ID `43947823009`): 33 tests passed, `npm run typecheck` passed, `npm run build` passed, and npm audit reported 0 vulnerabilities. Any newer PR head must still have green checks before merge.
- Active feature branch: `feature/organization-v1`, in open PR #11 targeting `main`; it is not merged.

## Source-of-truth hierarchy

1. Actual GitHub repository and branch contents
2. Actual Supabase schema/data contract
3. CI/test results
4. `PROJECT_STATE.md`
5. `PROJECT_ROADMAP.md`
6. Chat history/memory

If sources disagree, verify the higher-priority source. Never guess.

## Anti-confusion protocol

Before every substantial change:
1. Read roadmap and project state.
2. Verify active branch and PR state.
3. Inspect relevant code.
4. Verify live Supabase schema for DB changes.
5. Make the smallest safe change.
6. Run CI/tests/build where applicable.
7. Re-read changed files and verify the result.
8. Update this checkpoint after milestones.
9. Never report a change as verified until the authoritative system confirms it.

Branches are not PRs. A Compare & pull request button only means a branch has changes relative to its base.

## Completed milestones

### Recurring Tasks V1 — COMPLETE
- Daily, weekly and monthly recurrence rules.
- Weekly cycle anchoring.
- Monthly day 29–31 clamping with preserved anchor day.
- Recurrence validation and creation UI.
- Next-occurrence generation after completion.
- Activity events and guarded completion updates.
- Shared recurrence types and regression tests.
- Supabase partial unique index for recurring occurrence idempotency.
- PostgreSQL `23505` handling.
- Reproducible migration.
- V1 occurrence-only editing semantics.
- Full timezone/DST recurrence semantics remain deferred.

### Reminders V1 — COMPLETE
- Owner-scoped reminders and notifications with RLS.
- Task ownership validation.
- Scheduled timestamp + timezone field.
- `IN_APP` channel.
- Upcoming-reminder query and server action boundary.
- Authenticated cron delivery endpoint.
- Durable notification records and delivery idempotency.
- Activity events, dashboard scheduling/upcoming UI.
- Validation tests, cron configuration and CI verification.
- Full user-local timezone/DST semantics remain a hardening item.

### Progress & Streaks V1 — COMPLETE
- Generic measurable goals with positive targets.
- Positive progress entries with date validation.
- Current and longest streak calculations; duplicate entries on one day count once.
- Dashboard goal cards, progress logging, percentage and streak display.
- Goals/progress migration with owner-scoped RLS and positive-value constraints.
- Batched dashboard loading to avoid N+1 progress queries.
- Authenticated `user_id` enforced at the service boundary.
- Progress unit tests included in the repository test command.
- PR #8 merged to `main`.

## Security / hardening status

- `public.rls_auto_enable()` client execution restricted; security issue #6 closed.
- Security verification reported 0 advisor lints after remediation.
- Foreign-key indexing/performance findings should still be reviewed during production hardening.
- CI/build must remain a merge gate for future work.

## Roadmap

1. Recurring Tasks V1 — DONE
2. Reminders V1 — DONE
3. Progress & Streaks V1 — DONE
4. **Organization V1 — IN PROGRESS (PR #11; live database verification pending)**
5. Analytics V1
6. AI Assistant V1
7. Research Agent V1
8. Adaptive Scheduling
9. Production hardening

## Mind tree

```mermaid
mindmap
  root((PERSONAL-OS))
    Core Productivity [DONE]
      Authentication
      Dashboard
      Tasks
      Scheduler
      Calendar
      CI
    Recurring Tasks V1 [DONE]
      Daily
      Weekly anchored
      Monthly anchored
      Occurrence generation
      DB idempotency
      Tests
    Reminders V1 [DONE]
      Reminder model
      Owner RLS
      Cron delivery
      Notifications
      Idempotency
      Timezone/DST [HARDEN LATER]
    Progress & Streaks V1 [DONE]
      Goals
      Progress logs
      Current + longest streaks
      Dashboard
      Batched loading
      Tests + RLS
    Organization V1 [IN PROGRESS]
      Subtasks
      Checklists
      Projects
      Notes
      Tags
      Attachments [evaluate separately]
    Analytics [PLANNED]
    AI Assistant [LATER]
    Research Agent [LATER]
    Adaptive Scheduling [FUTURE]
    Production Hardening [ONGOING]
      Security
      CI
      Migrations
      Observability
      Backups
```

## Definition of done — every feature

A feature is not complete merely because the UI works. Where applicable, verify:
1. Data model/schema
2. Authorization/RLS
3. Backend/application logic
4. Edge cases and failure states
5. Unit/integration/regression tests
6. UI/UX
7. CI/build
8. Migration/recovery implications
9. Documentation + `PROJECT_STATE.md`

## Future-session rule

Never infer progress from chat wording. Verify GitHub branch/PR state, inspect relevant files, verify Supabase for data changes, verify CI, and update this checkpoint. If uncertain, mark it uncertain and continue verification rather than guessing.


## Historical Organization V1 checkpoint — 2026-10-16

The following observations were made on 2026-10-16 and are retained for traceability, not as a claim about the current live database:

- Organization V1 implementation was under PR #11 on `feature/organization-v1`.
- The intended Supabase project was `gujzvkyytxsnervovvrt`; at that time the migration ledger and schema were reported as accessible, with Organization migrations not yet applied.
- The branch included owner-scoped projects, task/project associations, subtasks, checklist CRUD, ownership hardening, legacy checklist reconciliation, cycle prevention, and the project-name compatibility migration.
- Earlier CI runs #95 and #96 passed. These are historical checks and do not replace final-head verification.

## Organization V1 — current checkpoint (2026-11-16)

- GitHub confirms `main` is at `2b42dd17796b75dca79434a81d4e1f0cbf0fa043`.
- PR #11 is open, unmerged, non-draft, and mergeable; it targets `main`. Its verified head at the start of this checkpoint was `aa26a556cd6627a0ccd19efd914fe62be76f0ed9`.
- CI run #104 (ID `43928396020`) passed on commit `f2b9e43564663c74ac51e7f1e2356163633e21c3`: dependency installation, `npm run test`, `npm run typecheck`, and `npm run build` all succeeded. This predates the current documentation-only refresh; verify the newest head's CI before merge.
- Supabase project metadata for `gujzvkyytxsnervovvrt` reports `ACTIVE_HEALTHY`, but live migration listing, table introspection, read-only SQL, and advisor calls failed with connection timeouts. Advisor calls reported that the project was hibernated. Therefore the current live migration ledger and schema are **unknown**, not verified.
- No Organization migration was applied in this checkpoint, and no production schema or data was changed.
- Do not merge PR #11 or start Analytics until the live migration ledger/schema can be read, migration compatibility is reviewed against that state, recovery readiness is confirmed, migrations are applied safely, advisors are checked, and authenticated CRUD plus cross-user isolation pass.

## Organization V1 implementation contract (branch state; not a live-deployment claim)

- Projects, tasks, subtasks, and checklist records are owner-scoped. Application checks provide defense in depth; PostgreSQL RLS and task-link validation triggers are intended to enforce the database boundary.
- A task's project and parent task must belong to the same owner; a subtask must remain in the same project as its parent. The hierarchy trigger rejects self-parenting and indirect cycles.
- `checklist_items` is the canonical application table. The legacy `task_checklist_items` table is retained and reconciled forward rather than dropped.
- The project compatibility migration bridges legacy `projects.title` and application-facing `projects.name` without dropping the legacy column.
- These are repository implementation contracts. Their live production state remains unverified until Supabase introspection succeeds.


## Organization V1 — current checkpoint (2026-11-17)

- Repository: `mohith-krishnaa/personal-os`; stable `main` remains at `2b42dd17796b75dca79434a81d4e1f0cbf0fa043`.
- PR #11 remains open and unmerged on `feature/organization-v1`. The live PR page is authoritative for its current head and mergeability.
- PR #12 (`fix/project-schema-compatibility`) remains an open draft explicitly marked superseded by PR #11. Do not merge it separately; its compatibility migration is already integrated into PR #11.
- CI run #115 (ID `43938573918`) passed on PR head `91cd88fedef768a65286381c361b72f46d67ee29`: `npm install`, `npm run test`, `npm run typecheck`, and `npm run build` succeeded.
- Organization project tests now verify that `createProject` derives `user_id` from `auth.getUser()`, `updateProject` filters by both project ID and authenticated user ID, and unauthenticated updates do not reach the database client. These are application-service tests using mocked Supabase clients, not live RLS tests.
- Added the architecture/decision record at `docs/architecture/organization-v1.md`. It documents the RLS trust boundary, owner/project/task/checklist invariants, forward-only compatibility intent, and the fail-closed production rollout rule.
- No lint script or linter configuration exists; no lint result is claimed.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but repeated `list_migrations` and verbose `list_tables` calls time out. A read-only `select now()` probe also times out. Security/performance advisor calls report that the project is hibernated. Live migration ledger and table definitions remain **unknown**.
- No migrations were applied and no production schema or data was changed. PR #11 was not merged.
- Organization V1 remains incomplete until the live ledger/schema are inspected, backup/recovery readiness is confirmed, reviewed migrations are applied safely, advisors are checked, and authenticated CRUD plus cross-user isolation pass.

Next safe action: restore supported database connectivity and inspect the actual live migration ledger and Organization tables before attempting any DDL or merge.


## Organization V1 — subtask visibility checkpoint (2026-11-17)

- PR #11 remains open and unmerged on `feature/organization-v1`; its live page is authoritative for current head/mergeability. PR #12 remains a draft explicitly superseded by PR #11.
- Added `listSubtasksAction` in `src/app/dashboard/subtask-actions.ts`. It creates the authenticated server-side Supabase client, resolves the user with `auth.getUser()`, and delegates to the owner-scoped service.
- `listSubtasks` verifies that the parent belongs to the supplied user and filters the child query by both `user_id` and `parent_task_id`.
- Updated `SubtaskManager` to lazy-load direct subtasks when expanded, display their completion state, and update completion through the existing `toggleTaskAction`. Subtask creation remains available. This is a one-level dashboard view; recursive hierarchy navigation is not implemented by this change.
- Added two tests: one asserts the child query's owner/parent filters and stable ordering; one asserts that a foreign-owned parent prevents child listing.
- CI run #120 (ID `43947823009`) passed on implementation commit `b8a686664e5e39b2ebc042192a9ea291c6d1bec7`: **33 passed, 0 failed**, typecheck passed, production build passed, and npm audit reported 0 vulnerabilities. Recheck the live PR checks on any later documentation commit before merge.
- No lint script or linter configuration exists; lint is not verified.
- Supabase metadata reports `ACTIVE_HEALTHY`; `list_migrations`, verbose `list_tables`, and read-only SQL continue to time out. Security/performance advisor calls report the project hibernated. Live migration ledger/schema remain unknown.
- No production DDL, migration, data write, or PR merge was performed.

Next safe action: restore supported database connectivity, inspect the actual migration ledger and Organization tables, confirm recovery readiness, then proceed with reviewed migrations, advisors, and authenticated two-user CRUD/isolation tests.
