# Progress goal metrics — legacy schema compatibility

Status: forward-only compatibility migration added on `feature/organization-v1`; not applied to Supabase production.

## Verified mismatch

The live `public.goals` table contains the original core columns (`id`, `user_id`, `title`, `description`, `status`, `priority`, date fields, and timestamps), but it does not contain `unit` or `target`.

The application progress service selects `unit` and `target` on every dashboard load and inserts them when creating a measurable goal. The original `20260830141616_progress_goals_v1.sql` used `CREATE TABLE IF NOT EXISTS public.goals`; because the core migration had already created that table, the Progress V1 table definition and its columns/constraints were skipped. A missing-column error from the dashboard query is therefore expected against the currently inspected live schema.

## Decision

- Do not rewrite the already-applied migration history.
- Add `20261117000100_reconcile_progress_goal_metrics.sql` as a forward-only repair.
- Add `unit text` and `target numeric` as nullable columns so legacy non-measurable goals remain intact; enforce non-empty units and positive targets whenever values are present.
- Keep application creation validation strict: newly created measurable goals require both values.
- Render legacy goals without metrics as readable records and omit the progress-entry form until metrics exist. Do not fabricate a target or unit for existing goals.

## Verification

- [CI #321](https://github.com/mohith-krishnaa/personal-os/actions/runs/44597240060) passed on code/test commit `9cf0327b94c0238783cdd3c9d0a95978f01ce035`: all 19 migrations replayed on PostgreSQL 17; the new goal-metric compatibility regression, Organization/RLS assertions, task hierarchy checks, application tests, TypeScript typecheck, and production build passed.
- `supabase/tests/progress-goal-compatibility.sql` verifies that `unit` is nullable text and `target` is nullable numeric; both named constraints exist and are validated; legacy goals with null metrics and valid measurable goals are accepted; whitespace-only units and zero/negative targets are rejected. The test transaction rolls back.
- Read-only preflight query 4 now lists both metrics, and query 12 reports their expected types, nullability, constraint presence, validation state, and definitions. Executing query 12 against live Supabase confirms both columns and constraints are still absent because the repair migration remains unapplied.

This does not authorize production DDL. The migration remains unapplied until a complete owner-controlled schema/data/roles backup is successfully restored in isolation and the production rollout is separately approved.
