-- Transactional TASK_DELETED event regression.
-- Existing migration assertions seed Owner A and Owner B in auth.users.

CREATE OR REPLACE FUNCTION public.personal_os_test_fail_task_delete_activity_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF current_setting('personal_os.test_fail_task_delete_activity', true) = 'on'
     AND NEW.event_type = 'TASK_DELETED'
     AND NEW.entity_id IN (
       '93000000-0000-4000-8000-000000000001'::uuid,
       '93000000-0000-4000-8000-000000000011'::uuid
     ) THEN
    RAISE EXCEPTION 'injected task delete activity event failure' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.personal_os_test_fail_task_delete_activity_event() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.personal_os_test_fail_task_delete_activity_event() TO authenticated;

DROP TRIGGER IF EXISTS personal_os_test_fail_task_delete_activity_event ON public.activity_events;
CREATE TRIGGER personal_os_test_fail_task_delete_activity_event
BEFORE INSERT ON public.activity_events
FOR EACH ROW
EXECUTE FUNCTION public.personal_os_test_fail_task_delete_activity_event();

SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

DO $task_delete$
DECLARE
  error_message text;
  affected_rows integer;
  event_count integer;
  trigger_definition text;
BEGIN
  IF current_user <> 'authenticated' OR auth.uid() <> '11111111-1111-4111-8111-111111111111'::uuid THEN
    RAISE EXCEPTION 'Task delete assertions must execute as Owner A under authenticated role.';
  END IF;

  SELECT pg_get_triggerdef(t.oid)
    INTO trigger_definition
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.tasks'::regclass
    AND t.tgname = 'tasks_record_activity_event'
    AND NOT t.tgisinternal
    AND t.tgenabled = 'O';

  IF trigger_definition IS NULL OR trigger_definition NOT ILIKE '%DELETE%' THEN
    RAISE EXCEPTION 'Task activity trigger must include DELETE.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.tasks'::regclass
      AND t.tgname = 'tasks_record_activity_event'
      AND NOT t.tgisinternal
      AND t.tgenabled = 'O'
      AND NOT p.prosecdef
      AND coalesce(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public']::text[]
      AND p.prosrc LIKE '%TASK_DELETED%'
      AND p.prosrc LIKE '%auth.uid() IS DISTINCT FROM OLD.user_id%'
  ) THEN
    RAISE EXCEPTION 'Task delete event trigger must be SECURITY INVOKER, fixed-search-path, and owner-context guarded.';
  END IF;

  IF has_function_privilege('anon', 'public.record_task_activity_event()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.record_task_activity_event()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_task_activity_event()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Task activity trigger EXECUTE grants are incorrect.';
  END IF;

  -- A failed direct delete must roll back the row deletion and event insert.
  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('93000000-0000-4000-8000-000000000001', auth.uid(), 'Direct delete failure');

  error_message := NULL;
  PERFORM set_config('personal_os.test_fail_task_delete_activity', 'on', true);
  BEGIN
    DELETE FROM public.tasks
    WHERE id = '93000000-0000-4000-8000-000000000001' AND user_id = auth.uid();
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
  END;
  PERFORM set_config('personal_os.test_fail_task_delete_activity', 'off', true);

  IF error_message IS DISTINCT FROM 'injected task delete activity event failure'
     OR NOT EXISTS (SELECT 1 FROM public.tasks WHERE id = '93000000-0000-4000-8000-000000000001')
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE entity_id = '93000000-0000-4000-8000-000000000001' AND event_type = 'TASK_DELETED') THEN
    RAISE EXCEPTION 'TASK_DELETED insertion failure did not roll back the direct task deletion.';
  END IF;

  DELETE FROM public.tasks
  WHERE id = '93000000-0000-4000-8000-000000000001' AND user_id = auth.uid();
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN RAISE EXCEPTION 'Expected one direct task deletion, found %.', affected_rows; END IF;

  SELECT count(*) INTO event_count
  FROM public.activity_events
  WHERE user_id = auth.uid()
    AND entity_type = 'TASK'
    AND entity_id = '93000000-0000-4000-8000-000000000001'
    AND event_type = 'TASK_DELETED'
    AND metadata ->> 'title' = 'Direct delete failure'
    AND metadata ->> 'status' = 'TODO';
  IF event_count <> 1 THEN RAISE EXCEPTION 'Direct deletion must persist exactly one TASK_DELETED snapshot event; found %.', event_count; END IF;

  DELETE FROM public.tasks
  WHERE id = '93000000-0000-4000-8000-000000000001' AND user_id = auth.uid();
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  SELECT count(*) INTO event_count
  FROM public.activity_events
  WHERE entity_id = '93000000-0000-4000-8000-000000000001' AND event_type = 'TASK_DELETED';
  IF affected_rows <> 0 OR event_count <> 1 THEN
    RAISE EXCEPTION 'A repeated delete must not create another TASK_DELETED event.';
  END IF;

  -- Build a three-level hierarchy. Deleting the root must emit one event per row.
  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('93000000-0000-4000-8000-000000000010', auth.uid(), 'Cascade root');
  INSERT INTO public.tasks (id, user_id, parent_task_id, title)
  VALUES ('93000000-0000-4000-8000-000000000011', auth.uid(), '93000000-0000-4000-8000-000000000010', 'Cascade child');
  INSERT INTO public.tasks (id, user_id, parent_task_id, title)
  VALUES ('93000000-0000-4000-8000-000000000012', auth.uid(), '93000000-0000-4000-8000-000000000011', 'Cascade grandchild');

  error_message := NULL;
  PERFORM set_config('personal_os.test_fail_task_delete_activity', 'on', true);
  BEGIN
    DELETE FROM public.tasks
    WHERE id = '93000000-0000-4000-8000-000000000010' AND user_id = auth.uid();
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
  END;
  PERFORM set_config('personal_os.test_fail_task_delete_activity', 'off', true);

  IF error_message IS DISTINCT FROM 'injected task delete activity event failure'
     OR (SELECT count(*) FROM public.tasks WHERE id IN (
       '93000000-0000-4000-8000-000000000010',
       '93000000-0000-4000-8000-000000000011',
       '93000000-0000-4000-8000-000000000012'
     )) <> 3
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE entity_id IN (
       '93000000-0000-4000-8000-000000000010',
       '93000000-0000-4000-8000-000000000011',
       '93000000-0000-4000-8000-000000000012'
     ) AND event_type = 'TASK_DELETED') THEN
    RAISE EXCEPTION 'A descendant event failure did not roll back the complete task cascade.';
  END IF;

  DELETE FROM public.tasks
  WHERE id = '93000000-0000-4000-8000-000000000010' AND user_id = auth.uid();
  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  IF affected_rows <> 1
     OR EXISTS (SELECT 1 FROM public.tasks WHERE id IN (
       '93000000-0000-4000-8000-000000000010',
       '93000000-0000-4000-8000-000000000011',
       '93000000-0000-4000-8000-000000000012'
     )) THEN
    RAISE EXCEPTION 'Deleting the hierarchy root did not cascade to every descendant.';
  END IF;

  SELECT count(*) INTO event_count
  FROM public.activity_events
  WHERE user_id = auth.uid()
    AND event_type = 'TASK_DELETED'
    AND entity_id IN (
      '93000000-0000-4000-8000-000000000010',
      '93000000-0000-4000-8000-000000000011',
      '93000000-0000-4000-8000-000000000012'
    );
  IF event_count <> 3
     OR NOT EXISTS (SELECT 1 FROM public.activity_events WHERE entity_id = '93000000-0000-4000-8000-000000000010' AND event_type = 'TASK_DELETED' AND metadata ->> 'title' = 'Cascade root')
     OR NOT EXISTS (SELECT 1 FROM public.activity_events WHERE entity_id = '93000000-0000-4000-8000-000000000011' AND event_type = 'TASK_DELETED' AND metadata ->> 'title' = 'Cascade child' AND metadata ->> 'parent_task_id' = '93000000-0000-4000-8000-000000000010')
     OR NOT EXISTS (SELECT 1 FROM public.activity_events WHERE entity_id = '93000000-0000-4000-8000-000000000012' AND event_type = 'TASK_DELETED' AND metadata ->> 'title' = 'Cascade grandchild' AND metadata ->> 'parent_task_id' = '93000000-0000-4000-8000-000000000011') THEN
    RAISE EXCEPTION 'Parent and descendant TASK_DELETED snapshot events are incomplete.';
  END IF;

  -- Owner B must not be able to delete Owner A's task or create its event.
  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('93000000-0000-4000-8000-000000000020', auth.uid(), 'Owner A protected task');

  PERFORM set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
  DELETE FROM public.tasks WHERE id = '93000000-0000-4000-8000-000000000020';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN RAISE EXCEPTION 'Owner B deleted Owner A task.'; END IF;

  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE id = '93000000-0000-4000-8000-000000000020' AND user_id = auth.uid())
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE entity_id = '93000000-0000-4000-8000-000000000020' AND event_type = 'TASK_DELETED') THEN
    RAISE EXCEPTION 'Cross-owner delete attempt changed the task or emitted a deletion event.';
  END IF;

  -- Owner B can delete its own task; Owner A cannot read that event.
  PERFORM set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('93000000-0000-4000-8000-000000000021', auth.uid(), 'Owner B own task');
  DELETE FROM public.tasks WHERE id = '93000000-0000-4000-8000-000000000021' AND user_id = auth.uid();

  SELECT count(*) INTO event_count
  FROM public.activity_events
  WHERE entity_id = '93000000-0000-4000-8000-000000000021' AND event_type = 'TASK_DELETED';
  IF event_count <> 1 THEN RAISE EXCEPTION 'Owner B deletion must create one owner-scoped event.'; END IF;

  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  SELECT count(*) INTO event_count
  FROM public.activity_events
  WHERE entity_id = '93000000-0000-4000-8000-000000000021' AND event_type = 'TASK_DELETED';
  IF event_count <> 0 THEN RAISE EXCEPTION 'Owner A can read Owner B TASK_DELETED event.'; END IF;
