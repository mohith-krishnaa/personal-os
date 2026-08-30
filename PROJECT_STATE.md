# Personal-OS — Persistent Project State

> Canonical recovery checkpoint. Read this before making project claims or changes.
> Last verified: 2026-08-30.

## 1. Current state

- Stable integration branch: `main`
- Current engineering branch: `feature/recurring-tasks-v1`
- Project-state branch: `chore/project-state-v1`
- Open PRs: **0**
- PR candidates awaiting review/creation: `feature/recurring-tasks-v1`, `chore/project-state-v1`

## 2. Merged PR history

- PR #1 — `ci: verify Next.js builds` — merged.
- PR #2 — `feat: task scheduler v1` — merged.

Never describe these as pending PRs.

## 3. Feature status

### Completed
- Core task CRUD/workflow
- Task status, priority, duration fields
- Due date/time and scheduled start/end
- Day / Week / Month calendar
- CI build verification
- Scheduler/calendar merged to `main`

### In progress
- **Recurring Tasks V1**
  - Recurrence model exists.
  - Daily / weekly / monthly rule types exist.
  - Occurrence generation exists.
  - Completion generates the next occurrence.
  - Activity event is recorded for generated occurrences.

### Needs correction before completion
- Weekly `interval > 1` semantics are not correctly anchored to the recurrence cycle.
- Recurrence tests need to be added/expanded.
- Concurrent completion must not create duplicate occurrences.
- Series editing semantics must distinguish occurrence vs entire series.
- Timezone/DST behavior must be explicitly defined before reminders.
- Do not call Recurring Tasks V1 complete until code + schema + UI + tests/CI are verified.

### Next
1. Review/fix recurrence semantics.
2. Add deterministic recurrence tests.
3. Verify database constraints/RLS and occurrence generation behavior.
4. Review recurring-task UI.
5. Run CI/build and inspect failures.
6. Create/review PR for recurring tasks.
7. Merge only after verification.
8. Then start Reminders V1.

## 4. Project-state work

`chore/project-state-v1` exists as a branch and is intended to preserve this checkpoint and the anti-hallucination workflow.

## 5. Anti-hallucination protocol

Before every substantial change:

1. Read `PROJECT_ROADMAP.md`.
2. Read `PROJECT_STATE.md`.
3. Verify the current branch and actual repository tree.
4. Verify the relevant Supabase schema before assuming columns/tables exist.
5. Inspect current implementation before proposing replacement code.
6. Write a short plan before changing code.
7. Make small, atomic commits.
8. Run tests/build/CI where applicable.
9. Update `PROJECT_STATE.md` and `PROJECT_ROADMAP.md` after a milestone.
10. Only claim a feature is complete when the verification checklist passes.

### Source-of-truth hierarchy

1. Actual GitHub repository/branch contents
2. Actual Supabase schema/data contract
3. CI/test results
4. `PROJECT_STATE.md`
5. `PROJECT_ROADMAP.md`
6. Chat history / memory

If sources conflict, verify the higher-priority source instead of guessing.

## 6. Branch / PR rules

- Branches are not PRs.
- A branch with a GitHub "Compare & pull request" button is a **PR candidate**, not an open PR.
- Confirm PR state through GitHub before reporting pending/open PRs.
- Do not merge feature work merely because a branch exists.
- Prefer one coherent feature per PR.
- Keep `main` stable.

## 7. Recurrence contract currently implemented

```text
DAILY   -> interval in days
WEEKLY  -> interval + selected weekdays
MONTHLY -> interval + dayOfMonth
```

The current implementation uses UTC date arithmetic. This is acceptable only as an implementation detail until user timezone semantics are explicitly designed.

## 8. Database verified on 2026-08-30

Supabase project is active/healthy. `tasks` contains:
- id, user_id, project_id, parent_task_id
- title, description, status, priority
- due_at, scheduled_start, scheduled_end
- estimated_minutes, actual_minutes, completed_at
- created_at, updated_at
- recurrence_rule, recurrence_until, recurrence_parent_id

`activity_events` contains:
- id, user_id, event_type, entity_type, entity_id
- occurred_at, metadata, created_at

Never invent additional columns without re-checking the live schema.

## 9. Roadmap

1. Recurring Tasks V1
2. Reminders V1
3. Progress & Streaks V1
4. Organization V1
5. Analytics V1
6. AI Assistant V1
7. Research Agent V1
8. Adaptive Scheduling
9. Production hardening

## 10. Session log

### 2026-08-30
- Rechecked repository from scratch after uncertainty about PR state.
- Confirmed PR #1 and PR #2 are merged.
- Confirmed there are currently zero open PRs.
- Confirmed two PR candidates exist as branches: recurring tasks and project state.
- Verified live Supabase schema.
- Identified weekly recurrence interval semantics as a correctness issue.
- Established the source-of-truth hierarchy and verification protocol.
- Next action: review/fix recurrence implementation before merging.

## 11. Important instruction to future sessions

Do not infer progress from chat wording such as "we did it" or "pending PR". Re-check GitHub and Supabase. Update this file after every major milestone. If uncertain, say what is verified and what is not verified.
