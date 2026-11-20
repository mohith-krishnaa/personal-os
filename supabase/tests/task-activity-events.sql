-- Transactional task activity-event regression.
-- Existing migration assertions seed the two auth.users fixtures used below.
CREATE OR REPLACE FUNCTION public.personal_os_test_fail_task_activity_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF current_setting('personal_os.test_fail_task_activity', true) = 'on'
     AND NEW.entity_type = 'TASK'
     AND NEW.entity_id IN (
       '91000000-0000-4000-8000-000000000001'::uuid,
       '91000000-0000-4000-8000-000000000002'::uuid,
       '91000000-0000-4000-8000-000000000003'::uuid,
       '91000000-0000-4000-8000-000000000005'::uuid
     ) THEN
    RAISE EXCEPTION 'injected task activity event failure' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.personal_os_test_fail_task_activity_event() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.personal_os_test_fail_task_activity_event() TO authenticated;

DROP TRIGGER IF EXISTS personal_os_test_fail_task_activity_event ON public.activity_events;
CREATE TRIGGER personal_os_test_fail_task_activity_event
BEFORE INSERT ON public.activity_events
FOR EACH ROW
EXECUTE FUNCTION public.personal_os_test_fail_task_activity_event();

SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

DO $task_activity$
DECLARE
  error_message text;
  error_constraint text;
  event_count integer;
  root_id uuid := '91000000-0000-4000-8000-000000000004';
