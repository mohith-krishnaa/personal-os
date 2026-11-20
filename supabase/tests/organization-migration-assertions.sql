-- Assert that the complete migration chain can be replayed against the legacy
-- core schema and that the resulting Organization boundary holds under RLS.
-- Each owner session also verifies that the other owner cannot UPDATE or DELETE its records.
DO $assert_schema$
DECLARE
  project_name_nullable text;
  project_name_check_valid boolean;
  copied_count integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'goals'
      AND column_name = 'unit' AND data_type = 'text'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'goals'
      AND column_name = 'target' AND data_type = 'numeric'
  ) THEN
    RAISE EXCEPTION 'Progress goal metric columns are missing after the forward compatibility migration.';
  END IF;
  IF to_regclass('public.checklist_items') IS NULL
     OR to_regclass('public.task_checklist_items') IS NULL THEN
    RAISE EXCEPTION 'Both canonical and legacy checklist tables must exist.';
  END IF;

  -- The missing_task report category is a drift detector, not an expected row:
  -- both checklist tables must enforce a non-null, validated task foreign key.
  IF EXISTS (
    WITH expected(table_name, relation_oid) AS (
      VALUES
        ('checklist_items', 'public.checklist_items'::regclass),
        ('task_checklist_items', 'public.task_checklist_items'::regclass)
    )
    SELECT 1
    FROM expected e
    WHERE NOT EXISTS (
      SELECT 1
      FROM pg_attribute a
      WHERE a.attrelid = e.relation_oid
        AND a.attname = 'task_id'
        AND a.attnotnull
        AND NOT a.attisdropped
    )
    OR (
      SELECT count(*)
      FROM pg_constraint con
      WHERE con.conrelid = e.relation_oid
        AND con.contype = 'f'
        AND (
          SELECT a.attnum
          FROM pg_attribute a
          WHERE a.attrelid = e.relation_oid
            AND a.attname = 'task_id'
            AND NOT a.attisdropped
        ) = ANY(con.conkey)
    ) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM pg_constraint con
      WHERE con.conrelid = e.relation_oid
        AND con.contype = 'f'
        AND con.confrelid = 'public.tasks'::regclass
        AND con.convalidated
        AND con.confdeltype = 'c'
        AND con.conkey = ARRAY[
          (
            SELECT a.attnum
            FROM pg_attribute a
            WHERE a.attrelid = e.relation_oid
              AND a.attname = 'task_id'
              AND NOT a.attisdropped
          )
        ]::smallint[]
    )
  ) THEN
    RAISE EXCEPTION 'Each checklist task_id must be NOT NULL and participate in exactly one validated single-column foreign key to public.tasks(id) ON DELETE CASCADE.';
  END IF;

  -- Verify the project/task relationship foreign keys exactly. The migration
  -- conditionally adds these only when no FK mentioning the source column
  -- exists, so a wrong pre-existing FK must fail this replay assertion.
  IF EXISTS (
    WITH expected(
      table_oid, source_column, target_oid, target_column, delete_action
    ) AS (
      VALUES
        ('public.tasks'::regclass, 'project_id', 'public.projects'::regclass, 'id', 'n'::"char"),
        ('public.tasks'::regclass, 'parent_task_id', 'public.tasks'::regclass, 'id', 'c'::"char"),
        ('public.projects'::regclass, 'goal_id', 'public.goals'::regclass, 'id', 'n'::"char")
    )
    SELECT 1
    FROM expected e
    WHERE (
      SELECT count(*)
      FROM pg_constraint con
      WHERE con.conrelid = e.table_oid
        AND con.contype = 'f'
        AND con.conkey = ARRAY[
          (
            SELECT a.attnum
            FROM pg_attribute a
            WHERE a.attrelid = e.table_oid
              AND a.attname = e.source_column
              AND NOT a.attisdropped
          )
        ]::smallint[]
    ) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM pg_constraint con
      WHERE con.conrelid = e.table_oid
        AND con.confrelid = e.target_oid
        AND con.contype = 'f'
        AND con.convalidated
        AND con.confdeltype = e.delete_action
        AND con.conkey = ARRAY[
          (
            SELECT a.attnum
            FROM pg_attribute a
            WHERE a.attrelid = e.table_oid
              AND a.attname = e.source_column
              AND NOT a.attisdropped
          )
        ]::smallint[]
        AND con.confkey = ARRAY[
          (
            SELECT a.attnum
            FROM pg_attribute a
            WHERE a.attrelid = e.target_oid
              AND a.attname = e.target_column
              AND NOT a.attisdropped
          )
        ]::smallint[]
    )
  ) THEN
    RAISE EXCEPTION 'Project/task relationship foreign keys must be single-column, validated, and preserve SET NULL/CASCADE delete behavior.';
  END IF;

  SELECT is_nullable INTO project_name_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'projects'
    AND column_name = 'name';

  IF project_name_nullable IS DISTINCT FROM 'NO' THEN
    RAISE EXCEPTION 'projects.name must exist and be NOT NULL after compatibility migration.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'projects' AND column_name = 'title'
  ) THEN
    RAISE EXCEPTION 'Legacy projects.title must be preserved.';
  END IF;

  SELECT convalidated INTO project_name_check_valid
  FROM pg_constraint
  WHERE conrelid = 'public.projects'::regclass
    AND conname = 'projects_name_length_check'
    AND contype = 'c';

  IF project_name_check_valid IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'The project name length constraint must exist and be validated.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.projects
    WHERE name IS NULL
       OR char_length(trim(name)) NOT BETWEEN 1 AND 120
       OR title IS DISTINCT FROM name
  ) THEN
    RAISE EXCEPTION 'Existing project name/title values are invalid or inconsistent.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'tasks'
      AND t.tgname = 'validate_task_organization_links' AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Task organization validation trigger is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'projects'
      AND t.tgname = 'sync_project_name_title' AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Project name/title compatibility trigger is missing.';
  END IF;

  -- The pending rollout must install valid indexes for the Organization
  -- foreign keys and the legacy project-to-goal relationship.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = 'public.tasks'::regclass
      AND idx.relname = 'tasks_project_id_idx'
      AND i.indisvalid AND i.indisready
  ) THEN
    RAISE EXCEPTION 'A valid index for tasks.project_id is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = 'public.tasks'::regclass
      AND idx.relname = 'tasks_parent_task_id_idx'
      AND i.indisvalid AND i.indisready
  ) THEN
    RAISE EXCEPTION 'A valid index for tasks.parent_task_id is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = 'public.projects'::regclass
      AND idx.relname = 'projects_goal_id_idx'
      AND i.indisvalid AND i.indisready
  ) THEN
    RAISE EXCEPTION 'A valid index for projects.goal_id is missing.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES ('projects'), ('tasks'), ('checklist_items'), ('task_checklist_items')) AS expected(table_name)
    JOIN pg_class c ON c.oid = to_regclass(format('public.%I', expected.table_name))
    WHERE NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'An Organization table is missing row-level security.';
  END IF;

  -- Assert the complete Organization policy matrix, not just representative rows.
  IF (
    SELECT count(*)
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('projects', 'tasks', 'checklist_items', 'task_checklist_items')
  ) <> 13 THEN
    RAISE EXCEPTION 'Expected exactly thirteen owner-scoped Organization policies.';
  END IF;

  IF EXISTS (
    WITH expected(tablename, policyname, command_name, needs_using, needs_check, needs_task_link) AS (
      VALUES
        ('projects', 'projects_select_own', 'SELECT', true, false, false),
        ('projects', 'projects_insert_own', 'INSERT', false, true, false),
        ('projects', 'projects_update_own', 'UPDATE', true, true, false),
        ('projects', 'projects_delete_own', 'DELETE', true, false, false),
        ('tasks', 'tasks_owner', 'ALL', true, true, false),
        ('checklist_items', 'checklist_items_select_own', 'SELECT', true, false, true),
        ('checklist_items', 'checklist_items_insert_own', 'INSERT', false, true, true),
        ('checklist_items', 'checklist_items_update_own', 'UPDATE', true, true, true),
        ('checklist_items', 'checklist_items_delete_own', 'DELETE', true, false, false),
        ('task_checklist_items', 'task_checklist_items_select_own', 'SELECT', true, false, true),
        ('task_checklist_items', 'task_checklist_items_insert_own', 'INSERT', false, true, true),
        ('task_checklist_items', 'task_checklist_items_update_own', 'UPDATE', true, true, true),
        ('task_checklist_items', 'task_checklist_items_delete_own', 'DELETE', true, false, false)
    )
    SELECT 1
    FROM expected e
    LEFT JOIN pg_policies p
      ON p.schemaname = 'public'
     AND p.tablename = e.tablename
     AND p.policyname = e.policyname
    WHERE p.policyname IS NULL
       OR p.roles <> ARRAY['authenticated']::name[]
       OR p.cmd <> e.command_name
       OR (
         e.needs_using
         AND (
           coalesce(p.qual, '') NOT LIKE '%SELECT auth.uid()%'
           OR coalesce(p.qual, '') NOT LIKE '%user_id%'
         )
       )
       OR (
         e.needs_check
         AND (
           coalesce(p.with_check, '') NOT LIKE '%SELECT auth.uid()%'
           OR coalesce(p.with_check, '') NOT LIKE '%user_id%'
         )
       )
       OR (
         e.needs_task_link
         AND (
           coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '') NOT LIKE '%EXISTS%'
           OR coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '') NOT LIKE '%t.user_id%'
           OR coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '') NOT LIKE '%SELECT auth.uid()%'
         )
       )
  ) THEN
    RAISE EXCEPTION 'An Organization policy changed its authenticated role, command, owner predicate, or task ownership check.';
  END IF;

  -- goals_owner is the single owner-scoped policy after deduplication.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'goals'
      AND policyname = 'goals_owner' AND cmd = 'ALL'
      AND roles = ARRAY['authenticated']::name[]
      AND qual LIKE '%SELECT auth.uid()%'
      AND with_check LIKE '%SELECT auth.uid()%'
      AND qual LIKE '%user_id%'
      AND with_check LIKE '%user_id%'
  ) THEN
    RAISE EXCEPTION 'The canonical authenticated goals_owner policy is missing.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'goals'
      AND policyname IN (
        'Users can read own goals',
        'Users can create own goals',
        'Users can update own goals',
        'Users can delete own goals'
      )
  ) THEN
    RAISE EXCEPTION 'Redundant legacy goals policies remain after deduplication.';
  END IF;

  -- The ten reminder/notification/progress policies must preserve their
  -- authenticated role, command scope, owner predicates, and progress-goal link.
  IF (
    SELECT count(*)
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('reminders', 'notifications', 'progress_entries')
  ) <> 10 THEN
    RAISE EXCEPTION 'Expected exactly ten reminder, notification, and progress policies.';
  END IF;

  IF EXISTS (
    WITH expected(tablename, policyname, command_name, needs_using, needs_check, needs_goal_link) AS (
      VALUES
        ('reminders', 'reminders_owner_select', 'SELECT', true, false, false),
        ('reminders', 'reminders_owner_insert', 'INSERT', false, true, false),
        ('reminders', 'reminders_owner_update', 'UPDATE', true, true, false),
        ('reminders', 'reminders_owner_delete', 'DELETE', true, false, false),
        ('notifications', 'notifications_owner_select', 'SELECT', true, false, false),
        ('notifications', 'notifications_owner_update', 'UPDATE', true, true, false),
        ('progress_entries', 'Users can read own progress', 'SELECT', true, false, false),
        ('progress_entries', 'Users can create own progress', 'INSERT', false, true, true),
        ('progress_entries', 'Users can update own progress', 'UPDATE', true, true, true),
        ('progress_entries', 'Users can delete own progress', 'DELETE', true, false, false)
    )
    SELECT 1
    FROM expected e
    LEFT JOIN pg_policies p
      ON p.schemaname = 'public'
     AND p.tablename = e.tablename
     AND p.policyname = e.policyname
    WHERE p.policyname IS NULL
       OR p.roles <> ARRAY['authenticated']::name[]
       OR p.cmd <> e.command_name
       OR (
         e.needs_using
         AND (
           coalesce(p.qual, '') NOT LIKE '%SELECT auth.uid()%'
           OR coalesce(p.qual, '') NOT LIKE '%user_id%'
         )
       )
       OR (
         e.needs_check
         AND (
           coalesce(p.with_check, '') NOT LIKE '%SELECT auth.uid()%'
           OR coalesce(p.with_check, '') NOT LIKE '%user_id%'
         )
       )
       OR (
         e.needs_goal_link
         AND (
           coalesce(p.with_check, '') NOT LIKE '%goal_id%'
           OR coalesce(p.with_check, '') NOT LIKE '%g.user_id%'
         )
       )
  ) THEN
    RAISE EXCEPTION 'A reminder, notification, or progress policy changed role, command, owner, or goal-link semantics.';
  END IF;

  -- No policy in this set may retain a direct per-row auth.uid() expression.
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('reminders', 'notifications', 'progress_entries')
      AND (
        coalesce(qual, '') LIKE '%auth.uid()%'
          AND coalesce(qual, '') NOT LIKE '%SELECT auth.uid()%'
        OR coalesce(with_check, '') LIKE '%auth.uid()%'
          AND coalesce(with_check, '') NOT LIKE '%SELECT auth.uid()%'
      )
  ) THEN
    RAISE EXCEPTION 'A reminder, notification, or progress policy still evaluates auth.uid() per row.';
  END IF;

  IF has_function_privilege('anon', 'public.rls_auto_enable()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.rls_auto_enable()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Client roles must not execute rls_auto_enable().';
  END IF;

  IF NOT has_function_privilege('service_role', 'public.rls_auto_enable()', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role must retain the pre-existing rls_auto_enable() grant.';
  END IF;

  SELECT count(*) INTO copied_count
  FROM public.checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000001';

  IF copied_count <> 1 THEN
    RAISE EXCEPTION 'A valid Owner A legacy checklist item was not reconciled.';
  END IF;

  SELECT count(*) INTO copied_count
  FROM public.checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000003';

  IF copied_count <> 1 THEN
    RAISE EXCEPTION 'A valid Owner B legacy checklist item was not reconciled.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.checklist_items
    WHERE id = '30000000-0000-4000-8000-000000000002'
  ) THEN
    RAISE EXCEPTION 'A legacy checklist item attached to another owner task was copied.';
  END IF;

  -- A primary-key collision must not overwrite or take ownership of the
  -- pre-existing canonical row. The legacy source row must remain intact.
  SELECT count(*) INTO copied_count
  FROM public.checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000005'
    AND user_id = '22222222-2222-4222-8222-222222222222'
    AND task_id = '20000000-0000-4000-8000-000000000001'
    AND title = 'Pre-existing canonical record wins'
    AND is_completed IS TRUE
    AND position = 9;

  IF copied_count <> 1 THEN
    RAISE EXCEPTION 'Checklist reconciliation overwrote or removed the pre-existing canonical record on ID collision.';
  END IF;

  SELECT count(*) INTO copied_count
  FROM public.task_checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000005'
    AND user_id = '11111111-1111-4111-8111-111111111111'
    AND task_id = '10000000-0000-4000-8000-000000000001'
    AND title = 'Legacy record with colliding ID'
    AND is_completed IS FALSE
    AND position = 4;

  IF copied_count <> 1 THEN
    RAISE EXCEPTION 'Checklist reconciliation removed or changed the legacy source row on ID collision.';
  END IF;

  SELECT count(*) INTO copied_count
  FROM public.checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000005'
    AND user_id = '11111111-1111-4111-8111-111111111111';

  IF copied_count <> 0 THEN
    RAISE EXCEPTION 'Checklist reconciliation transferred a conflicting canonical ID to the legacy owner.';
  END IF;
END
$assert_schema$;

DO $assert_reminder_notification_ownership$
DECLARE
  tasks_id_attnum smallint;
  tasks_user_attnum smallint;
  reminders_id_attnum smallint;
  reminders_user_attnum smallint;
  reminders_task_attnum smallint;
  notifications_reminder_attnum smallint;
  notifications_user_attnum smallint;
  notifications_task_attnum smallint;
BEGIN
  SELECT attnum INTO tasks_id_attnum FROM pg_attribute
  WHERE attrelid = 'public.tasks'::regclass AND attname = 'id' AND NOT attisdropped;
  SELECT attnum INTO tasks_user_attnum FROM pg_attribute
  WHERE attrelid = 'public.tasks'::regclass AND attname = 'user_id' AND NOT attisdropped;
  SELECT attnum INTO reminders_id_attnum FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass AND attname = 'id' AND NOT attisdropped;
  SELECT attnum INTO reminders_user_attnum FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass AND attname = 'user_id' AND NOT attisdropped;
  SELECT attnum INTO reminders_task_attnum FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass AND attname = 'task_id' AND NOT attisdropped;
  SELECT attnum INTO notifications_reminder_attnum FROM pg_attribute
  WHERE attrelid = 'public.notifications'::regclass AND attname = 'reminder_id' AND NOT attisdropped;
  SELECT attnum INTO notifications_user_attnum FROM pg_attribute
  WHERE attrelid = 'public.notifications'::regclass AND attname = 'user_id' AND NOT attisdropped;
  SELECT attnum INTO notifications_task_attnum FROM pg_attribute
  WHERE attrelid = 'public.notifications'::regclass AND attname = 'task_id' AND NOT attisdropped;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tasks'::regclass
      AND conname = 'tasks_id_user_id_key'
      AND contype = 'u' AND convalidated AND NOT condeferrable
      AND conkey = ARRAY[tasks_id_attnum, tasks_user_attnum]::smallint[]
  ) THEN
    RAISE EXCEPTION 'The tasks(id,user_id) unique key required by reminder ownership is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_id_user_id_task_id_key'
      AND contype = 'u' AND convalidated AND NOT condeferrable
      AND conkey = ARRAY[
        reminders_id_attnum, reminders_user_attnum, reminders_task_attnum
      ]::smallint[]
  ) THEN
    RAISE EXCEPTION 'The reminders(id,user_id,task_id) unique key required by notification ownership is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_task_owner_fkey'
      AND contype = 'f'
      AND confrelid = 'public.tasks'::regclass
      AND conkey = ARRAY[reminders_task_attnum, reminders_user_attnum]::smallint[]
      AND confkey = ARRAY[tasks_id_attnum, tasks_user_attnum]::smallint[]
      AND confdeltype = 'c' AND confupdtype = 'a' AND convalidated
  ) THEN
    RAISE EXCEPTION 'The validated reminders_task_owner_fkey owner relationship is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_reminder_owner_task_fkey'
      AND contype = 'f'
      AND confrelid = 'public.reminders'::regclass
      AND conkey = ARRAY[
        notifications_reminder_attnum,
        notifications_user_attnum,
        notifications_task_attnum
      ]::smallint[]
      AND confkey = ARRAY[
        reminders_id_attnum,
        reminders_user_attnum,
        reminders_task_attnum
      ]::smallint[]
      AND confdeltype = 'c' AND confupdtype = 'a' AND convalidated
  ) THEN
    RAISE EXCEPTION 'The validated notifications_reminder_owner_task_fkey owner/task relationship is missing.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_task_id_fkey'
  ) OR EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_reminder_id_fkey'
  ) THEN
    RAISE EXCEPTION 'A weaker single-column reminder ownership foreign key remains.';
  END IF;

  IF (
    SELECT count(*) FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND contype = 'f'
      AND reminders_task_attnum = ANY(conkey)
  ) <> 1 OR (
    SELECT count(*) FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND contype = 'f'
      AND notifications_reminder_attnum = ANY(conkey)
  ) <> 1 THEN
    RAISE EXCEPTION 'Unexpected duplicate foreign keys remain on reminder ownership source columns.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_task_id_fkey'
      AND contype = 'f'
      AND confrelid = 'public.tasks'::regclass
      AND conkey = ARRAY[notifications_task_attnum]::smallint[]
      AND confdeltype = 'c' AND convalidated
  ) THEN
    RAISE EXCEPTION 'The existing notification.task_id cascade foreign key was not preserved.';
  END IF;
