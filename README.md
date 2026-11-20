# Personal OS

A personal productivity web app designed to become a user's **personal operating system**.

Instead of being only a todo list, Personal OS is planned to combine planning, scheduling, notes, goals, reminders, behavioral analytics, and AI assistance in one system.

## Vision

**Plan → Execute → Track → Analyze → Adapt**

The long-term goal is for the system to learn from real usage patterns and help users build more realistic schedules, identify recurring problems, and make better decisions about their time.

## Planned Features

- Tasks, subtasks, and checklists
- Goals and projects
- Day, week, and month planning
- Calendar and reminders
- Notes and tags
- Recurring tasks
- Activity/event tracking
- Daily, weekly, and monthly analytics
- AI daily briefings and reviews
- AI-assisted planning and task breakdown
- Web research agent for finding useful resources
- Adaptive scheduling based on historical behavior

## Development Roadmap

### V1 — Core Productivity
Authentication, dashboard, tasks, goals, projects, notes, calendar foundations, and activity tracking.

### V2 — Scheduling & Analytics
Recurring tasks, reminders, scheduling logic, productivity statistics, planning accuracy, and behavioral insights.

### V3 — AI Assistant
Brain-dump-to-tasks, daily planning, daily reviews, and AI-generated briefings.

### V4 — Research Agent
Web research, source extraction, ranking, summarization, and optional task/resource generation.

### V5 — Adaptive Personal OS
Behavior modeling, workload prediction, intelligent scheduling, and continuous improvement from user activity.

## Architecture Principles

- PostgreSQL as the source of truth
- Task INSERT/UPDATE activity events are written in the same PostgreSQL statement transaction via a SECURITY INVOKER trigger; task/subtask creation uses per-owner client request IDs and payload fingerprints for same-request retries; DELETE events and immutable activity-event retention are not yet covered
- Deterministic business logic for scheduling and constraints
- AI operates through validated tools rather than direct database access
- User approval for consequential external or bulk actions
- Privacy and data isolation designed from the beginning

## Verified status

The current verified baseline on `main` includes core productivity, **Recurring Tasks V1**, **Reminders V1**, and **Progress & Streaks V1**. **Organization V1** is implemented on `feature/organization-v1` in open PR #11, but it is not merged. Fresh read-only inspection reconfirmed eight applied core migrations; the branch contains **24 migrations total**, with **16 branch-only migrations**. The branch includes Organization ownership/RLS, checklist reconciliation, reminder/notification owner-link constraints, atomic reminder delivery, transactional task INSERT/UPDATE activity events, and per-owner task/subtask create-request idempotency. These changes are not deployed. DELETE event semantics and immutable activity-event retention remain incomplete. The isolated two-owner PostgREST harness is prepared but has not been executed. Production rollout remains blocked by the owner-controlled complete backup/isolated-restore gate, checklist conflict review, authenticated API acceptance, and explicit migration approval. Analytics remains queued. See `PROJECT_STATE.md`, `PROJECT_HANDOFF.md`, and `docs/operations/organization-v1-preflight.md` for the current checkpoint.

The V1 recurrence implementation includes daily, weekly, and monthly rules, next-occurrence generation, validation, activity events, and idempotency protection. Reminders include owner-scoped data access, upcoming-reminder queries, an in-app channel contract, authenticated delivery, durable notifications, and dashboard UI.

> Timezone and daylight-saving behavior is not fully solved yet. Do not treat the presence of a timezone field as complete arbitrary timezone scheduling.

## Local development

The repository uses Next.js and includes scripts for development, production builds, and focused recurrence/reminder tests:

```bash
npm install
npm run dev
npm run test
npm run typecheck
npm run build
```

## Project-state references

- `PROJECT_STATE.md` is the canonical verified checkpoint for current implementation status.
- `PROJECT_ROADMAP.md` describes longer-term direction and may lag behind merged work; verify it against the actual repository and CI before making claims.
- `docs/architecture/organization-v1.md` records Organization ownership boundaries, compatibility decisions, and production rollout gates.
- `docs/operations/organization-v1-preflight.md` records live schema evidence, migration reconciliation, the Free Plan backup gate, and the safe rollout sequence.
- `supabase/operations/organization-v1-preflight.sql` is a read-only SQL checklist for rechecking the live schema and policies.

## License

To be decided.
