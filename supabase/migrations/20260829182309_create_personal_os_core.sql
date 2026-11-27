create table if not exists public.profiles (id uuid primary key references auth.users(id) on delete cascade, display_name text, timezone text not null default 'UTC', created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table if not exists public.goals (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, title text not null, description text, status text not null default 'ACTIVE' check (status in ('ACTIVE','COMPLETED','ARCHIVED')), priority text not null default 'MEDIUM' check (priority in ('LOW','MEDIUM','HIGH')), start_date date, target_date date, created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table if not exists public.projects (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, goal_id uuid references public.goals(id) on delete set null, title text not null, description text, status text not null default 'ACTIVE' check (status in ('ACTIVE','COMPLETED','ARCHIVED')), priority text not null default 'MEDIUM' check (priority in ('LOW','MEDIUM','HIGH')), start_date date, target_date date, created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table if not exists public.tasks (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, project_id uuid references public.projects(id) on delete set null, parent_task_id uuid references public.tasks(id) on delete cascade, title text not null, description text, status text not null default 'TODO' check (status in ('BACKLOG','TODO','IN_PROGRESS','COMPLETED','CANCELLED')), priority text not null default 'MEDIUM' check (priority in ('LOW','MEDIUM','HIGH')), due_at timestamptz, scheduled_start timestamptz, scheduled_end timestamptz, estimated_minutes integer check (estimated_minutes is null or estimated_minutes > 0), actual_minutes integer check (actual_minutes is null or actual_minutes >= 0), completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table if not exists public.notes (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, title text not null default '', content text not null default '', archived_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table if not exists public.activity_events (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, event_type text not null, entity_type text, entity_id uuid, occurred_at timestamptz not null default now(), metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());

create index if not exists goals_user_id_idx on public.goals(user_id); create index if not exists projects_user_id_idx on public.projects(user_id); create index if not exists tasks_user_id_status_idx on public.tasks(user_id,status); create index if not exists tasks_user_id_due_at_idx on public.tasks(user_id,due_at); create index if not exists notes_user_id_idx on public.notes(user_id); create index if not exists activity_events_user_id_occurred_at_idx on public.activity_events(user_id,occurred_at desc);

alter table public.profiles enable row level security; alter table public.goals enable row level security; alter table public.projects enable row level security; alter table public.tasks enable row level security; alter table public.notes enable row level security; alter table public.activity_events enable row level security;

create policy profiles_owner on public.profiles for all to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy goals_owner on public.goals for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy projects_owner on public.projects for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy tasks_owner on public.tasks for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy notes_owner on public.notes for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy activity_events_owner on public.activity_events for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create or replace function public.handle_new_user() returns trigger language plpgsql security invoker set search_path = public as $$ begin insert into public.profiles (id, display_name) values (new.id, coalesce(new.raw_user_meta_data->>'full_name','')); return new; end; $$;

 drop trigger if exists on_auth_user_created on auth.users; create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