END
$assert_reminder_notification_ownership$;

-- Simulate a legacy malformed canonical row whose owner matches the caller
-- but whose task belongs to the other owner. SELECT RLS must hide it. whose owner matches the caller
-- but whose task belongs to the other owner. SELECT RLS must hide it.
INSERT INTO public.checklist_items (id, user_id, task_id, title)
VALUES (
  '30000000-0000-4000-8000-000000000004',
  '11111111-1111-4111-8111-111111111111',
  '20000000-0000-4000-8000-000000000001',
  'Malformed canonical cross-owner task link'
);

-- Dedicated task-delete cascade fixture. Owner A owns a three-level hierarchy,
-- an unrelated task, and a recurring occurrence that references the root only
-- through recurrence_parent_id (not parent_task_id). Owner B has a child so an
-- Owner A delete attempt against Owner B's root can be checked for no cascade.
INSERT INTO public.tasks (
  id, user_id, project_id, parent_task_id, title,
  recurrence_parent_id, recurrence_rule, due_at
)
VALUES
  ('70000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', NULL, 'Cascade root', NULL, NULL, NULL),
  ('70000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '70000000-0000-4000-8000-000000000001', 'Cascade child', NULL, NULL, NULL),
  ('70000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '70000000-0000-4000-8000-000000000002', 'Cascade grandchild', NULL, NULL, NULL),
  ('70000000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', NULL, 'Unrelated task survives parent deletion', NULL, NULL, NULL),
  ('70000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', NULL, 'Recurring occurrence survives source deletion', '70000000-0000-4000-8000-000000000001', '{"frequency":"DAILY","interval":1}'::jsonb, '2099-01-01T09:00:00Z'),
  ('70000000-0000-4000-8000-000000000006', '22222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '20000000-0000-4000-8000-000000000001', 'Owner B protected child', NULL, NULL, NULL);

INSERT INTO public.reminders (id, user_id, task_id, remind_at)
VALUES
  ('71000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '70000000-0000-4000-8000-000000000001', '2099-01-01T09:00:00Z'),
  ('71000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '70000000-0000-4000-8000-000000000002', '2099-01-01T10:00:00Z'),
  ('71000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', '70000000-0000-4000-8000-000000000004', '2099-01-01T11:00:00Z');

-- Owner A/B reminder fixtures support authenticated relationship tests.
INSERT INTO public.reminders (id, user_id, task_id, remind_at)
VALUES
  ('81000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000001', '2099-01-02T09:00:00Z'),
  ('81000000-0000-4000-8000-000000000002', '22222222-2222-4222-8222-222222222222', '20000000-0000-4000-8000-000000000001', '2099-01-02T09:00:00Z'),
  ('81000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', '70000000-0000-4000-8000-000000000004', '2099-01-02T10:00:00Z'),
  ('81000000-0000-4000-8000-000000000004', '22222222-2222-4222-8222-222222222222', '70000000-0000-4000-8000-000000000006', '2099-01-02T10:00:00Z');

-- Notifications have no client INSERT policy; seed them before switching to
-- authenticated so the task-delete test and ownership regressions have valid rows.
INSERT INTO public.notifications (id, user_id, reminder_id, task_id, title, body)
VALUES
  ('72000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000001', '70000000-0000-4000-8000-000000000001', 'Cascade root reminder', 'Seeded notification'),
  ('72000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000002', 'Cascade child reminder', 'Seeded notification'),
  ('72000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000004', 'Unrelated task reminder', 'Must survive parent deletion'),
  ('82000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '81000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Owner A reminder', 'Ownership fixture'),
  ('82000000-0000-4000-8000-000000000002', '22222222-2222-4222-8222-222222222222', '81000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', 'Owner B reminder', 'Ownership fixture');

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO authenticated, service_role;
GRANT SELECT ON auth.users TO authenticated, service_role;

SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

DO $owner_a$
DECLARE
  visible_projects integer;
  visible_tasks integer;
  visible_checklists integer;
  visible_legacy_checklists integer;
  affected_rows integer;
  project_name text;
  project_title text;
  error_message text;
  error_constraint text;
BEGIN
  IF current_user <> 'authenticated' THEN
    RAISE EXCEPTION 'Owner A assertions must execute as the authenticated database role; current_user is %.', current_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = current_user
      AND (rolsuper OR rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'The authenticated test role must not bypass row-level security.';
  END IF;

  IF auth.uid() <> '11111111-1111-4111-8111-111111111111'::uuid THEN
    RAISE EXCEPTION 'The test JWT subject was not resolved.';
  END IF;

  SELECT count(*) INTO visible_projects FROM public.projects;
  SELECT count(*) INTO visible_tasks FROM public.tasks;
  SELECT count(*) INTO visible_checklists FROM public.checklist_items;
  SELECT count(*) INTO visible_legacy_checklists FROM public.task_checklist_items;

  IF visible_projects <> 1 OR visible_tasks <> 6 OR visible_checklists <> 1 THEN
    RAISE EXCEPTION 'Owner A visibility is incorrect: projects %, tasks %, checklists %.',
      visible_projects, visible_tasks, visible_checklists;
  END IF;

  IF visible_legacy_checklists <> 2 THEN
    RAISE EXCEPTION 'Owner A must see its valid legacy row and preserved ID-collision source row; found %.',
      visible_legacy_checklists;
  END IF;

  -- Reminder INSERT/UPDATE must bind task_id to the same owner, even when the
  -- caller supplies a valid foreign task UUID that RLS hides from SELECT.
  INSERT INTO public.reminders (id, user_id, task_id, remind_at)
  VALUES (
    '83000000-0000-4000-8000-000000000001',
    auth.uid(),
    '10000000-0000-4000-8000-000000000001',
    '2099-01-03T09:00:00Z'
  );

  UPDATE public.reminders
  SET task_id = '70000000-0000-4000-8000-000000000004'
  WHERE id = '83000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000001'
      AND user_id = auth.uid()
      AND task_id = '70000000-0000-4000-8000-000000000004'
  ) THEN
    RAISE EXCEPTION 'Owner A could not move a reminder between its own tasks.';
  END IF;

  UPDATE public.reminders
  SET task_id = '10000000-0000-4000-8000-000000000001'
  WHERE id = '83000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000001'
      AND task_id = '10000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Owner A could not restore a valid same-owner reminder task link.';
  END IF;

  BEGIN
    INSERT INTO public.reminders (id, user_id, task_id, remind_at)
    VALUES (
      '83000000-0000-4000-8000-000000000002',
      auth.uid(),
      '20000000-0000-4000-8000-000000000001',
      '2099-01-03T10:00:00Z'
    );
    RAISE EXCEPTION 'Owner A created a reminder for Owner B task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'reminders_task_owner_fkey' THEN
      RAISE EXCEPTION 'Owner A cross-owner reminder INSERT failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000002'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner A cross-owner reminder INSERT left a row behind.';
  END IF;

  BEGIN
    UPDATE public.reminders
    SET task_id = '20000000-0000-4000-8000-000000000001'
    WHERE id = '83000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Owner A reassigned a reminder to Owner B task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'reminders_task_owner_fkey' THEN
      RAISE EXCEPTION 'Owner A cross-owner reminder UPDATE failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000001'
      AND task_id = '10000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner A reminder UPDATE changed the original task link.';
  END IF;

  -- A legitimate same-owner notification reassignment succeeds. All later
  -- negative updates must leave this exact reminder/task pair unchanged.
  UPDATE public.notifications
  SET reminder_id = '81000000-0000-4000-8000-000000000003',
      task_id = '70000000-0000-4000-8000-000000000004'
  WHERE id = '82000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE id = '82000000-0000-4000-8000-000000000001'
      AND user_id = auth.uid()
      AND reminder_id = '81000000-0000-4000-8000-000000000003'
      AND task_id = '70000000-0000-4000-8000-000000000004'
  ) THEN
    RAISE EXCEPTION 'Owner A could not reassign a notification to a matching same-owner reminder/task pair.';
  END IF;

  UPDATE public.notifications
  SET read_at = now()
  WHERE id = '82000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Owner A could not update the read state of its own notification.';
  END IF;

  BEGIN
    UPDATE public.notifications
    SET task_id = '20000000-0000-4000-8000-000000000001'
    WHERE id = '82000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Owner A reassigned a notification to Owner B task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'Owner A cross-owner notification task UPDATE failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  BEGIN
    UPDATE public.notifications
    SET reminder_id = '81000000-0000-4000-8000-000000000002'
    WHERE id = '82000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Owner A reassigned a notification to Owner B reminder.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'Owner A cross-owner notification reminder UPDATE failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  BEGIN
    UPDATE public.notifications
    SET reminder_id = '81000000-0000-4000-8000-000000000001'
    WHERE id = '82000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Owner A linked a notification to a same-owner reminder for a different task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'Owner A mismatched notification pair failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE id = '82000000-0000-4000-8000-000000000001'
      AND reminder_id = '81000000-0000-4000-8000-000000000003'
      AND task_id = '70000000-0000-4000-8000-000000000004'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner A notification UPDATE changed its previous reminder/task pair.';
  END IF;

  BEGIN
    UPDATE public.reminders
    SET task_id = '10000000-0000-4000-8000-000000000001'
    WHERE id = '81000000-0000-4000-8000-000000000003';
    RAISE EXCEPTION 'Owner A changed a reminder task while a notification still references its original task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'Owner A reminder task-change protection failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '81000000-0000-4000-8000-000000000003'
      AND task_id = '70000000-0000-4000-8000-000000000004'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner A reminder task change modified the existing notification relationship.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.projects
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ) OR EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '20000000-0000-4000-8000-000000000001'
  ) OR EXISTS (
    SELECT 1 FROM public.checklist_items
    WHERE id IN ('30000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000005')
  ) OR EXISTS (
    SELECT 1 FROM public.task_checklist_items
    WHERE id = '30000000-0000-4000-8000-000000000003'
  ) THEN
    RAISE EXCEPTION 'Owner A can read Owner B organization records.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.task_checklist_items
    WHERE id = '30000000-0000-4000-8000-000000000002'
  ) OR EXISTS (
    SELECT 1 FROM public.checklist_items
    WHERE id = '30000000-0000-4000-8000-000000000004'
  ) THEN
    RAISE EXCEPTION 'Owner A can read a checklist row attached to Owner B task.';
  END IF;

  -- Direct task INSERTs below run as authenticated with RLS enabled, not as
  -- the migration owner. A valid active-project subtask must be accepted.
  INSERT INTO public.tasks (id, user_id, project_id, parent_task_id, title)
  VALUES (
    '40000000-0000-4000-8000-000000000003',
    auth.uid(),
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '10000000-0000-4000-8000-000000000001',
    'Owner A authenticated active subtask'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000003'
      AND user_id = auth.uid()
      AND project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      AND parent_task_id = '10000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Owner A could not create a subtask under its ACTIVE project with the correct parent link.';
  END IF;

  -- Exercise UPDATE/reassignment while still running as authenticated. The
  -- alternate project is also owned by Owner A and remains ACTIVE throughout.
  INSERT INTO public.projects (id, user_id, name)
  VALUES (
    'abababab-abab-4aba-8aba-abababababab',
    auth.uid(),
    'Owner A alternate ACTIVE project'
  );

  INSERT INTO public.tasks (id, user_id, project_id, title)
  VALUES
    ('40000000-0000-4000-8000-000000000008', auth.uid(), NULL, 'Owner A unassigned task for active assignment'),
    ('40000000-0000-4000-8000-000000000009', auth.uid(), 'abababab-abab-4aba-8aba-abababababab', 'Owner A task for active reassignment'),
    ('40000000-0000-4000-8000-000000000010', auth.uid(), 'abababab-abab-4aba-8aba-abababababab', 'Owner A task for completed-project reassignment'),
    ('40000000-0000-4000-8000-000000000011', auth.uid(), 'abababab-abab-4aba-8aba-abababababab', 'Owner A task for archived-project reassignment'),
    ('40000000-0000-4000-8000-000000000012', auth.uid(), 'abababab-abab-4aba-8aba-abababababab', 'Owner A task for cross-owner reassignment');

  UPDATE public.tasks
  SET project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  WHERE id = '40000000-0000-4000-8000-000000000008';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000008'
      AND project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) THEN
    RAISE EXCEPTION 'Authenticated UPDATE could not assign an unassigned task to an ACTIVE project.';
  END IF;

  UPDATE public.tasks
  SET project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  WHERE id = '40000000-0000-4000-8000-000000000009';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000009'
      AND project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) THEN
    RAISE EXCEPTION 'Authenticated UPDATE could not reassign a task from another owned ACTIVE project.';
  END IF;

  -- Reparent an existing task to another parent in the same owner/project.
  UPDATE public.tasks
  SET parent_task_id = '40000000-0000-4000-8000-000000000009'
  WHERE id = '40000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000003'
      AND project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      AND parent_task_id = '40000000-0000-4000-8000-000000000009'
  ) THEN
    RAISE EXCEPTION 'Authenticated UPDATE could not reassign a task to another parent in the same owned project.';
  END IF;

  -- A three-level chain must not be closed into a cycle by an authenticated UPDATE.
  INSERT INTO public.tasks (id, user_id, project_id, parent_task_id, title)
  VALUES (
    '40000000-0000-4000-8000-000000000013',
    auth.uid(),
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '40000000-0000-4000-8000-000000000003',
    'Owner A hierarchy-cycle descendant'
  );

  BEGIN
    UPDATE public.tasks
    SET parent_task_id = '40000000-0000-4000-8000-000000000013'
    WHERE id = '40000000-0000-4000-8000-000000000009';
    RAISE EXCEPTION 'Authenticated hierarchy-cycle UPDATE unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Task hierarchy cannot contain cycles.' THEN
      RAISE EXCEPTION 'Authenticated hierarchy-cycle UPDATE failed for an unexpected reason: %', error_message;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1
    FROM public.tasks root
    JOIN public.tasks child
      ON child.id = '40000000-0000-4000-8000-000000000003'
    JOIN public.tasks descendant
      ON descendant.id = '40000000-0000-4000-8000-000000000013'
    WHERE root.id = '40000000-0000-4000-8000-000000000009'
      AND root.parent_task_id IS NULL
      AND child.parent_task_id = root.id
      AND descendant.parent_task_id = child.id
  ) THEN
    RAISE EXCEPTION 'Rejected Owner A hierarchy-cycle UPDATE changed the existing parent chain.';
  END IF;

  -- A parent in another project owned by the same user must still be rejected.
  BEGIN
    UPDATE public.tasks
    SET parent_task_id = '40000000-0000-4000-8000-000000000010'
    WHERE id = '40000000-0000-4000-8000-000000000003';
    RAISE EXCEPTION 'Authenticated parent reassignment into another project unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Subtask must belong to the same project as its parent.' THEN
      RAISE EXCEPTION 'Cross-project parent reassignment failed for an unexpected reason: %', error_message;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000003'
      AND parent_task_id = '40000000-0000-4000-8000-000000000009'
  ) THEN
    RAISE EXCEPTION 'Rejected cross-project parent reassignment changed the existing parent link.';
  END IF;

  -- A task owned by another user is hidden by RLS and must not become a parent.
  BEGIN
    UPDATE public.tasks
    SET parent_task_id = '20000000-0000-4000-8000-000000000001'
    WHERE id = '40000000-0000-4000-8000-000000000003';
    RAISE EXCEPTION 'Authenticated cross-owner parent reassignment unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000003'
      AND parent_task_id = '40000000-0000-4000-8000-000000000009'
  ) THEN
    RAISE EXCEPTION 'Rejected cross-owner parent reassignment changed the existing parent link.';
  END IF;

  -- An owned ACTIVE project must not allow a foreign owner's parent task.
  BEGIN
    INSERT INTO public.tasks (id, user_id, project_id, parent_task_id, title)
    VALUES (
      '40000000-0000-4000-8000-000000000007',
      auth.uid(),
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '20000000-0000-4000-8000-000000000001',
      'Owner A cross-owner parent attack'
    );
    RAISE EXCEPTION 'Task trigger accepted Owner B parent task for Owner A.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  IF EXISTS (
    SELECT 1 FROM public.tasks WHERE id = '40000000-0000-4000-8000-000000000007'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner A cross-owner parent INSERT left a task row behind.';
  END IF;

  -- The authenticated owner may complete/archive its project, but new
  -- subtasks must be rejected after each status transition.
  UPDATE public.projects
  SET status = 'COMPLETED'
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Owner A could not complete its own project in the authenticated fixture.';
  END IF;

  BEGIN
    UPDATE public.tasks
    SET project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    WHERE id = '40000000-0000-4000-8000-000000000010';
    RAISE EXCEPTION 'Authenticated reassignment into a COMPLETED project unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Tasks can only be linked to active projects.' THEN
      RAISE EXCEPTION 'COMPLETED-project reassignment failed for an unexpected reason: %', error_message;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000010'
      AND project_id = 'abababab-abab-4aba-8aba-abababababab'
  ) THEN
    RAISE EXCEPTION 'Rejected COMPLETED-project reassignment changed the task project link.';
  END IF;

  BEGIN
    INSERT INTO public.tasks (id, user_id, project_id, parent_task_id, title)
    VALUES (
      '40000000-0000-4000-8000-000000000004',
      auth.uid(),
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '10000000-0000-4000-8000-000000000001',
      'Owner A subtask under completed project'
    );
    RAISE EXCEPTION 'Authenticated task INSERT under a COMPLETED project unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Tasks can only be linked to active projects.' THEN
      RAISE EXCEPTION 'COMPLETED-project subtask failed for an unexpected reason: %', error_message;
    END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM public.tasks WHERE id = '40000000-0000-4000-8000-000000000004'
  ) THEN
    RAISE EXCEPTION 'Rejected authenticated COMPLETED-project subtask left a task row behind.';
  END IF;

  UPDATE public.projects
  SET status = 'ARCHIVED'
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Owner A could not archive its own completed project in the authenticated fixture.';
  END IF;

  -- Existing tasks in archived projects remain maintainable: changing only the
  -- parent link must not create a new project assignment.
  UPDATE public.tasks
  SET parent_task_id = '10000000-0000-4000-8000-000000000001'
  WHERE id = '40000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000003'
      AND project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      AND parent_task_id = '10000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'An existing archived-project task could not be reparented within its historical project.';
  END IF;

  BEGIN
    UPDATE public.tasks
    SET project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    WHERE id = '40000000-0000-4000-8000-000000000011';
    RAISE EXCEPTION 'Authenticated reassignment into an ARCHIVED project unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Tasks can only be linked to active projects.' THEN
      RAISE EXCEPTION 'ARCHIVED-project reassignment failed for an unexpected reason: %', error_message;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000011'
      AND project_id = 'abababab-abab-4aba-8aba-abababababab'
  ) THEN
    RAISE EXCEPTION 'Rejected ARCHIVED-project reassignment changed the task project link.';
  END IF;

  BEGIN
    UPDATE public.tasks
    SET project_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    WHERE id = '40000000-0000-4000-8000-000000000012';
    RAISE EXCEPTION 'Authenticated cross-owner project reassignment unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000012'
      AND project_id = 'abababab-abab-4aba-8aba-abababababab'
  ) THEN
    RAISE EXCEPTION 'Rejected cross-owner reassignment changed the task project link.';
  END IF;

  BEGIN
    INSERT INTO public.tasks (id, user_id, project_id, parent_task_id, title)
    VALUES (
      '40000000-0000-4000-8000-000000000005',
      auth.uid(),
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '10000000-0000-4000-8000-000000000001',
      'Owner A subtask under archived project'
    );
    RAISE EXCEPTION 'Authenticated task INSERT under an ARCHIVED project unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Tasks can only be linked to active projects.' THEN
      RAISE EXCEPTION 'ARCHIVED-project subtask failed for an unexpected reason: %', error_message;
    END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM public.tasks WHERE id = '40000000-0000-4000-8000-000000000005'
  ) THEN
    RAISE EXCEPTION 'Rejected authenticated ARCHIVED-project subtask left a task row behind.';
  END IF;

  -- An unchanged historical project link remains valid after archive, including
  -- when the update is issued by the authenticated owner.
  UPDATE public.tasks
  SET project_id = project_id
  WHERE id IN (
    '10000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000003'
  );
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 2 THEN
    RAISE EXCEPTION 'Authenticated updates did not preserve both historical task/project links after archive.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.tasks
    WHERE id = '40000000-0000-4000-8000-000000000003'
      AND project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      AND parent_task_id = '10000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'The authenticated subtask lost its historical project or parent relationship after archive.';
  END IF;

  -- Both compatibility directions must work for the legacy title and app name.
  UPDATE public.projects
  SET title = 'Renamed through legacy title'
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  SELECT name, title INTO project_name, project_title
  FROM public.projects
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  IF project_name <> 'Renamed through legacy title'
     OR project_title <> 'Renamed through legacy title' THEN
    RAISE EXCEPTION 'Legacy title update did not synchronize projects.name.';
  END IF;

  UPDATE public.projects
  SET name = 'Renamed through application name'
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  SELECT name, title INTO project_name, project_title
  FROM public.projects
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  IF project_name <> 'Renamed through application name'
     OR project_title <> 'Renamed through application name' THEN
    RAISE EXCEPTION 'Application name update did not synchronize projects.title.';
  END IF;

  -- If both columns are supplied with conflicting values in one statement,
  -- the canonical application-facing name must win deterministically.
  UPDATE public.projects
  SET name = 'Canonical update wins',
      title = 'Conflicting legacy update'
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  SELECT name, title INTO project_name, project_title
  FROM public.projects
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  IF project_name <> 'Canonical update wins'
     OR project_title <> 'Canonical update wins' THEN
    RAISE EXCEPTION 'A conflicting dual-column update did not prefer projects.name.';
  END IF;

  INSERT INTO public.projects (id, user_id, name, title)
  VALUES (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee6',
    auth.uid(),
    'Canonical insert wins',
    'Conflicting legacy insert'
  );

  SELECT name, title INTO project_name, project_title
  FROM public.projects
  WHERE id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee6';

  IF project_name <> 'Canonical insert wins'
     OR project_title <> 'Canonical insert wins' THEN
    RAISE EXCEPTION 'A conflicting dual-column insert did not prefer projects.name.';
  END IF;

  INSERT INTO public.projects (id, user_id, name, description)
  VALUES (
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    auth.uid(),
    'Created through authenticated API',
    NULL
  );

  SELECT title INTO project_title
  FROM public.projects
  WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

  IF project_title <> 'Created through authenticated API' THEN
    RAISE EXCEPTION 'Name-only project insert did not satisfy the legacy title column.';
  END IF;

  INSERT INTO public.projects (id, user_id, title)
  VALUES (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',
    auth.uid(),
    'Created through legacy title'
  );

  SELECT name, title INTO project_name, project_title
  FROM public.projects
  WHERE id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5';

  IF project_name <> 'Created through legacy title'
     OR project_title <> 'Created through legacy title' THEN
    RAISE EXCEPTION 'Legacy title-only insert did not populate projects.name.';
  END IF;

  -- Both application-name and legacy-title write paths must reject invalid names.
  BEGIN
    INSERT INTO public.projects (id, user_id, name)
    VALUES (
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
      auth.uid(),
      '   '
    );
    RAISE EXCEPTION 'Project compatibility accepted a blank application name.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.projects (id, user_id, name)
    VALUES (
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3',
      auth.uid(),
      repeat('x', 121)
    );
    RAISE EXCEPTION 'Project compatibility accepted an application name longer than 120 characters.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.projects (id, user_id, name)
    VALUES (
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee4',
      auth.uid(),
      E'\t\n'
    );
    RAISE EXCEPTION 'Project compatibility accepted a whitespace-only application name.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE public.projects
    SET title = '   '
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    RAISE EXCEPTION 'Project compatibility accepted a blank legacy title.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE public.projects
    SET title = repeat('x', 121)
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    RAISE EXCEPTION 'Project compatibility accepted a legacy title longer than 120 characters.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE public.projects
    SET title = E'\n\t'
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    RAISE EXCEPTION 'Project compatibility accepted a whitespace-only legacy title.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.projects (id, user_id, name)
    VALUES (
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      '22222222-2222-4222-8222-222222222222',
      'Spoofed owner project'
    );
    RAISE EXCEPTION 'RLS accepted a project insert for another owner.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.tasks (id, user_id, project_id, title)
    VALUES (
      '40000000-0000-4000-8000-000000000001',
      auth.uid(),
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'Cross-owner project link'
    );
    RAISE EXCEPTION 'Task trigger accepted a project owned by another user.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.checklist_items (id, user_id, task_id, title)
    VALUES (
      '50000000-0000-4000-8000-000000000001',
      auth.uid(),
      '20000000-0000-4000-8000-000000000001',
      'Cross-owner canonical checklist'
    );
    RAISE EXCEPTION 'Canonical checklist RLS accepted another owner task.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.task_checklist_items (id, user_id, task_id, title)
    VALUES (
      '60000000-0000-4000-8000-000000000001',
      auth.uid(),
      '20000000-0000-4000-8000-000000000001',
      'Cross-owner legacy checklist'
    );
    RAISE EXCEPTION 'Legacy checklist RLS accepted another owner task.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    UPDATE public.checklist_items
    SET task_id = '20000000-0000-4000-8000-000000000001'
    WHERE id = '30000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Canonical checklist RLS accepted reassignment to another owner task.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  UPDATE public.projects
  SET name = 'Unauthorized update'
  WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner A updated Owner B project.';
  END IF;

  DELETE FROM public.projects
  WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner A deleted Owner B project.';
  END IF;

  UPDATE public.tasks
  SET title = 'Unauthorized task update'
  WHERE id = '20000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner A updated Owner B task.';
  END IF;

  DELETE FROM public.tasks
  WHERE id = '20000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner A deleted Owner B task.';
  END IF;

  UPDATE public.checklist_items
  SET title = 'Unauthorized canonical checklist update'
  WHERE id = '30000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner A updated Owner B canonical checklist item.';
  END IF;

  DELETE FROM public.checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner A deleted Owner B canonical checklist item.';
  END IF;

  UPDATE public.task_checklist_items
  SET title = 'Unauthorized legacy checklist update'
  WHERE id = '30000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner A updated Owner B legacy checklist item.';
  END IF;

  DELETE FROM public.task_checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner A deleted Owner B legacy checklist item.';
  END IF;

  -- Create matching canonical and legacy checklist rows as the authenticated
  -- owner. Identical payloads keep the reconciliation conflict report stable.
  INSERT INTO public.checklist_items (
    id, user_id, task_id, title, is_completed, position, created_at, updated_at
  )
  VALUES
    ('73000000-0000-4000-8000-000000000001', auth.uid(), '70000000-0000-4000-8000-000000000001', 'Cascade root checklist', false, 0, '2026-11-20T00:00:00Z', '2026-11-20T00:00:00Z'),
    ('73000000-0000-4000-8000-000000000002', auth.uid(), '70000000-0000-4000-8000-000000000002', 'Cascade child checklist', false, 1, '2026-11-20T00:00:00Z', '2026-11-20T00:00:00Z'),
    ('73000000-0000-4000-8000-000000000003', auth.uid(), '70000000-0000-4000-8000-000000000003', 'Cascade grandchild checklist', false, 2, '2026-11-20T00:00:00Z', '2026-11-20T00:00:00Z'),
    ('73000000-0000-4000-8000-000000000004', auth.uid(), '70000000-0000-4000-8000-000000000004', 'Unrelated task checklist', false, 3, '2026-11-20T00:00:00Z', '2026-11-20T00:00:00Z');

  INSERT INTO public.task_checklist_items (
    id, user_id, task_id, title, is_completed, position, created_at, updated_at
  )
  VALUES
    ('73000000-0000-4000-8000-000000000001', auth.uid(), '70000000-0000-4000-8000-000000000001', 'Cascade root checklist', false, 0, '2026-11-20T00:00:00Z', '2026-11-20T00:00:00Z'),
    ('73000000-0000-4000-8000-000000000002', auth.uid(), '70000000-0000-4000-8000-000000000002', 'Cascade child checklist', false, 1, '2026-11-20T00:00:00Z', '2026-11-20T00:00:00Z'),
    ('73000000-0000-4000-8000-000000000003', auth.uid(), '70000000-0000-4000-8000-000000000003', 'Cascade grandchild checklist', false, 2, '2026-11-20T00:00:00Z', '2026-11-20T00:00:00Z'),
    ('73000000-0000-4000-8000-000000000004', auth.uid(), '70000000-0000-4000-8000-000000000004', 'Unrelated task checklist', false, 3, '2026-11-20T00:00:00Z', '2026-11-20T00:00:00Z');

  -- Deleting the owned parent must cascade only through parent_task_id children.
  DELETE FROM public.tasks
  WHERE id = '70000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Authenticated owner could not delete exactly its selected parent task.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id IN (
      '70000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000002',
      '70000000-0000-4000-8000-000000000003'
    )
  ) THEN
    RAISE EXCEPTION 'Deleting an owned parent did not remove its full descendant chain.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.checklist_items
    WHERE task_id IN (
      '70000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000002',
      '70000000-0000-4000-8000-000000000003'
    )
  ) OR EXISTS (
    SELECT 1 FROM public.task_checklist_items
    WHERE task_id IN (
      '70000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000002',
      '70000000-0000-4000-8000-000000000003'
    )
  ) THEN
    RAISE EXCEPTION 'Task deletion left canonical or legacy checklist associations behind.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.reminders
    WHERE task_id IN (
      '70000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000002',
      '70000000-0000-4000-8000-000000000003'
    )
  ) OR EXISTS (
    SELECT 1 FROM public.notifications
    WHERE task_id IN (
      '70000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000002',
      '70000000-0000-4000-8000-000000000003'
    ) OR reminder_id IN (
      '71000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000002'
    )
  ) THEN
    RAISE EXCEPTION 'Task deletion left reminder or notification records behind.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '70000000-0000-4000-8000-000000000005'
      AND project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      AND parent_task_id IS NULL
      AND recurrence_parent_id IS NULL
      AND recurrence_rule = '{"frequency":"DAILY","interval":1}'::jsonb
      AND due_at = '2099-01-01T09:00:00Z'::timestamptz
  ) THEN
    RAISE EXCEPTION 'Deleting a recurrence source must preserve the occurrence and clear only recurrence_parent_id.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '70000000-0000-4000-8000-000000000004'
      AND project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.projects
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Deleting a task changed an unrelated task or its project relationship.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.checklist_items
    WHERE id = '73000000-0000-4000-8000-000000000004'
      AND task_id = '70000000-0000-4000-8000-000000000004'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.task_checklist_items
    WHERE id = '73000000-0000-4000-8000-000000000004'
      AND task_id = '70000000-0000-4000-8000-000000000004'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '71000000-0000-4000-8000-000000000003'
      AND task_id = '70000000-0000-4000-8000-000000000004'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE id = '72000000-0000-4000-8000-000000000003'
      AND task_id = '70000000-0000-4000-8000-000000000004'
      AND reminder_id = '71000000-0000-4000-8000-000000000003'
  ) THEN
    RAISE EXCEPTION 'Deleting the parent removed unrelated checklist, reminder, or notification records.';
  END IF;
