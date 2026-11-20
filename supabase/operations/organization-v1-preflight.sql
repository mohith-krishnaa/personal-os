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

-- 4. Organization and Progress compatibility columns expected by the application and migrations.
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
    ('goals', 'unit'),
    ('goals', 'target'),
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

-- 5. Owner and performance-sensitive policies for Organization, reminders, and progress.
-- The related tables are included so rollout can verify the pending initplan-safe RLS repairs.
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
  and tablename in ('projects', 'tasks', 'checklist_items', 'task_checklist_items', 'goals', 'reminders', 'notifications', 'progress_entries')
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

-- 10. Project name/title compatibility safety check.
-- Uses row JSON so this query works both before and after the name column is added.
-- Do not apply the compatibility migration if blocking rows or existing column drift are reported.
with project_values as (
  select
    to_jsonb(p)->>'name' as app_name,
    to_jsonb(p)->>'title' as legacy_title
  from public.projects p
),
normalized as (
  select
    app_name,
    legacy_title,
    coalesce(app_name, legacy_title) as resulting_name
  from project_values
)
select
  count(*) as total_projects,
  count(*) filter (
    where resulting_name is null
       or char_length(trim(resulting_name)) not between 1 and 120
       or resulting_name !~ '[^[:space:]]'
  ) as rows_blocking_name_compatibility,
  count(*) filter (
    where app_name is not null
      and legacy_title is not null
      and app_name is distinct from legacy_title
  ) as rows_with_name_title_drift
from normalized;

-- 11. Exact project/task/checklist foreign-key contracts.
-- Report missing, duplicate, unvalidated, incorrectly targeted, or incorrectly configured FKs.
with expected_foreign_keys(
  source_table, source_column, target_table, target_column,
  expected_delete_action, delete_action_code
) as (
  values
    ('tasks', 'project_id', 'projects', 'id', 'SET NULL', 'n'::"char"),
    ('tasks', 'parent_task_id', 'tasks', 'id', 'CASCADE', 'c'::"char"),
    ('projects', 'goal_id', 'goals', 'id', 'SET NULL', 'n'::"char"),
    ('checklist_items', 'task_id', 'tasks', 'id', 'CASCADE', 'c'::"char"),
    ('task_checklist_items', 'task_id', 'tasks', 'id', 'CASCADE', 'c'::"char")
),
resolved as (
  select
    e.*,
    to_regclass(format('public.%I', e.source_table)) as source_oid,
    to_regclass(format('public.%I', e.target_table)) as target_oid
  from expected_foreign_keys e
)
select
  e.source_table,
  e.source_column,
  e.target_table,
  e.target_column,
  e.expected_delete_action,
  con.conname as constraint_name,
  coalesce(con.convalidated, false) as constraint_validated,
  con.oid is not null as exact_constraint_present,
  (
    select count(*)
    from pg_constraint other_con
    where other_con.conrelid = e.source_oid
      and other_con.contype = 'f'
      and (
        select a.attnum from pg_attribute a
        where a.attrelid = e.source_oid
          and a.attname = e.source_column
          and not a.attisdropped
      ) = any(other_con.conkey)
  ) as source_column_foreign_key_count,
  pg_get_constraintdef(con.oid) as actual_definition
from resolved e
left join lateral (
  select candidate.*
  from pg_constraint candidate
  where candidate.conrelid = e.source_oid
    and candidate.confrelid = e.target_oid
    and candidate.contype = 'f'
    and candidate.convalidated
    and candidate.confdeltype = e.delete_action_code
    and candidate.conkey = array[
      (
        select a.attnum from pg_attribute a
        where a.attrelid = e.source_oid
          and a.attname = e.source_column
          and not a.attisdropped
      )
    ]::smallint[]
    and candidate.confkey = array[
      (
        select a.attnum from pg_attribute a
        where a.attrelid = e.target_oid
          and a.attname = e.target_column
          and not a.attisdropped
      )
    ]::smallint[]
  order by candidate.conname
  limit 1
) con on true
order by e.source_table, e.source_column;

-- 12. Progress goal-metric compatibility.
-- Metrics remain nullable for legacy goals; validated checks reject blank units
-- and non-positive targets.
with expected_metrics(column_name, expected_data_type, constraint_name) as (
  values
    ('unit', 'text', 'goals_unit_nonempty'),
    ('target', 'numeric', 'goals_target_positive')
)
select
  e.column_name,
  e.expected_data_type,
  c.data_type,
  c.is_nullable,
  c.column_name is not null as column_present,
  con.conname as constraint_name,
  coalesce(con.convalidated, false) as constraint_validated,
  pg_get_constraintdef(con.oid) as constraint_definition
from expected_metrics e
left join information_schema.columns c
  on c.table_schema = 'public'
 and c.table_name = 'goals'
 and c.column_name = e.column_name
left join pg_constraint con
  on con.conrelid = to_regclass('public.goals')
 and con.conname = e.constraint_name
 and con.contype = 'c'
order by e.column_name;

-- 13. Reminder/notification ownership foreign keys.
-- The composite constraints prevent cross-owner task links and notifications
-- whose task does not match their reminder, including service_role writes.
with expected(table_name, constraint_name, description) as (
  values
    ('reminders', 'reminders_task_owner_fkey', 'FOREIGN KEY (task_id, user_id) REFERENCES tasks(id, user_id) ON DELETE CASCADE'),
    ('notifications', 'notifications_reminder_owner_task_fkey', 'FOREIGN KEY (reminder_id, user_id, task_id) REFERENCES reminders(id, user_id, task_id) ON DELETE CASCADE')
)
select
  e.table_name,
  e.constraint_name,
  e.description as expected_definition,
  con.oid is not null as constraint_present,
  coalesce(con.convalidated, false) as constraint_validated,
  pg_get_constraintdef(con.oid) as actual_definition
from expected e
left join pg_constraint con
  on con.conrelid = to_regclass(format('public.%I', e.table_name))
 and con.conname = e.constraint_name
 and con.contype = 'f'
order by e.table_name, e.constraint_name;

-- 14. Supporting composite unique keys required by the ownership foreign keys.
with expected(table_name, constraint_name) as (
  values
    ('tasks', 'tasks_id_user_id_key'),
    ('reminders', 'reminders_id_user_id_task_id_key')
)
select
  e.table_name,
  e.constraint_name,
  con.oid is not null as constraint_present,
  coalesce(con.convalidated, false) as constraint_validated,
  pg_get_constraintdef(con.oid) as actual_definition
from expected e
left join pg_constraint con
  on con.conrelid = to_regclass(format('public.%I', e.table_name))
 and con.conname = e.constraint_name
 and con.contype = 'u'
order by e.table_name, e.constraint_name;
