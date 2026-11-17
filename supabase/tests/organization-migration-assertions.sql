-- Assert that the complete migration chain can be replayed against the legacy
-- core schema and that the resulting Organization boundary holds under RLS.
DO $assert_schema$
DECLARE
  project_name_nullable text;
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

  IF EXISTS (
    SELECT 1
    FROM (VALUES ('projects'), ('tasks'), ('checklist_items'), ('task_checklist_items')) AS expected(table_name)
    JOIN pg_class c ON c.oid = to_regclass(format('public.%I', expected.table_name))
    WHERE NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'An Organization table is missing row-level security.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'projects'
      AND policyname = 'projects_select_own' AND cmd = 'SELECT'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'checklist_items'
      AND policyname = 'checklist_items_insert_own' AND cmd = 'INSERT'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'task_checklist_items'
      AND policyname = 'task_checklist_items_insert_own' AND cmd = 'INSERT'
  ) THEN
    RAISE EXCEPTION 'Expected owner-scoped Organization policies are missing.';
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
    RAISE EXCEPTION 'A valid legacy checklist item was not reconciled.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.checklist_items
    WHERE id = '30000000-0000-4000-8000-000000000002'
  ) THEN
    RAISE EXCEPTION 'A legacy checklist item attached to another owner task was copied.';
  END IF;
END
$assert_schema$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO authenticated, service_role;
GRANT SELECT ON auth.users TO authenticated, service_role;

SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

DO $owner_a$
DECLARE
  visible_projects integer;
  visible_tasks integer;
  visible_checklists integer;
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

  IF visible_projects <> 1 OR visible_tasks <> 1 OR visible_checklists <> 1 THEN
    RAISE EXCEPTION 'Owner A visibility is incorrect: projects %, tasks %, checklists %.',
      visible_projects, visible_tasks, visible_checklists;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.projects
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ) OR EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '20000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Owner A can read Owner B organization records.';
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
END
$owner_a$;

SET request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';

DO $owner_b$
DECLARE
  visible_projects integer;
  visible_tasks integer;
  visible_checklists integer;
BEGIN
  IF auth.uid() <> '22222222-2222-4222-8222-222222222222'::uuid THEN
    RAISE EXCEPTION 'The second test JWT subject was not resolved.';
  END IF;

  SELECT count(*) INTO visible_projects FROM public.projects;
  SELECT count(*) INTO visible_tasks FROM public.tasks;
  SELECT count(*) INTO visible_checklists FROM public.checklist_items;

  IF visible_projects <> 1 OR visible_tasks <> 1 OR visible_checklists <> 0 THEN
    RAISE EXCEPTION 'Owner B visibility is incorrect: projects %, tasks %, checklists %.',
      visible_projects, visible_tasks, visible_checklists;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.projects
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) OR EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = '10000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Owner B can read Owner A organization records.';
  END IF;
END
$owner_b$;

RESET ROLE;

SELECT 'Organization migration replay and authenticated isolation checks passed.' AS result;
