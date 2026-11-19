-- Remove redundant legacy goals policies.
-- The core migration already installs goals_owner for all commands with
-- an initplan-safe (select auth.uid()) predicate. The four later command-
-- specific policies duplicate that authorization and add per-row auth.uid()
-- evaluation plus multiple-permissive-policy overhead.
-- Keep goals_owner as the single owner-scoped policy for authenticated users.
drop policy if exists "Users can read own goals" on public.goals;
drop policy if exists "Users can create own goals" on public.goals;
drop policy if exists "Users can update own goals" on public.goals;
drop policy if exists "Users can delete own goals" on public.goals;
