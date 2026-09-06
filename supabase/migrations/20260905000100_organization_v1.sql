-- Organization V1: projects + task hierarchy + checklist items.
-- All organization records are owner-scoped.

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

drop policy if exists projects_select_own on public.projects;
drop policy if exists projects_insert_own on public.projects;
drop policy if exists projects_update_own on public.projects;
drop policy if exists projects_delete_own on public.projects;
create policy projects_select_own on public.projects for select to authenticated using (user_id = auth.uid());
create policy projects_insert_own on public.projects for insert to authenticated with check (user_id = auth.uid());
create policy projects_update_own on public.projects for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy projects_delete_own on public.projects for delete to authenticated using (user_id = auth.uid());

-- Existing task.project_id is retained as the application contract.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='tasks' and column_name='project_id')
     and not exists (
       select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace
       where n.nspname='public' and t.relname='tasks' and c.contype='f' and pg_get_constraintdef(c.oid) like '%(project_id)%'
     ) then
    alter table public.tasks add constraint tasks_project_id_fkey foreign key (project_id) references public.projects(id) on delete set null;
  end if;
end $$;
create index if not exists tasks_project_id_idx on public.tasks(project_id) where project_id is not null;

-- Self-reference for subtasks.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='tasks' and column_name='parent_task_id')
     and not exists (
       select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace
       where n.nspname='public' and t.relname='tasks' and c.contype='f' and pg_get_constraintdef(c.oid) like '%(parent_task_id)%'
     ) then
    alter table public.tasks add constraint tasks_parent_task_id_fkey foreign key (parent_task_id) references public.tasks(id) on delete cascade;
  end if;
end $$;
create index if not exists tasks_parent_task_id_idx on public.tasks(parent_task_id) where parent_task_id is not null;

-- Enforce hierarchy ownership and prevent self-parenting even for direct database writes.
create or replace function public.validate_task_organization_links()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  parent_user uuid;
  parent_project uuid;
  project_user uuid;
begin
  if new.parent_task_id is not null then
    if new.parent_task_id = new.id then
      raise exception 'A task cannot be its own parent.' using errcode = '23514';
    end if;
    select user_id, project_id into parent_user, parent_project
      from public.tasks where id = new.parent_task_id;
    if parent_user is null or parent_user <> new.user_id then
      raise exception 'Parent task must belong to the same user.' using errcode = '42501';
    end if;
    if new.project_id is distinct from parent_project then
      raise exception 'Subtask must belong to the same project as its parent.' using errcode = '23514';
    end if;
  end if;
  if new.project_id is not null then
    select user_id into project_user from public.projects where id = new.project_id;
    if project_user is null or project_user <> new.user_id then
      raise exception 'Project must belong to the same user as the task.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists validate_task_organization_links on public.tasks;
create trigger validate_task_organization_links
before insert or update of user_id, project_id, parent_task_id on public.tasks
for each row execute function public.validate_task_organization_links();

create table if not exists public.checklist_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 240),
  is_completed boolean not null default false,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists checklist_items_task_idx on public.checklist_items(task_id, position, created_at);
create index if not exists checklist_items_user_idx on public.checklist_items(user_id);
alter table public.checklist_items enable row level security;

drop policy if exists checklist_items_select_own on public.checklist_items;
drop policy if exists checklist_items_insert_own on public.checklist_items;
drop policy if exists checklist_items_update_own on public.checklist_items;
drop policy if exists checklist_items_delete_own on public.checklist_items;
create policy checklist_items_select_own on public.checklist_items for select to authenticated using (user_id = auth.uid());
create policy checklist_items_insert_own on public.checklist_items for insert to authenticated with check (user_id = auth.uid());
create policy checklist_items_update_own on public.checklist_items for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy checklist_items_delete_own on public.checklist_items for delete to authenticated using (user_id = auth.uid());
