-- Personal OS / Organization V1 database preflight.
-- READ ONLY: this file intentionally contains SELECT statements only.
-- Run in Supabase SQL Editor. Do not append DDL or DML to this file.

-- 1. Connection and PostgreSQL version.
select
  now() as inspected_at,
  current_database() as database_name,
  current_setting('server_version') as server_version;

-- 2. Authoritative migration ledger.
select version, name
from supabase_migrations.schema_migrations
order by version;

-- 3. Required Organization tables and their RLS state.
with expected_tables(table_name) as (
  values
    ('projects'),
    ('tasks'),
    ('checklist_items'),
    ('task_checklist_items')
)
select
  e.table_name,
  c.oid is not null as exists,
  coalesce(c.relrowsecurity, false) as rls_enabled,
  coalesce(c.relforcerowsecurity, false) as force_rls
from expected_tables e
left join pg_class c
  on c.oid = to_regclass(format('public.%I', e.table_name))
order by e.table_name;

-- 4. Organization columns expected by the application and migrations.
with expected_columns(table_name, column_name) as (
  values
    ('projects', 'id'),
    ('projects', 'user_id'),
    ('projects', 'goal_id'),
    ('projects', 'title'),
    ('projects', 'name'),
    ('projects', 'status'),
    ('projects', 'priority'),
    ('projects', 'start_date'),
    ('projects', 'target_date'),
    ('tasks', 'id'),
    ('tasks', 'user_id'),
    ('tasks', 'project_id'),
    ('tasks', 'parent_task_id'),
    ('checklist_items', 'id'),
    ('checklist_items', 'user_id'),
    ('checklist_items', 'task_id'),
    ('checklist_items', 'title'),
    ('checklist_items', 'is_completed'),
    ('checklist_items', 'position'),
    ('task_checklist_items', 'id'),
    ('task_checklist_items', 'user_id'),
    ('task_checklist_items', 'task_id'),
    ('task_checklist_items', 'title'),
    ('task_checklist_items', 'is_completed'),
    ('task_checklist_items', 'position')
)
select
  e.table_name,
  e.column_name,
  c.data_type,
  c.is_nullable,
  c.column_default,
  c.column_name is not null as present
from expected_columns e
left join information_schema.columns c
  on c.table_schema = 'public'
 and c.table_name = e.table_name
 and c.column_name = e.column_name
order by e.table_name, e.column_name;

-- 5. Current owner policies for Organization and related tables.
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('projects', 'tasks', 'checklist_items', 'task_checklist_items', 'goals')
order by tablename, policyname;

-- 6. User-defined triggers on Organization tables.
select
  c.relname as table_name,
  t.tgname as trigger_name,
  p.proname as function_name,
  pg_get_triggerdef(t.oid) as trigger_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where not t.tgisinternal
  and n.nspname = 'public'
  and c.relname in ('projects', 'tasks', 'checklist_items', 'task_checklist_items')
order by c.relname, t.tgname;

-- 7. Constraints and foreign keys.
select
  c.relname as table_name,
  con.conname as constraint_name,
  con.contype as constraint_type,
  pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('projects', 'tasks', 'checklist_items', 'task_checklist_items')
order by c.relname, con.conname;

-- 8. Indexes relevant to Organization queries and foreign keys.
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('projects', 'tasks', 'checklist_items', 'task_checklist_items')
order by tablename, indexname;

-- 9. Expected foreign-key index status (Organization plus the related reminder FK).
with expected_indexes(table_name, column_name, index_name) as (
  values
    ('tasks', 'project_id', 'tasks_project_id_idx'),
    ('tasks', 'parent_task_id', 'tasks_parent_task_id_idx'),
    ('projects', 'goal_id', 'projects_goal_id_idx'),
    ('notifications', 'task_id', 'notifications_task_id_idx')
)
select
  e.table_name,
  e.column_name,
  e.index_name,
  i.indexrelid is not null as index_exists,
  coalesce(i.indisready, false) as index_ready,
  coalesce(i.indisvalid, false) as index_valid,
  pg_get_indexdef(i.indexrelid) as index_definition
from expected_indexes e
left join pg_class t
  on t.oid = to_regclass(format('public.%I', e.table_name))
left join pg_class idx
  on idx.relnamespace = 'public'::regnamespace
 and idx.relname = e.index_name
left join pg_index i
  on i.indexrelid = idx.oid
 and i.indrelid = t.oid
order by e.table_name, e.column_name;