END
$owner_a$;

SET request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';

DO $owner_b$
DECLARE
  visible_projects integer;
  visible_tasks integer;
  visible_checklists integer;
  visible_legacy_checklists integer;
  affected_rows integer;
  error_message text;
  error_constraint text;
BEGIN
  IF current_user <> 'authenticated' THEN
    RAISE EXCEPTION 'Owner B assertions must execute as the authenticated database role; current_user is %.', current_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = current_user
      AND (rolsuper OR rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'The authenticated test role must not bypass row-level security for Owner B.';
  END IF;

  IF auth.uid() <> '22222222-2222-4222-8222-222222222222'::uuid THEN
    RAISE EXCEPTION 'The second test JWT subject was not resolved.';
  END IF;

  SELECT count(*) INTO visible_projects FROM public.projects;
  SELECT count(*) INTO visible_tasks FROM public.tasks;
  SELECT count(*) INTO visible_checklists FROM public.checklist_items;
  SELECT count(*) INTO visible_legacy_checklists FROM public.task_checklist_items;

  IF visible_projects <> 1 OR visible_tasks <> 2 OR visible_checklists <> 2 THEN
    RAISE EXCEPTION 'Owner B visibility is incorrect: projects %, tasks %, canonical checklists %.',
      visible_projects, visible_tasks, visible_checklists;
  END IF;

  IF visible_legacy_checklists <> 1 THEN
    RAISE EXCEPTION 'Owner B must see only its one legacy checklist row; found %.',
      visible_legacy_checklists;
  END IF;

  INSERT INTO public.reminders (id, user_id, task_id, remind_at)
  VALUES (
    '83000000-0000-4000-8000-000000000003',
    auth.uid(),
    '20000000-0000-4000-8000-000000000001',
    '2099-01-04T09:00:00Z'
  );

  UPDATE public.reminders
  SET task_id = '70000000-0000-4000-8000-000000000006'
  WHERE id = '83000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000003'
      AND task_id = '70000000-0000-4000-8000-000000000006'
  ) THEN
    RAISE EXCEPTION 'Owner B could not move a reminder between its own tasks.';
  END IF;

  UPDATE public.reminders
  SET task_id = '20000000-0000-4000-8000-000000000001'
  WHERE id = '83000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000003'
      AND task_id = '20000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Owner B could not restore a valid same-owner reminder task link.';
  END IF;

  BEGIN
    INSERT INTO public.reminders (id, user_id, task_id, remind_at)
    VALUES (
      '83000000-0000-4000-8000-000000000004',
      auth.uid(),
      '10000000-0000-4000-8000-000000000001',
      '2099-01-04T10:00:00Z'
    );
    RAISE EXCEPTION 'Owner B created a reminder for Owner A task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'reminders_task_owner_fkey' THEN
      RAISE EXCEPTION 'Owner B cross-owner reminder INSERT failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000004'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner B cross-owner reminder INSERT left a row behind.';
  END IF;

  BEGIN
    UPDATE public.reminders
    SET task_id = '10000000-0000-4000-8000-000000000001'
    WHERE id = '83000000-0000-4000-8000-000000000003';
    RAISE EXCEPTION 'Owner B reassigned a reminder to Owner A task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'reminders_task_owner_fkey' THEN
      RAISE EXCEPTION 'Owner B cross-owner reminder UPDATE failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000003'
      AND task_id = '20000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner B reminder UPDATE changed the original task link.';
  END IF;

  UPDATE public.notifications
  SET reminder_id = '81000000-0000-4000-8000-000000000004',
      task_id = '70000000-0000-4000-8000-000000000006'
  WHERE id = '82000000-0000-4000-8000-000000000002';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE id = '82000000-0000-4000-8000-000000000002'
      AND user_id = auth.uid()
      AND reminder_id = '81000000-0000-4000-8000-000000000004'
      AND task_id = '70000000-0000-4000-8000-000000000006'
  ) THEN
    RAISE EXCEPTION 'Owner B could not reassign a notification to a matching same-owner reminder/task pair.';
  END IF;

  UPDATE public.notifications
  SET read_at = now()
  WHERE id = '82000000-0000-4000-8000-000000000002';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Owner B could not update the read state of its own notification.';
  END IF;

  BEGIN
    UPDATE public.notifications
    SET task_id = '10000000-0000-4000-8000-000000000001'
    WHERE id = '82000000-0000-4000-8000-000000000002';
    RAISE EXCEPTION 'Owner B reassigned a notification to Owner A task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'Owner B cross-owner notification task UPDATE failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  BEGIN
    UPDATE public.notifications
    SET reminder_id = '81000000-0000-4000-8000-000000000001'
    WHERE id = '82000000-0000-4000-8000-000000000002';
    RAISE EXCEPTION 'Owner B reassigned a notification to Owner A reminder.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'Owner B cross-owner notification reminder UPDATE failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  BEGIN
    UPDATE public.notifications
    SET reminder_id = '81000000-0000-4000-8000-000000000002'
    WHERE id = '82000000-0000-4000-8000-000000000002';
    RAISE EXCEPTION 'Owner B linked a notification to a same-owner reminder for a different task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'Owner B mismatched notification pair failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE id = '82000000-0000-4000-8000-000000000002'
      AND reminder_id = '81000000-0000-4000-8000-000000000004'
      AND task_id = '70000000-0000-4000-8000-000000000006'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner B notification UPDATE changed its previous reminder/task pair.';
  END IF;

  BEGIN
    UPDATE public.reminders
    SET task_id = '20000000-0000-4000-8000-000000000001'
    WHERE id = '81000000-0000-4000-8000-000000000004';
    RAISE EXCEPTION 'Owner B changed a reminder task while a notification still references its original task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'Owner B reminder task-change protection failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '81000000-0000-4000-8000-000000000004'
      AND task_id = '70000000-0000-4000-8000-000000000006'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner B reminder task change modified the existing notification relationship.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '20000000-0000-4000-8000-000000000001'
      AND project_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      AND parent_task_id IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '70000000-0000-4000-8000-000000000006'
      AND project_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      AND parent_task_id = '20000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Owner A cross-owner DELETE affected Owner B task hierarchy.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.projects
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) OR EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '10000000-0000-4000-8000-000000000001'
  ) OR EXISTS (
    SELECT 1 FROM public.checklist_items
    WHERE id = '30000000-0000-4000-8000-000000000001'
  ) OR EXISTS (
    SELECT 1 FROM public.task_checklist_items
    WHERE id IN ('30000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000005')
  ) THEN
    RAISE EXCEPTION 'Owner B can read Owner A organization records.';
  END IF;

  UPDATE public.projects
  SET name = 'Owner B unauthorized project update'
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner B updated Owner A project.';
  END IF;

  DELETE FROM public.projects
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner B deleted Owner A project.';
  END IF;

  UPDATE public.tasks
  SET title = 'Owner B unauthorized task update'
  WHERE id = '10000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner B updated Owner A task.';
  END IF;

  DELETE FROM public.tasks
  WHERE id = '10000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner B deleted Owner A task.';
  END IF;

  UPDATE public.checklist_items
  SET title = 'Owner B unauthorized canonical checklist update'
  WHERE id = '30000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner B updated Owner A canonical checklist item.';
  END IF;

  DELETE FROM public.checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner B deleted Owner A canonical checklist item.';
  END IF;

  UPDATE public.task_checklist_items
  SET title = 'Owner B unauthorized legacy checklist update'
  WHERE id = '30000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner B updated Owner A legacy checklist item.';
  END IF;

  DELETE FROM public.task_checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Owner B deleted Owner A legacy checklist item.';
  END IF;
  -- Reciprocal direct-API insert and relationship-change attacks by Owner B.
  BEGIN
    INSERT INTO public.projects (id, user_id, name)
    VALUES (
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
      '11111111-1111-4111-8111-111111111111',
      'Spoofed Owner A project from Owner B'
    );
    RAISE EXCEPTION 'RLS accepted a project insert for another owner from Owner B.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.tasks (id, user_id, project_id, title)
    VALUES (
      '40000000-0000-4000-8000-000000000002',
      auth.uid(),
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'Owner B cross-owner project link'
    );
    RAISE EXCEPTION 'Task trigger accepted Owner A project for Owner B.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  IF EXISTS (
    SELECT 1 FROM public.tasks WHERE id = '40000000-0000-4000-8000-000000000002'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner B cross-owner project INSERT left a task row behind.';
  END IF;

  -- Owner B must receive the same cycle protection within its own isolated project.
  INSERT INTO public.tasks (id, user_id, project_id, parent_task_id, title)
  VALUES (
    '40000000-0000-4000-8000-000000000014',
    auth.uid(),
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '20000000-0000-4000-8000-000000000001',
    'Owner B hierarchy-cycle descendant'
  );

  BEGIN
    UPDATE public.tasks
    SET parent_task_id = '40000000-0000-4000-8000-000000000014'
    WHERE id = '20000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Owner B authenticated hierarchy-cycle UPDATE unexpectedly succeeded.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Task hierarchy cannot contain cycles.' THEN
      RAISE EXCEPTION 'Owner B hierarchy-cycle UPDATE failed for an unexpected reason: %', error_message;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1
    FROM public.tasks root
    JOIN public.tasks descendant
      ON descendant.id = '40000000-0000-4000-8000-000000000014'
    WHERE root.id = '20000000-0000-4000-8000-000000000001'
      AND root.parent_task_id IS NULL
      AND descendant.parent_task_id = root.id
  ) THEN
    RAISE EXCEPTION 'Rejected Owner B hierarchy-cycle UPDATE changed the existing parent chain.';
  END IF;

  -- A valid Owner B project cannot be combined with Owner A's hidden parent.
  BEGIN
    INSERT INTO public.tasks (id, user_id, project_id, parent_task_id, title)
    VALUES (
      '40000000-0000-4000-8000-000000000006',
      auth.uid(),
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      '10000000-0000-4000-8000-000000000001',
      'Owner B cross-owner parent attack'
    );
    RAISE EXCEPTION 'Task trigger accepted Owner A parent task for Owner B.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  IF EXISTS (
    SELECT 1 FROM public.tasks WHERE id = '40000000-0000-4000-8000-000000000006'
  ) THEN
    RAISE EXCEPTION 'Rejected Owner B cross-owner parent INSERT left a task row behind.';
  END IF;

  BEGIN
    INSERT INTO public.checklist_items (id, user_id, task_id, title)
    VALUES (
      '50000000-0000-4000-8000-000000000002',
      auth.uid(),
      '10000000-0000-4000-8000-000000000001',
      'Owner B cross-owner canonical checklist'
    );
    RAISE EXCEPTION 'Canonical checklist RLS accepted Owner A task for Owner B.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.task_checklist_items (id, user_id, task_id, title)
    VALUES (
      '60000000-0000-4000-8000-000000000002',
      auth.uid(),
      '10000000-0000-4000-8000-000000000001',
      'Owner B cross-owner legacy checklist'
    );
    RAISE EXCEPTION 'Legacy checklist RLS accepted Owner A task for Owner B.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    UPDATE public.tasks
    SET project_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    WHERE id = '20000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Task trigger accepted a project reassignment to another owner.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    UPDATE public.tasks
    SET parent_task_id = '10000000-0000-4000-8000-000000000001'
    WHERE id = '20000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Task trigger accepted a parent reassignment to another owner.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '20000000-0000-4000-8000-000000000001'
      AND parent_task_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Rejected reciprocal cross-owner parent reassignment changed Owner B task state.';
  END IF;

  BEGIN
    UPDATE public.checklist_items
    SET task_id = '10000000-0000-4000-8000-000000000001'
    WHERE id = '30000000-0000-4000-8000-000000000003';
    RAISE EXCEPTION 'Canonical checklist RLS accepted reassignment to Owner A task.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    UPDATE public.task_checklist_items
    SET task_id = '10000000-0000-4000-8000-000000000001'
    WHERE id = '30000000-0000-4000-8000-000000000003';
    RAISE EXCEPTION 'Legacy checklist RLS accepted reassignment to Owner A task.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

