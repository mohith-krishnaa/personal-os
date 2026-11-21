-- Make auth.uid() evaluation initplan-safe in reminder and progress policies.
-- Preserve each existing command, role, ownership predicate, and goal/task
-- relationship check; only wrap auth.uid() in a scalar SELECT.
drop policy if exists reminders_owner_select on public.reminders;
create policy reminders_owner_select on public.reminders
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists reminders_owner_insert on public.reminders;
create policy reminders_owner_insert on public.reminders
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists reminders_owner_update on public.reminders;
create policy reminders_owner_update on public.reminders
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists reminders_owner_delete on public.reminders;
create policy reminders_owner_delete on public.reminders
  for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists notifications_owner_select on public.notifications;
create policy notifications_owner_select on public.notifications
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists notifications_owner_update on public.notifications;
create policy notifications_owner_update on public.notifications
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can read own progress" on public.progress_entries;
create policy "Users can read own progress" on public.progress_entries
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can create own progress" on public.progress_entries;
create policy "Users can create own progress" on public.progress_entries
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.goals g
      where g.id = progress_entries.goal_id
        and g.user_id = (select auth.uid())
    )
  );

drop policy if exists "Users can update own progress" on public.progress_entries;
create policy "Users can update own progress" on public.progress_entries
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.goals g
      where g.id = progress_entries.goal_id
        and g.user_id = (select auth.uid())
    )
  );

drop policy if exists "Users can delete own progress" on public.progress_entries;
create policy "Users can delete own progress" on public.progress_entries
  for delete to authenticated
  using ((select auth.uid()) = user_id);
