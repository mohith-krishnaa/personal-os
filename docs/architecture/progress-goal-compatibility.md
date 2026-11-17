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

The migration replay CI applies the complete numbered migration sequence against a disposable PostgreSQL 17 database and asserts that both columns exist after replay. A unit test verifies that legacy goals without a target produce a safe 0% progress summary. CI must pass tests, typecheck, and production build on the current branch head.

This does not authorize production DDL. The migration remains unapplied until a private backup/restore path is established and the production rollout is separately approved.
