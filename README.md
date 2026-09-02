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
- Activity events preserved for historical analysis
- Deterministic business logic for scheduling and constraints
- AI operates through validated tools rather than direct database access
- User approval for consequential external or bulk actions
- Privacy and data isolation designed from the beginning

## Verified status

The current verified baseline on `main` includes the core productivity foundation, **Recurring Tasks V1**, and **Reminders V1**. Progress & Streaks V1 is the current engineering focus. The project-state checkpoint documents the merged work, CI verification, ownership boundaries, and remaining timezone/DST limitations.

The V1 recurrence implementation includes daily, weekly, and monthly rules, next-occurrence generation, validation, activity events, and idempotency protection. Reminders include owner-scoped data access, upcoming-reminder queries, an in-app channel contract, authenticated delivery, durable notifications, and dashboard UI.

> Timezone and daylight-saving behavior is not fully solved yet. Do not treat the presence of a timezone field as complete arbitrary timezone scheduling.

## Local development

The repository uses Next.js and includes scripts for development, production builds, and focused recurrence/reminder tests:

```bash
npm install
npm run dev
npm run test
npm run build
```

## Project-state references

- `PROJECT_STATE.md` is the canonical verified checkpoint for current implementation status.
- `PROJECT_ROADMAP.md` describes longer-term direction and may lag behind merged work; verify it against the actual repository and CI before making claims.

## License

To be decided.
