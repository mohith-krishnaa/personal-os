create table if not exists public.reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  remind_at timestamptz not null,
  timezone text not null default 'UTC',
  channel text not null default 'IN_APP' check (channel in ('IN_APP')),
  enabled boolean not null default true,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reminders_user_remind_at_idx on public.reminders (user_id, remind_at) where enabled = true;
create index if not exists reminders_task_idx on public.reminders (task_id);

alter table public.reminders enable row level security;

create policy reminders_owner_select on public.reminders
  for select to authenticated
  using (auth.uid() = user_id);

create policy reminders_owner_insert on public.reminders
  for insert to authenticated
  with check (auth.uid() = user_id);

create policy reminders_owner_update on public.reminders
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy reminders_owner_delete on public.reminders
  for delete to authenticated
  using (auth.uid() = user_id);
