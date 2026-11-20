-- Verify that project completion/archive preserves existing task links while
-- new task creation and project reassignment require an ACTIVE project.
-- All fixtures are rolled back.

BEGIN;

INSERT INTO public.projects (id, user_id, name, status)
VALUES
  ('71000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Lifecycle active project', 'ACTIVE'),
  ('71000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'Lifecycle completed project', 'ACTIVE'),
  ('71000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', 'Lifecycle archived project', 'ACTIVE');

INSERT INTO public.tasks (id, user_id, project_id, title)
VALUES
  ('72000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000002', 'Existing completed-project task'),
  ('72000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000003', 'Existing archived-project parent'),
  ('72000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000003', 'Existing archived-project child'),
  ('72000000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', NULL, 'Unassigned task'),
  ('72000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000001', 'Active-project task');

UPDATE public.projects
SET status = 'COMPLETED'
WHERE id = '71000000-0000-4000-8000-000000000002';

UPDATE public.projects
SET status = 'ARCHIVED'
WHERE id = '71000000-0000-4000-8000-000000000003';

DO $archive_lifecycle$
DECLARE
  actual_project_id uuid;
  error_message text;
BEGIN
  SELECT project_id INTO actual_project_id
  FROM public.tasks
  WHERE id = '72000000-0000-4000-8000-000000000001';

  IF actual_project_id <> '71000000-0000-4000-8000-000000000002' THEN
    RAISE EXCEPTION 'Completing a project detached an existing task.';
  END IF;

  SELECT project_id INTO actual_project_id
  FROM public.tasks
  WHERE id = '72000000-0000-4000-8000-000000000002';

  IF actual_project_id <> '71000000-0000-4000-8000-000000000003' THEN
    RAISE EXCEPTION 'Archiving a project detached an existing task.';
  END IF;

  -- Existing task edits and hierarchy maintenance remain possible after archive.
  UPDATE public.tasks
  SET title = 'Existing archived task remains editable'
  WHERE id = '72000000-0000-4000-8000-000000000002';

  UPDATE public.tasks
  SET parent_task_id = '72000000-0000-4000-8000-000000000002'
  WHERE id = '72000000-0000-4000-8000-000000000003';

  BEGIN
    INSERT INTO public.tasks (id, user_id, project_id, title)
    VALUES ('73000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000003', 'Must reject archived project');
    RAISE EXCEPTION 'Expected archived-project task creation to fail.' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Tasks can only be linked to active projects.' THEN
      RAISE EXCEPTION 'Archived-project insert failed for an unexpected reason: %', error_message;
    END IF;
  END;

  BEGIN
    INSERT INTO public.tasks (id, user_id, project_id, title)
    VALUES ('73000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '71000000-0000-4000-8000-000000000002', 'Must reject completed project');
    RAISE EXCEPTION 'Expected completed-project task creation to fail.' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Tasks can only be linked to active projects.' THEN
      RAISE EXCEPTION 'Completed-project insert failed for an unexpected reason: %', error_message;
    END IF;
  END;

  BEGIN
    UPDATE public.tasks
    SET project_id = '71000000-0000-4000-8000-000000000003'
    WHERE id = '72000000-0000-4000-8000-000000000004';
    RAISE EXCEPTION 'Expected assignment to an archived project to fail.' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Tasks can only be linked to active projects.' THEN
      RAISE EXCEPTION 'Archived-project reassignment failed for an unexpected reason: %', error_message;
    END IF;
  END;

  BEGIN
    UPDATE public.tasks
    SET project_id = '71000000-0000-4000-8000-000000000002'
    WHERE id = '72000000-0000-4000-8000-000000000005';
    RAISE EXCEPTION 'Expected assignment to a completed project to fail.' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    IF error_message <> 'Tasks can only be linked to active projects.' THEN
      RAISE EXCEPTION 'Completed-project reassignment failed for an unexpected reason: %', error_message;
    END IF;
  END;

  -- An unassigned task can still be linked to an ACTIVE project.
  UPDATE public.tasks
  SET project_id = '71000000-0000-4000-8000-000000000001'
  WHERE id = '72000000-0000-4000-8000-000000000004';

  SELECT project_id INTO actual_project_id
  FROM public.tasks
  WHERE id = '72000000-0000-4000-8000-000000000004';

  IF actual_project_id <> '71000000-0000-4000-8000-000000000001' THEN
    RAISE EXCEPTION 'An ACTIVE project assignment was unexpectedly rejected.';
  END IF;
END
$archive_lifecycle$;

ROLLBACK;

SELECT 'Project archive lifecycle and active-project task-link checks passed.' AS result;