END
$owner_b$;

-- The reminder delivery worker uses service_role. BYPASSRLS must not bypass
-- referential ownership integrity; valid worker writes still succeed.
RESET ROLE;
SET request.jwt.claim.sub = '';
SET ROLE service_role;

DO $service_role$
DECLARE
  error_constraint text;
BEGIN
  IF current_user <> 'service_role' OR NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolbypassrls
  ) THEN
    RAISE EXCEPTION 'The worker regression must execute as the BYPASSRLS service_role.';
  END IF;

  INSERT INTO public.reminders (id, user_id, task_id, remind_at)
  VALUES
    ('83000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000001', '2099-01-05T09:00:00Z'),
    ('83000000-0000-4000-8000-000000000006', '22222222-2222-4222-8222-222222222222', '20000000-0000-4000-8000-000000000001', '2099-01-05T09:00:00Z');

  INSERT INTO public.notifications (id, user_id, reminder_id, task_id, title, body)
  VALUES (
    '82000000-0000-4000-8000-000000000003',
    '11111111-1111-4111-8111-111111111111',
    '83000000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000001',
    'Service role valid notification',
    'Worker path'
  );

  BEGIN
    INSERT INTO public.reminders (id, user_id, task_id, remind_at)
    VALUES (
      '83000000-0000-4000-8000-000000000007',
      '11111111-1111-4111-8111-111111111111',
      '20000000-0000-4000-8000-000000000001',
      '2099-01-05T10:00:00Z'
    );
    RAISE EXCEPTION 'service_role created a reminder with a foreign-owner task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'reminders_task_owner_fkey' THEN
      RAISE EXCEPTION 'service_role reminder ownership failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  BEGIN
    INSERT INTO public.notifications (id, user_id, reminder_id, task_id, title, body)
    VALUES (
      '82000000-0000-4000-8000-000000000004',
      '11111111-1111-4111-8111-111111111111',
      '83000000-0000-4000-8000-000000000006',
      '20000000-0000-4000-8000-000000000001',
      'Service role cross-owner notification',
      'Must be rejected'
    );
    RAISE EXCEPTION 'service_role created a notification for another owner reminder.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'service_role notification ownership failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  BEGIN
    UPDATE public.notifications
    SET task_id = '20000000-0000-4000-8000-000000000001'
    WHERE id = '82000000-0000-4000-8000-000000000003';
    RAISE EXCEPTION 'service_role changed a valid notification to a mismatched task.'
      USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
    IF error_constraint <> 'notifications_reminder_owner_task_fkey' THEN
      RAISE EXCEPTION 'service_role notification task integrity failed on unexpected constraint %.', error_constraint;
    END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM public.reminders
    WHERE id = '83000000-0000-4000-8000-000000000007'
  ) OR EXISTS (
    SELECT 1 FROM public.notifications
    WHERE id = '82000000-0000-4000-8000-000000000004'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE id = '82000000-0000-4000-8000-000000000003'
      AND reminder_id = '83000000-0000-4000-8000-000000000005'
      AND task_id = '10000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'service_role ownership rejection left invalid rows or changed a valid notification.';
  END IF;
END
$service_role$;

RESET ROLE;
SET request.jwt.claim.sub = '';
SET ROLE anon;

-- Anonymous clients receive table privileges in Supabase, so RLS itself must
-- deny access rather than relying on missing SQL grants.
DO $anonymous$
DECLARE
  visible_projects integer;
  visible_tasks integer;
  visible_checklists integer;
  visible_legacy_checklists integer;
  affected_rows integer;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Anonymous session unexpectedly resolved an authenticated user.';
  END IF;

  SELECT count(*) INTO visible_projects FROM public.projects;
  SELECT count(*) INTO visible_tasks FROM public.tasks;
  SELECT count(*) INTO visible_checklists FROM public.checklist_items;
  SELECT count(*) INTO visible_legacy_checklists FROM public.task_checklist_items;

  IF visible_projects <> 0
     OR visible_tasks <> 0
     OR visible_checklists <> 0
     OR visible_legacy_checklists <> 0 THEN
    RAISE EXCEPTION 'Anonymous role can read Organization rows: projects %, tasks %, checklists %, legacy checklists %.',
      visible_projects, visible_tasks, visible_checklists, visible_legacy_checklists;
  END IF;

  BEGIN
    INSERT INTO public.projects (id, user_id, name)
    VALUES (
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
      '11111111-1111-4111-8111-111111111111',
      'Anonymous project'
    );
    RAISE EXCEPTION 'RLS accepted an anonymous project insert.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.tasks (id, user_id, title)
    VALUES (
      '40000000-0000-4000-8000-000000000003',
      '11111111-1111-4111-8111-111111111111',
      'Anonymous task'
    );
    RAISE EXCEPTION 'RLS accepted an anonymous task insert.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.checklist_items (id, user_id, task_id, title)
    VALUES (
      '50000000-0000-4000-8000-000000000003',
      '11111111-1111-4111-8111-111111111111',
      '10000000-0000-4000-8000-000000000001',
      'Anonymous canonical checklist'
    );
    RAISE EXCEPTION 'RLS accepted an anonymous canonical checklist insert.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.task_checklist_items (id, user_id, task_id, title)
    VALUES (
      '60000000-0000-4000-8000-000000000003',
      '11111111-1111-4111-8111-111111111111',
      '10000000-0000-4000-8000-000000000001',
      'Anonymous legacy checklist'
    );
    RAISE EXCEPTION 'RLS accepted an anonymous legacy checklist insert.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  UPDATE public.projects SET name = 'Anonymous update'
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Anonymous role updated an authenticated project.';
  END IF;

  UPDATE public.tasks SET title = 'Anonymous update'
  WHERE id = '10000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Anonymous role updated an authenticated task.';
  END IF;

  DELETE FROM public.checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Anonymous role deleted an authenticated checklist item.';
  END IF;

  UPDATE public.checklist_items SET title = 'Anonymous checklist update'
  WHERE id = '30000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Anonymous role updated an authenticated canonical checklist item.';
  END IF;

  UPDATE public.task_checklist_items SET title = 'Anonymous legacy checklist update'
  WHERE id = '30000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Anonymous role updated an authenticated legacy checklist item.';
  END IF;

  DELETE FROM public.projects
  WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Anonymous role deleted an authenticated project.';
  END IF;

  DELETE FROM public.tasks
  WHERE id = '10000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Anonymous role deleted an authenticated task.';
  END IF;

  DELETE FROM public.task_checklist_items
  WHERE id = '30000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'Anonymous role deleted an authenticated legacy checklist item.';
  END IF;
END
$anonymous$;

RESET ROLE;

SELECT 'Organization migration replay, authenticated isolation, and anonymous denial checks passed.' AS result;
