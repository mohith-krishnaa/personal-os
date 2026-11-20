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
  expected_delete_action, delete_action_code,
  expected_update_action, update_action_code
) as (
  values
    ('tasks', 'project_id', 'projects', 'id', 'SET NULL', 'n'::"char", 'NO ACTION', 'a'::"char"),
    ('tasks', 'parent_task_id', 'tasks', 'id', 'CASCADE', 'c'::"char", 'NO ACTION', 'a'::"char"),
    ('projects', 'goal_id', 'goals', 'id', 'SET NULL', 'n'::"char", 'NO ACTION', 'a'::"char"),
    ('checklist_items', 'task_id', 'tasks', 'id', 'CASCADE', 'c'::"char", 'NO ACTION', 'a'::"char"),
    ('task_checklist_items', 'task_id', 'tasks', 'id', 'CASCADE', 'c'::"char", 'NO ACTION', 'a'::"char")
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
  e.expected_update_action,
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
    and candidate.confupdtype = e.update_action_code
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


-- 15. Atomic reminder delivery worker contract.
-- The RPC must create the notification and activity event before committing
-- delivered_at, while retaining SKIP LOCKED and service_role-only execution.
select
  p.oid::regprocedure::text as function_signature,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  position('INSERT INTO public.notifications' in pg_get_functiondef(p.oid)) > 0 as inserts_notification,
  position('INSERT INTO public.activity_events' in pg_get_functiondef(p.oid)) > 0 as inserts_activity_event,
  position('FOR UPDATE OF rm SKIP LOCKED' in pg_get_functiondef(p.oid)) > 0 as skips_locked_reminders,
  has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'claim_due_reminders'
  and pg_get_function_identity_arguments(p.oid) = 'p_limit integer';


-- 16. Transactional task activity-event contract.
select
  t.tgname is not null and t.tgenabled = 'O' as task_activity_trigger_enabled,
  p.prosecdef = false as trigger_is_security_invoker,
  coalesce(p.proconfig, array[]::text[]) @> array['search_path=pg_catalog, public']::text[] as trigger_search_path_safe,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute_trigger,
  has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_can_execute_trigger,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute_trigger,
  has_table_privilege('authenticated', 'public.activity_events', 'INSERT') as authenticated_can_insert_activity_events,
  exists (
    select 1 from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'activity_events'
      and policy.policyname = 'activity_events_select_owner'
      and policy.cmd = 'SELECT'
      and policy.roles @> array['authenticated']::name[]
      and policy.qual ilike '%auth.uid%'
  ) as activity_events_select_owner_policy_present,
  exists (
    select 1 from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'activity_events'
      and policy.policyname = 'activity_events_insert_owner'
      and policy.cmd = 'INSERT'
      and policy.roles @> array['authenticated']::name[]
      and policy.with_check ilike '%auth.uid%'
  ) as activity_events_insert_owner_policy_present,
  not exists (
    select 1 from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'activity_events'
      and policy.cmd in ('ALL', 'UPDATE', 'DELETE')
  ) as activity_events_mutation_policies_absent,
  not has_table_privilege('authenticated', 'public.activity_events', 'UPDATE') as authenticated_cannot_update_activity_events,
  not has_table_privilege('authenticated', 'public.activity_events', 'DELETE') as authenticated_cannot_delete_activity_events,
  not has_table_privilege('authenticated', 'public.activity_events', 'TRUNCATE') as authenticated_cannot_truncate_activity_events
from pg_trigger t
join pg_proc p on p.oid = t.tgfoid
where t.tgrelid = 'public.tasks'::regclass
  and t.tgname = 'tasks_record_activity_event'
  and not t.tgisinternal;

-- 17. Per-owner task create request identity and immutability contract.
-- This query is read-only and reports the request key, payload fingerprint,
-- unique constraint, immutable trigger, SECURITY INVOKER setting, and grants.
WITH trigger_function AS (
  SELECT p.*
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'prevent_task_request_identity_change'
), task_columns AS (
  SELECT
    max(a.attnotnull::int) FILTER (WHERE a.attname = 'client_request_id') = 1 AS request_id_not_null,
    max(pg_get_expr(d.adbin, d.adrelid)) FILTER (WHERE a.attname = 'client_request_id') AS request_id_default,
    bool_or(a.atttypid = 'uuid'::regtype) FILTER (WHERE a.attname = 'client_request_id') AS request_id_is_uuid,
    bool_or(a.atttypid = 'text'::regtype) FILTER (WHERE a.attname = 'client_request_hash') AS request_hash_is_text
  FROM pg_attribute a
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attrelid = 'public.tasks'::regclass
    AND a.attname IN ('client_request_id', 'client_request_hash')
    AND NOT a.attisdropped
)
SELECT
  coalesce(c.request_id_not_null, false) AS task_request_id_not_null,
  c.request_id_default AS task_request_id_default,
  coalesce(c.request_id_is_uuid, false) AS task_request_id_is_uuid,
  coalesce(c.request_hash_is_text, false) AS task_request_hash_is_text,
  EXISTS (
    SELECT 1 FROM pg_constraint con
    WHERE con.conrelid = 'public.tasks'::regclass
      AND con.conname = 'tasks_user_client_request_unique'
      AND con.contype = 'u'
      AND con.convalidated
      AND con.conkey = ARRAY[
        (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.tasks'::regclass AND attname = 'user_id' AND NOT attisdropped),
        (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.tasks'::regclass AND attname = 'client_request_id' AND NOT attisdropped)
      ]::smallint[]
  ) AS task_request_unique_per_owner,
  EXISTS (
    SELECT 1 FROM pg_constraint con
    WHERE con.conrelid = 'public.tasks'::regclass
      AND con.conname = 'tasks_client_request_hash_check'
      AND con.contype = 'c'
      AND con.convalidated
  ) AS task_request_hash_format_check,
  EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.tasks'::regclass
      AND t.tgname = 'tasks_request_identity_immutable'
      AND NOT t.tgisinternal
      AND t.tgenabled = 'O'
  ) AS task_request_identity_trigger_enabled,
  coalesce(p.prosecdef = false, false) AS request_trigger_is_security_invoker,
  coalesce(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public']::text[] AS request_trigger_search_path_safe,
  CASE WHEN p.oid IS NULL THEN false ELSE has_function_privilege('authenticated', p.oid, 'EXECUTE') END AS authenticated_can_execute_request_trigger,
  CASE WHEN p.oid IS NULL THEN false ELSE has_function_privilege('service_role', p.oid, 'EXECUTE') END AS service_role_can_execute_request_trigger,
  CASE WHEN p.oid IS NULL THEN false ELSE has_function_privilege('anon', p.oid, 'EXECUTE') END AS anon_can_execute_request_trigger
FROM task_columns c
LEFT JOIN trigger_function p ON true;

-- 18. Transactional task DELETE event contract.
-- TASK_DELETED is emitted only when the authenticated JWT subject owns the deleted row.
-- Service-role/Auth-account cascades intentionally skip the event so auth.users cleanup
-- can cascade both tasks and activity_events without inserting a row for a deleted user.
WITH task_activity_trigger AS (
  SELECT
    t.oid AS trigger_oid,
    pg_get_triggerdef(t.oid) AS trigger_definition,
    p.oid AS function_oid,
    p.prosecdef,
    p.proconfig,
    p.prosrc
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE t.tgrelid = 'public.tasks'::regclass
    AND t.tgname = 'tasks_record_activity_event'
    AND NOT t.tgisinternal
    AND t.tgenabled = 'O'
)
SELECT
  EXISTS (SELECT 1 FROM task_activity_trigger) AS task_activity_trigger_enabled,
  coalesce((SELECT trigger_definition ILIKE '%DELETE%' FROM task_activity_trigger), false) AS task_delete_event_enabled,
  coalesce((SELECT prosrc LIKE '%TASK_DELETED%' FROM task_activity_trigger), false) AS task_deleted_event_mapping_present,
  coalesce((SELECT prosrc LIKE '%auth.uid() IS DISTINCT FROM OLD.user_id%' FROM task_activity_trigger), false) AS task_delete_owner_context_guard_present,
  coalesce((SELECT prosecdef = false FROM task_activity_trigger), false) AS task_activity_trigger_is_security_invoker,
  coalesce((SELECT proconfig @> ARRAY['search_path=pg_catalog, public']::text[] FROM task_activity_trigger), false) AS task_activity_trigger_search_path_safe,
  CASE WHEN (SELECT function_oid FROM task_activity_trigger) IS NULL THEN false
       ELSE has_function_privilege('authenticated', (SELECT function_oid FROM task_activity_trigger), 'EXECUTE') END AS authenticated_can_execute_task_activity_trigger,
  CASE WHEN (SELECT function_oid FROM task_activity_trigger) IS NULL THEN false
       ELSE has_function_privilege('service_role', (SELECT function_oid FROM task_activity_trigger), 'EXECUTE') END AS service_role_can_execute_task_activity_trigger,
  CASE WHEN (SELECT function_oid FROM task_activity_trigger) IS NULL THEN false
       ELSE has_function_privilege('anon', (SELECT function_oid FROM task_activity_trigger), 'EXECUTE') END AS anon_can_execute_task_activity_trigger,
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tasks'::regclass
      AND conname = 'tasks_parent_task_id_fkey'
      AND contype = 'f'
      AND convalidated
      AND confdeltype = 'c'
  ) AS task_parent_delete_cascade_preserved,
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tasks'::regclass
      AND conname = 'tasks_user_id_fkey'
      AND contype = 'f'
      AND convalidated
      AND confdeltype = 'c'
  ) AS task_owner_delete_cascade_preserved,
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.activity_events'::regclass
      AND conname = 'activity_events_user_id_fkey'
      AND contype = 'f'
      AND convalidated
      AND confdeltype = 'c'
  ) AS activity_owner_delete_cascade_preserved;