END
$task_delete$;

RESET ROLE;
DROP TRIGGER IF EXISTS personal_os_test_fail_task_delete_activity_event ON public.activity_events;
DROP FUNCTION IF EXISTS public.personal_os_test_fail_task_delete_activity_event();

-- Model Auth account deletion under an administrative context. Both task and
-- activity rows cascade from auth.users; no per-user delete event is retained.
SET request.jwt.claim.sub = '';
INSERT INTO auth.users (id)
VALUES ('93000000-0000-4000-8000-000000000030');

INSERT INTO public.tasks (id, user_id, title)
VALUES (
  '93000000-0000-4000-8000-000000000030',
  '93000000-0000-4000-8000-000000000030',
  'Auth account cascade'
);

DELETE FROM auth.users
WHERE id = '93000000-0000-4000-8000-000000000030';

DO $auth_cascade$
BEGIN
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = '93000000-0000-4000-8000-000000000030')
     OR EXISTS (SELECT 1 FROM public.tasks WHERE id = '93000000-0000-4000-8000-000000000030')
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE user_id = '93000000-0000-4000-8000-000000000030') THEN
    RAISE EXCEPTION 'Auth account deletion must still cascade without task-delete event FK failure.';
  END IF;
END
$auth_cascade$;

SELECT 'Transactional TASK_DELETED events, descendant cascades, rollback, owner isolation, and Auth account cleanup passed.' AS result;
