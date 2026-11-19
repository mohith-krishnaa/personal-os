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
    RAISE EXCEPTION 'Both checklist task_id columns must be NOT NULL and reference public.tasks with a validated ON DELETE CASCADE foreign key.';
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


-- Simulate a legacy malformed canonical row whose owner matches the caller
-- but whose task belongs to the other owner. SELECT RLS must hide it.
INSERT INTO public.checklist_items (id, user_id, task_id, title)
VALUES (
  '30000000-0000-4000-8000-000000000004',
  '11111111-1111-4111-8111-111111111111',
  '20000000-0000-4000-8000-000000000001',
  'Malformed canonical cross-owner task link'
);

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
BEGIN
  IF auth.uid() <> '11111111-1111-4111-8111-111111111111'::uuid THEN
    RAISE EXCEPTION 'The test JWT subject was not resolved.';
  END IF;

  SELECT count(*) INTO visible_projects FROM public.projects;
  SELECT count(*) INTO visible_tasks FROM public.tasks;
  SELECT count(*) INTO visible_checklists FROM public.checklist_items;
  SELECT count(*) INTO visible_legacy_checklists FROM public.task_checklist_items;

  IF visible_projects <> 1 OR visible_tasks <> 1 OR visible_checklists <> 1 THEN
    RAISE EXCEPTION 'Owner A visibility is incorrect: projects %, tasks %, checklists %.',
      visible_projects, visible_tasks, visible_checklists;
  END IF;

  IF visible_legacy_checklists <> 2 THEN
    RAISE EXCEPTION 'Owner A must see its valid legacy row and preserved ID-collision source row; found %.',
      visible_legacy_checklists;
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
BEGIN
  IF auth.uid() <> '22222222-2222-4222-8222-222222222222'::uuid THEN
    RAISE EXCEPTION 'The second test JWT subject was not resolved.';
  END IF;

  SELECT count(*) INTO visible_projects FROM public.projects;
  SELECT count(*) INTO visible_tasks FROM public.tasks;
  SELECT count(*) INTO visible_checklists FROM public.checklist_items;
  SELECT count(*) INTO visible_legacy_checklists FROM public.task_checklist_items;

  IF visible_projects <> 1 OR visible_tasks <> 1 OR visible_checklists <> 2 THEN
    RAISE EXCEPTION 'Owner B visibility is incorrect: projects %, tasks %, canonical checklists %.',
      visible_projects, visible_tasks, visible_checklists;
  END IF;

  IF visible_legacy_checklists <> 1 THEN
    RAISE EXCEPTION 'Owner B must see only its one legacy checklist row; found %.',
      visible_legacy_checklists;
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
