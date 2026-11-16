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
