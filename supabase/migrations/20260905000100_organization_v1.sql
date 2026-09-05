-- Organization V1: projects + task ownership relationship.
-- Projects are owner-scoped. Tasks may optionally belong to one project.

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  description text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists projects_user_id_idx on public.projects(user_id);

alter table public.projects enable row level security;

create policy projects_select_own on public.projects
  for select to authenticated using (user_id = auth.uid());
create policy projects_insert_own on public.projects
  for insert to authenticated with check (user_id = auth.uid());
create policy projects_update_own on public.projects
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy projects_delete_own on public.projects
  for delete to authenticated using (user_id = auth.uid());

-- Existing task.project_id is retained as the application contract; add the
-- foreign key only when the column exists and no equivalent constraint exists.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tasks' and column_name = 'project_id'
  ) and not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public' and t.relname = 'tasks'
      and c.contype = 'f'
      and pg_get_constraintdef(c.oid) like '%(project_id)%'
  ) then
    alter table public.tasks
      add constraint tasks_project_id_fkey
      foreign key (project_id) references public.projects(id) on delete set null;
  end if;
end $$;

create index if not exists tasks_project_id_idx on public.tasks(project_id)
  where project_id is not null;
