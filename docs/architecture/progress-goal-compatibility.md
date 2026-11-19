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


## Application-level enforcement for legacy goals

- `hasUsableGoalMetrics` is the shared application predicate: the unit must be a non-empty trimmed string and the target must be finite and greater than zero.
- `ProgressForm` uses that predicate and renders an explanatory message instead of a progress-entry form when a legacy goal has null, blank, or invalid measurement metadata.
- `createGoal` continues to require a non-empty title/unit and a finite positive target for newly created measurable goals.
- `logProgress` re-reads the goal using both `id` and the supplied authenticated `user_id`; it rejects a missing/non-owned goal or one without usable metrics before inserting a progress entry. The existing RLS policy remains the authoritative database ownership boundary.
- Regression coverage verifies the predicate, creation validation, owner-filtered lookup, valid insertion, and rejection of legacy/unconfigured or missing/non-owned goals. CI #324 passed all 66 application tests, the 19-migration PostgreSQL 17 replay, hierarchy checks, typecheck, and production build on code/test commit `771f2b133bafc9cc834442449a07f1bfb4def5f4`.

This guard is application-level, not an atomic database invariant: the current progress-entry RLS check verifies goal ownership but does not independently require non-null measurement metadata. A concurrent metadata change between lookup and insert is therefore not closed by this change. If goal-metric mutation is introduced, enforce the invariant with a separately reviewed database policy/trigger migration after the backup and isolated-restore gate is satisfied. No production RLS change is authorized by this checkpoint.

## Verification

- [CI #321](https://github.com/mohith-krishnaa/personal-os/actions/runs/44597240060) passed on code/test commit `9cf0327b94c0238783cdd3c9d0a95978f01ce035`: all 19 migrations replayed on PostgreSQL 17; the new goal-metric compatibility regression, Organization/RLS assertions, task hierarchy checks, application tests, TypeScript typecheck, and production build passed.
- `supabase/tests/progress-goal-compatibility.sql` verifies that `unit` is nullable text and `target` is nullable numeric; both named constraints exist and are validated; legacy goals with null metrics and valid measurable goals are accepted; whitespace-only units and zero/negative targets are rejected. The test transaction rolls back.
- Read-only preflight query 4 now lists both metrics, and query 12 reports their expected types, nullability, constraint presence, validation state, and definitions. Executing query 12 against live Supabase confirms both columns and constraints are still absent because the repair migration remains unapplied.

This does not authorize production DDL. The migration remains unapplied until a complete owner-controlled schema/data/roles backup is successfully restored in isolation and the production rollout is separately approved.


## Legacy-goal aggregation and dashboard read path

- `getGoalsWithProgress` reads goals through the authenticated Supabase client; the goals query is constrained by the table's existing owner RLS policy.
- It fetches progress entries only for the goal IDs returned by that RLS-scoped query. The progress-entry table's owner RLS policy remains authoritative for row visibility.
- Entries are grouped by `goal_id` while preserving the database's descending `occurred_on` order. The grouping loop appends in linear time rather than copying each accumulated array on every entry.
- Legacy goals with NULL `unit` and `target` remain in the result. Their historical entries, total, and streak are retained; progress percentage remains zero because no target is invented. The dashboard displays “Target not set” and does not offer the progress-entry form.
- Errors from either the goals query or progress-entry query are propagated; the dashboard must not silently present a partial or empty history when a read fails.
- CI #327 passed on code/test head `c9329a95b770b55168e85d349b1bd2fbde3e8bd8`: 71/71 application tests, 19-migration PostgreSQL 17 replay, Organization/RLS assertions, hierarchy checks, typecheck, and production build. New tests cover legacy grouping, measurable-goal aggregation, empty-goal short-circuiting, empty progress results, and both query-error paths.
