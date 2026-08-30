create table if not exists public.goals (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, title text not null, unit text not null, target numeric not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), constraint goals_target_positive check (target > 0), constraint goals_title_nonempty check (length(trim(title)) > 0), constraint goals_unit_nonempty check (length(trim(unit)) > 0));

create table if not exists public.progress_entries (id uuid primary key default gen_random_uuid(), goal_id uuid not null references public.goals(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade, value numeric not null, occurred_on date not null, created_at timestamptz not null default now(), constraint progress_entries_value_positive check (value > 0));

create index if not exists goals_user_created_idx on public.goals(user_id, created_at desc);
create index if not exists progress_entries_goal_date_idx on public.progress_entries(goal_id, occurred_on desc);
create index if not exists progress_entries_user_date_idx on public.progress_entries(user_id, occurred_on desc);

alter table public.goals enable row level security;
alter table public.progress_entries enable row level security;

create policy "Users can read own goals" on public.goals for select to authenticated using (auth.uid() = user_id);
create policy "Users can create own goals" on public.goals for insert to authenticated with check (auth.uid() = user_id);
create policy "Users can update own goals" on public.goals for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users can delete own goals" on public.goals for delete to authenticated using (auth.uid() = user_id);

create policy "Users can read own progress" on public.progress_entries for select to authenticated using (auth.uid() = user_id);
create policy "Users can create own progress" on public.progress_entries for insert to authenticated with check (auth.uid() = user_id and exists (select 1 from public.goals g where g.id = goal_id and g.user_id = auth.uid()));
create policy "Users can update own progress" on public.progress_entries for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id and exists (select 1 from public.goals g where g.id = goal_id and g.user_id = auth.uid()));
create policy "Users can delete own progress" on public.progress_entries for delete to authenticated using (auth.uid() = user_id);