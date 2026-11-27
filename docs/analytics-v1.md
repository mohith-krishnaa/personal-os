# Analytics V1

Analytics V1 is a no-cost review page built from the user's existing Personal OS data. It adds no third-party analytics provider, tracking script, database migration, or production setting.

## Reviews

The dashboard provides current calendar-week and current calendar-month views, each compared with the preceding matching calendar period. Dates and boundaries use UTC and the page labels that choice. Each daily bucket reports completed tasks and the number of goal progress entries logged.

The summary reports tasks completed, tasks created, progress-entry count, and planned versus actual minutes. Goal totals are displayed separately by goal and unit because pages, kilometres, and other custom units cannot be meaningfully added together.

## Data and calculations

- Task completion uses `tasks.status` and `tasks.completed_at`.
- Task creation uses `tasks.created_at`.
- Planned versus actual time includes only completed tasks with both `estimated_minutes` and `actual_minutes` recorded. Actual minutes are entered through the existing task editor; zero is valid.
- Goal activity uses `progress_entries.occurred_on`, `goal_id`, and `value`; each goal's value is shown with that goal's configured unit.
- Review queries use the authenticated Supabase server client, so the existing owner RLS policies remain the authorization boundary.
- The comparison note about estimate accuracy is shown only after at least three completed tasks have both time values recorded. Other notes compare observed completion counts and progress-entry counts; they do not predict future behavior.

## Limits

UTC defines review-day boundaries until the product has a user timezone setting. Planned versus actual totals are intentionally blank in practice until time estimates and actual minutes are entered. The progress chart counts entries across goals while the separate goal list preserves unit meaning.

## Verification

Analytics calculation tests cover UTC week/month boundaries, date inclusion, completion and progress grouping, custom-unit separation, and the minimum sample for time-estimate notes. Task update tests cover non-negative whole-minute validation. The application CI also replays migrations and runs the existing RLS, application, typecheck, and build checks.