-- 19. Append-only activity-event access contract.
-- Application roles may SELECT/INSERT only. The postgres table owner retains
-- controlled maintenance/retention privileges; auth.users FK cleanup still cascades.
WITH event_table AS (
  SELECT
    c.relrowsecurity,
    pg_get_userbyid(c.relowner) AS table_owner
  FROM pg_class c
  WHERE c.oid = to_regclass('public.activity_events')
)
SELECT
  coalesce(event_table.relrowsecurity, false) AS activity_events_rls_enabled,
  event_table.table_owner AS activity_events_table_owner,
  EXISTS (
    SELECT 1 FROM pg_policies policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = 'activity_events'
      AND policy.policyname = 'activity_events_select_owner'
      AND policy.cmd = 'SELECT'
      AND policy.roles @> ARRAY['authenticated']::name[]
      AND policy.qual ILIKE '%auth.uid%'
  ) AS activity_events_select_owner_policy_present,
  EXISTS (
    SELECT 1 FROM pg_policies policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = 'activity_events'
      AND policy.policyname = 'activity_events_insert_owner'
      AND policy.cmd = 'INSERT'
      AND policy.roles @> ARRAY['authenticated']::name[]
      AND policy.with_check ILIKE '%auth.uid%'
  ) AS activity_events_insert_owner_policy_present,
  NOT EXISTS (
    SELECT 1 FROM pg_policies policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = 'activity_events'
      AND policy.cmd IN ('ALL', 'UPDATE', 'DELETE')
  ) AS activity_events_mutation_policies_absent,
  has_table_privilege('authenticated', 'public.activity_events', 'SELECT') AS authenticated_can_select,
  has_table_privilege('authenticated', 'public.activity_events', 'INSERT') AS authenticated_can_insert,
  has_table_privilege('authenticated', 'public.activity_events', 'UPDATE') AS authenticated_can_update,
  has_table_privilege('authenticated', 'public.activity_events', 'DELETE') AS authenticated_can_delete,
  has_table_privilege('authenticated', 'public.activity_events', 'TRUNCATE') AS authenticated_can_truncate,
  has_table_privilege('anon', 'public.activity_events', 'SELECT') AS anon_can_select,
  has_table_privilege('anon', 'public.activity_events', 'INSERT') AS anon_can_insert,
  has_table_privilege('anon', 'public.activity_events', 'UPDATE') AS anon_can_update,
  has_table_privilege('anon', 'public.activity_events', 'DELETE') AS anon_can_delete,
  has_table_privilege('anon', 'public.activity_events', 'TRUNCATE') AS anon_can_truncate,
  has_table_privilege('service_role', 'public.activity_events', 'SELECT') AS service_role_can_select,
  has_table_privilege('service_role', 'public.activity_events', 'INSERT') AS service_role_can_insert,
  has_table_privilege('service_role', 'public.activity_events', 'UPDATE') AS service_role_can_update,
  has_table_privilege('service_role', 'public.activity_events', 'DELETE') AS service_role_can_delete,
  has_table_privilege('service_role', 'public.activity_events', 'TRUNCATE') AS service_role_can_truncate,
  has_table_privilege('postgres', 'public.activity_events', 'DELETE') AS postgres_owner_can_delete_for_maintenance,
  has_table_privilege('postgres', 'public.activity_events', 'TRUNCATE') AS postgres_owner_can_truncate_for_maintenance
FROM event_table;
