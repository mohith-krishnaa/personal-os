-- Organization V1: owner-scoped checklist items attached to tasks.
create table if not exists public.task_checklist_items (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 240),
  is_completed boolean not null default false,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists task_checklist_items_task_idx
  on public.task_checklist_items(task_id, position, created_at);
create index if not exists task_checklist_items_user_idx
  on public.task_checklist_items(user_id);

alter table public.task_checklist_items enable row level security;

create policy task_checklist_items_select_own on public.task_checklist_items
  for select to authenticated using (user_id = auth.uid());
create policy task_checklist_items_insert_own on public.task_checklist_items
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.tasks t
      where t.id = task_id and t.user_id = auth.uid()
    )
  );
create policy task_checklist_items_update_own on public.task_checklist_items
  for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.tasks t
      where t.id = task_id and t.user_id = auth.uid()
    )
  );
create policy task_checklist_items_delete_own on public.task_checklist_items
  for delete to authenticated using (user_id = auth.uid());
