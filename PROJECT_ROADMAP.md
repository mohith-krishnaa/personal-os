# Personal OS — Project Roadmap & Mind Map

> Single source of truth for project direction. Update this file whenever a major feature is started, completed, deferred, or redesigned.

## Current position

**Completed:** Core task creation, scheduling fields, editing/rescheduling, and Day/Week/Month calendar.

**Current work:** Recurring Tasks V1.

**Paused groundwork:** Generic progress + streak calculations exist on `feature/progress-streaks-v1`; the UI waits until recurrence and reminders are complete.

## Mind map

```text
PERSONAL OS
│
├── CORE PRODUCTIVITY [DONE]
│   ├── Authentication / Dashboard / Tasks
│   ├── Status / Priority / Duration
│   └── Activity events
│
├── TIME & SCHEDULING [PARTIAL]
│   ├── Due date/time [DONE]
│   ├── Scheduled start/end [DONE]
│   ├── Day / Week / Month calendar [DONE]
│   ├── Recurring tasks [NEXT]
│   ├── Reminders [NEXT]
│   └── Conflict-aware scheduling [LATER]
│
├── ORGANIZATION [PLANNED]
│   ├── Projects / Subtasks / Checklists
│   ├── Notes / Tags / Attachments
│
├── GOALS & PROGRESS [AFTER SCHEDULING]
│   ├── Generic measurable goals
│   ├── Custom units: pages, km, problems, minutes, etc.
│   ├── Progress logs / history
│   ├── Current + longest streaks
│   └── Goal motivation
│
├── ANALYTICS [PLANNED]
│   ├── Daily / Weekly / Monthly reviews
│   ├── Planned vs actual time
│   ├── Completion + progress trends
│   └── Behavioral insights
│
├── AI ASSISTANT [LATER]
│   ├── Brain dump → tasks
│   ├── Task breakdown / planning
│   ├── Daily briefing / review
│   └── Validated tool-based actions
│
├── RESEARCH AGENT [LATER]
│   ├── Web research / source extraction
│   ├── Ranking / summarization
│   └── Optional resource/task generation
│
└── ADAPTIVE PERSONAL OS [FUTURE]
    ├── Learn actual duration
    ├── Detect overload/procrastination patterns
    ├── Predict workload
    └── Adapt schedules from behavior
```

## Execution order

1. **Recurring Tasks V1** — rule model + occurrence generation/completion semantics.
2. **Reminders V1** — reminder records + notification abstraction.
3. **Progress & Streaks V1** — measurable goals + progress logs + streak dashboard.
4. **Organization V1** — subtasks, checklists, notes, tags.
5. **Analytics V1** — daily/weekly/monthly behavioral insights.
6. **AI Assistant V1** — planning, reviews, briefings through validated tools.
7. **Research Agent V1** — web research and source-backed resources.
8. **Adaptive Scheduling** — only after sufficient activity data exists.
9. **Production hardening** — migrations, RLS/security, tests, deployment, observability, backups.

## Rules

- Check this file before starting a feature.
- Do not silently reorder roadmap items.
- Do not call a feature complete until code, data model, UI, and CI are verified where applicable.
- Never invent database columns without a verified schema/backend contract.
- PostgreSQL/Supabase remains the source of truth.
- Preserve activity history for analytics and adaptive scheduling.
- AI must use validated application tools, not direct database writes.
- Prefer small branches/PRs and merge only after CI is green.

## Branch map

- `main` — stable integrated product.
- `feature/recurring-tasks-v1` — current work.
- `feature/progress-streaks-v1` — paused groundwork; resume after reminders.

## Decision log

- **2026-08-30:** Scheduler/calendar merged to `main` as PR #2.
- **2026-08-30:** Progress/streaks accepted as a generic core system, not book-only.
- **2026-08-30:** Recurring Tasks stays ahead of Progress UI in execution order.