BEGIN
  IF current_user <> 'authenticated' OR auth.uid() <> '11111111-1111-4111-8111-111111111111'::uuid THEN
    RAISE EXCEPTION 'Task activity assertions must execute as Owner A under authenticated role.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.tasks'::regclass
      AND t.tgname = 'tasks_record_activity_event'
      AND NOT t.tgisinternal AND t.tgenabled = 'O'
      AND p.prosecdef
      AND pg_get_userbyid(p.proowner) = 'postgres'
      AND coalesce(p.proconfig, array[]::text[]) @> array['search_path=pg_catalog, public']::text[]
  ) THEN
    RAISE EXCEPTION 'Task activity trigger must be postgres-owned SECURITY DEFINER and use a fixed search_path.';
  END IF;

  IF has_function_privilege('anon', 'public.record_task_activity_event()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_task_activity_event()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_task_activity_event()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Task activity trigger EXECUTE grants are incorrect.';
  END IF;

  error_message := NULL;
  PERFORM set_config('personal_os.test_fail_task_activity', 'on', true);
  BEGIN
    INSERT INTO public.tasks (id, user_id, title)
    VALUES ('91000000-0000-4000-8000-000000000001', auth.uid(), 'Atomic create');
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
  END;
  PERFORM set_config('personal_os.test_fail_task_activity', 'off', true);

  IF error_message IS DISTINCT FROM 'injected task activity event failure'
     OR EXISTS (SELECT 1 FROM public.tasks WHERE id = '91000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'TASK_CREATED failure did not roll back the task row.';
  END IF;

  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('91000000-0000-4000-8000-000000000001', auth.uid(), 'Atomic create');

  SELECT count(*) INTO event_count
  FROM public.activity_events
  WHERE user_id = auth.uid() AND entity_id = '91000000-0000-4000-8000-000000000001' AND event_type = 'TASK_CREATED';
  IF event_count <> 1 THEN
    RAISE EXCEPTION 'Successful task creation must produce exactly one TASK_CREATED event; found %.', event_count;
  END IF;

  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('91000000-0000-4000-8000-000000000002', auth.uid(), 'Before update');

  error_message := NULL;
  PERFORM set_config('personal_os.test_fail_task_activity', 'on', true);
  BEGIN
    UPDATE public.tasks SET title = 'Failed update', updated_at = now()
    WHERE id = '91000000-0000-4000-8000-000000000002' AND user_id = auth.uid();
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
  END;
  PERFORM set_config('personal_os.test_fail_task_activity', 'off', true);

  IF error_message IS DISTINCT FROM 'injected task activity event failure'
     OR NOT EXISTS (SELECT 1 FROM public.tasks WHERE id = '91000000-0000-4000-8000-000000000002' AND title = 'Before update')
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE entity_id = '91000000-0000-4000-8000-000000000002' AND event_type = 'TASK_UPDATED') THEN
    RAISE EXCEPTION 'TASK_UPDATED failure did not roll back the task update.';
  END IF;

  UPDATE public.tasks SET title = 'After update', updated_at = now()
  WHERE id = '91000000-0000-4000-8000-000000000002' AND user_id = auth.uid();
  UPDATE public.tasks SET title = 'After update', updated_at = now()
  WHERE id = '91000000-0000-4000-8000-000000000002' AND user_id = auth.uid();

  SELECT count(*) INTO event_count FROM public.activity_events
  WHERE entity_id = '91000000-0000-4000-8000-000000000002' AND event_type = 'TASK_UPDATED';
  IF event_count <> 1 THEN
    RAISE EXCEPTION 'A successful task update and no-op retry must produce one TASK_UPDATED event; found %.', event_count;
  END IF;

  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('91000000-0000-4000-8000-000000000003', auth.uid(), 'Status task');

  error_message := NULL;
  PERFORM set_config('personal_os.test_fail_task_activity', 'on', true);
  BEGIN
    UPDATE public.tasks SET status = 'COMPLETED', completed_at = now(), updated_at = now()
    WHERE id = '91000000-0000-4000-8000-000000000003' AND user_id = auth.uid();
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
  END;
  PERFORM set_config('personal_os.test_fail_task_activity', 'off', true);

  IF error_message IS DISTINCT FROM 'injected task activity event failure'
     OR NOT EXISTS (SELECT 1 FROM public.tasks WHERE id = '91000000-0000-4000-8000-000000000003' AND status = 'TODO' AND completed_at IS NULL)
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE entity_id = '91000000-0000-4000-8000-000000000003' AND event_type = 'TASK_COMPLETED') THEN
    RAISE EXCEPTION 'TASK_COMPLETED failure did not roll back the status transition.';
  END IF;

  UPDATE public.tasks SET status = 'COMPLETED', completed_at = now(), updated_at = now()
  WHERE id = '91000000-0000-4000-8000-000000000003' AND user_id = auth.uid();
  UPDATE public.tasks SET status = 'COMPLETED', completed_at = completed_at, updated_at = now()
  WHERE id = '91000000-0000-4000-8000-000000000003' AND user_id = auth.uid();

  SELECT count(*) INTO event_count FROM public.activity_events
  WHERE entity_id = '91000000-0000-4000-8000-000000000003' AND event_type = 'TASK_COMPLETED';
  IF event_count <> 1 THEN
    RAISE EXCEPTION 'A completion transition and no-op retry must produce one TASK_COMPLETED event; found %.', event_count;
  END IF;

  INSERT INTO public.tasks (id, user_id, title, recurrence_rule, due_at)
  VALUES (root_id, auth.uid(), 'Recurring root', '{"frequency":"DAILY","interval":1}'::jsonb, '2099-01-01T09:00:00Z');
  UPDATE public.tasks SET recurrence_parent_id = root_id, updated_at = now()
  WHERE id = root_id AND user_id = auth.uid();

  SELECT count(*) INTO event_count FROM public.activity_events
  WHERE entity_id = root_id AND event_type = 'TASK_UPDATED';
  IF event_count <> 0 THEN
    RAISE EXCEPTION 'Initializing a recurring root self-link emitted an extra TASK_UPDATED event.';
  END IF;

  error_message := NULL;
  PERFORM set_config('personal_os.test_fail_task_activity', 'on', true);
  BEGIN
    INSERT INTO public.tasks (id, user_id, recurrence_parent_id, recurrence_rule, due_at, title)
    VALUES ('91000000-0000-4000-8000-000000000005', auth.uid(), root_id,
            '{"frequency":"DAILY","interval":1}'::jsonb, '2099-01-02T09:00:00Z', 'Recurring occurrence');
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
  END;
  PERFORM set_config('personal_os.test_fail_task_activity', 'off', true);

  IF error_message IS DISTINCT FROM 'injected task activity event failure'
     OR EXISTS (SELECT 1 FROM public.tasks WHERE id = '91000000-0000-4000-8000-000000000005') THEN
    RAISE EXCEPTION 'Recurrence event failure did not roll back the occurrence row.';
  END IF;

  INSERT INTO public.tasks (id, user_id, recurrence_parent_id, recurrence_rule, due_at, title)
  VALUES ('91000000-0000-4000-8000-000000000005', auth.uid(), root_id,
          '{"frequency":"DAILY","interval":1}'::jsonb, '2099-01-02T09:00:00Z', 'Recurring occurrence');

  SELECT count(*) INTO event_count FROM public.activity_events
  WHERE entity_id = '91000000-0000-4000-8000-000000000005'
    AND event_type = 'TASK_RECURRENCE_GENERATED'
    AND metadata ->> 'source_task_id' = root_id::text;
  IF event_count <> 1 THEN
    RAISE EXCEPTION 'Recurrence generation must produce one event referencing its source task; found %.', event_count;
  END IF;

  error_constraint := NULL;
  BEGIN
    INSERT INTO public.tasks (id, user_id, recurrence_parent_id, recurrence_rule, due_at, title)
    VALUES ('91000000-0000-4000-8000-000000000008', auth.uid(), root_id,
            '{"frequency":"DAILY","interval":1}'::jsonb, '2099-01-02T09:00:00Z', 'Duplicate occurrence');
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
  END;
  IF error_constraint IS DISTINCT FROM 'tasks_recurring_occurrence_unique'
     OR (SELECT count(*) FROM public.tasks WHERE user_id = auth.uid() AND recurrence_parent_id = root_id AND due_at = '2099-01-02T09:00:00Z') <> 1
     OR (SELECT count(*) FROM public.activity_events WHERE entity_id = '91000000-0000-4000-8000-000000000005' AND event_type = 'TASK_RECURRENCE_GENERATED') <> 1 THEN
    RAISE EXCEPTION 'Duplicate recurrence request created a second occurrence or event.';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('91000000-0000-4000-8000-000000000007', auth.uid(), 'Owner B task');

  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  SELECT count(*) INTO event_count FROM public.activity_events
  WHERE entity_id = '91000000-0000-4000-8000-000000000007' AND event_type = 'TASK_CREATED';
  IF event_count <> 0 THEN RAISE EXCEPTION 'Owner A can read Owner B task activity events.'; END IF;

  PERFORM set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
  SELECT count(*) INTO event_count FROM public.activity_events
  WHERE entity_id = '91000000-0000-4000-8000-000000000007' AND event_type = 'TASK_CREATED';
  IF event_count <> 1 THEN RAISE EXCEPTION 'Owner B cannot read its own task activity event.'; END IF;
END
$task_activity$;

RESET ROLE;
DROP TRIGGER IF EXISTS personal_os_test_fail_task_activity_event ON public.activity_events;
DROP FUNCTION IF EXISTS public.personal_os_test_fail_task_activity_event();
SET request.jwt.claim.sub = '';

SELECT 'Transactional task activity events, no-op retries, recurrence, and owner isolation passed.' AS result;
