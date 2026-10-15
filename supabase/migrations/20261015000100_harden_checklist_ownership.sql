-- Harden checklist ownership at the database boundary.
-- Application checks are useful, but RLS must also prevent a user from
-- attaching checklist records to another user's task via direct API writes.

drop policy if exists checklist_items_insert_own on public.checklist_items;
create policy checklist_items_insert_own on public.checklist_items
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.tasks t
      where t.id = task_id and t.user_id = auth.uid()
    )
  );

drop policy if exists checklist_items_update_own on public.checklist_items;
create policy checklist_items_update_own on public.checklist_items
  for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.tasks t
      where t.id = task_id and t.user_id = auth.uid()
    )
  );
