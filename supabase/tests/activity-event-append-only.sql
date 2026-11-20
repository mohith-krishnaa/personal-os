-- Trusted-writer, application-role append-only access, and retention-owner regression.
-- Fixtures are rolled back; Owner A and Owner B exist in auth.users.
BEGIN;

DO $catalog_contract$
DECLARE
  v_policy_count integer;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Append-only catalog assertions must run as the database owner.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid = 'public.activity_events'::regclass
      AND relrowsecurity
  ) THEN
    RAISE EXCEPTION 'activity_events RLS must remain enabled.';
  END IF;

  SELECT count(*) INTO v_policy_count
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'activity_events';

  IF v_policy_count <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'activity_events'
         AND policyname = 'activity_events_select_owner'
         AND cmd = 'SELECT'
         AND roles @> ARRAY['authenticated']::name[]
         AND qual ILIKE '%auth.uid%'
     )
     OR EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'activity_events'
         AND policyname = 'activity_events_insert_owner'
     )
     OR EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'activity_events'
         AND cmd IN ('ALL', 'UPDATE', 'DELETE')
     ) THEN
    RAISE EXCEPTION 'activity_events must have exactly one owner-scoped SELECT policy and no client INSERT or mutation policy.';
  END IF;

  IF NOT has_table_privilege('authenticated', 'public.activity_events', 'SELECT')
     OR has_table_privilege('authenticated', 'public.activity_events', 'INSERT')
     OR has_table_privilege('authenticated', 'public.activity_events', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.activity_events', 'DELETE')
     OR has_table_privilege('authenticated', 'public.activity_events', 'TRUNCATE') THEN
    RAISE EXCEPTION 'authenticated must have SELECT only on activity_events.';
  END IF;

  IF has_table_privilege('anon', 'public.activity_events', 'SELECT')
     OR has_table_privilege('anon', 'public.activity_events', 'INSERT')
     OR has_table_privilege('anon', 'public.activity_events', 'UPDATE')
     OR has_table_privilege('anon', 'public.activity_events', 'DELETE')
     OR has_table_privilege('anon', 'public.activity_events', 'TRUNCATE') THEN
    RAISE EXCEPTION 'anon must have no activity_events table privileges.';
  END IF;

  IF NOT has_table_privilege('service_role', 'public.activity_events', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.activity_events', 'INSERT')
     OR has_table_privilege('service_role', 'public.activity_events', 'UPDATE')
     OR has_table_privilege('service_role', 'public.activity_events', 'DELETE')
     OR has_table_privilege('service_role', 'public.activity_events', 'TRUNCATE') THEN
    RAISE EXCEPTION 'service_role must retain SELECT/INSERT only on activity_events.';
  END IF;

  IF NOT has_table_privilege('postgres', 'public.activity_events', 'INSERT')
     OR NOT has_table_privilege('postgres', 'public.activity_events', 'DELETE')
     OR NOT has_table_privilege('postgres', 'public.activity_events', 'TRUNCATE') THEN
    RAISE EXCEPTION 'The postgres table owner must retain trusted writer and maintenance privileges.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.tasks'::regclass
      AND t.tgname = 'tasks_record_activity_event'
      AND NOT t.tgisinternal
      AND t.tgenabled = 'O'
      AND p.prosecdef
      AND pg_get_userbyid(p.proowner) = 'postgres'
      AND coalesce(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public']::text[]
  )
     OR has_function_privilege('authenticated', 'public.record_task_activity_event()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_task_activity_event()', 'EXECUTE') THEN
    RAISE EXCEPTION 'The task event trigger must be postgres-owned SECURITY DEFINER and unavailable for direct authenticated execution.';
  END IF;
END;
$catalog_contract$;

INSERT INTO public.activity_events (
  id, user_id, event_type, entity_type, entity_id, metadata
)
VALUES
  (
    '96000000-0000-4000-8000-000000000001',
    '11111111-1111-4111-8111-111111111111',
    'APPEND_ONLY_TEST',
    'TEST',
    '96000000-0000-4000-8000-000000000001',
    '{"marker":"owner-a"}'::jsonb
  ),
  (
    '96000000-0000-4000-8000-000000000002',
    '22222222-2222-4222-8222-222222222222',
    'APPEND_ONLY_TEST',
    'TEST',
    '96000000-0000-4000-8000-000000000002',
    '{"marker":"owner-b"}'::jsonb
  );

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

DO $authenticated_contract$
DECLARE
  v_event_id constant uuid := '96000000-0000-4000-8000-000000000001';
  v_error_code text;
  v_visible_count integer;
BEGIN
  IF current_user <> 'authenticated'
     OR auth.uid() <> '11111111-1111-4111-8111-111111111111'::uuid THEN
    RAISE EXCEPTION 'Authenticated append-only assertions must run as Owner A.';
  END IF;

  v_error_code := NULL;
  BEGIN
    INSERT INTO public.activity_events (
      id, user_id, event_type, entity_type, entity_id, metadata
    )
    VALUES (
      '96000000-0000-4000-8000-000000000003',
      auth.uid(),
      'TASK_COMPLETED',
      'TASK',
      '97000000-0000-4000-8000-000000000001',
      '{"status":"COMPLETED"}'::jsonb
    );
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
  END;

  IF v_error_code IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'Authenticated direct event INSERT must be denied with SQLSTATE 42501; got %.', v_error_code;
  END IF;

  -- The task trigger is the authenticated writer boundary: task INSERT still
  -- creates its event even though the client has no activity_events INSERT grant.
  INSERT INTO public.tasks (id, user_id, title)
  VALUES ('97000000-0000-4000-8000-000000000001', auth.uid(), 'Trusted trigger write');

  IF NOT EXISTS (
    SELECT 1 FROM public.activity_events
    WHERE user_id = auth.uid()
      AND event_type = 'TASK_CREATED'
      AND entity_type = 'TASK'
      AND entity_id = '97000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'Authenticated task INSERT did not create its trusted TASK_CREATED event.';
  END IF;

  SELECT count(*) INTO v_visible_count
  FROM public.activity_events
  WHERE id = '96000000-0000-4000-8000-000000000002';

  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'Owner A can read Owner B activity events.';
  END IF;

  v_error_code := NULL;
  BEGIN
    UPDATE public.activity_events
    SET metadata = '{"marker":"tampered"}'::jsonb
    WHERE id = v_event_id;
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
  END;

  IF v_error_code IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'Authenticated activity-event UPDATE must be denied; got SQLSTATE %.', v_error_code;
  END IF;

  v_error_code := NULL;
  BEGIN
    DELETE FROM public.activity_events WHERE id = v_event_id;
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
  END;

  IF v_error_code IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'Authenticated activity-event DELETE must be denied; got SQLSTATE %.', v_error_code;
  END IF;

  v_error_code := NULL;
  BEGIN
    EXECUTE 'TRUNCATE TABLE public.activity_events';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
  END;

  IF v_error_code IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'Authenticated activity-event TRUNCATE must be denied; got SQLSTATE %.', v_error_code;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.activity_events
    WHERE id = v_event_id AND metadata ->> 'marker' = 'owner-a'
  ) THEN
    RAISE EXCEPTION 'Denied mutation attempts changed or removed Owner A event.';
  END IF;
END;
$authenticated_contract$;

RESET ROLE;
SET LOCAL ROLE service_role;

DO $service_role_contract$
DECLARE
  v_error_code text;
BEGIN
  IF current_user <> 'service_role' THEN
    RAISE EXCEPTION 'Service-role append-only assertions must run as service_role.';
  END IF;

  v_error_code := NULL;
  BEGIN
    UPDATE public.activity_events
    SET metadata = '{"marker":"service-tamper"}'::jsonb
    WHERE id = '96000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
  END;
  IF v_error_code IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'service_role activity-event UPDATE must be denied; got SQLSTATE %.', v_error_code;
  END IF;

  v_error_code := NULL;
  BEGIN
    DELETE FROM public.activity_events
    WHERE id = '96000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
  END;
  IF v_error_code IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'service_role activity-event DELETE must be denied; got SQLSTATE %.', v_error_code;
  END IF;

  v_error_code := NULL;
  BEGIN
    EXECUTE 'TRUNCATE TABLE public.activity_events';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
  END;
  IF v_error_code IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'service_role activity-event TRUNCATE must be denied; got SQLSTATE %.', v_error_code;
  END IF;
END;
$service_role_contract$;

RESET ROLE;

-- The FK cascade remains the supported Auth-account cleanup path.
INSERT INTO auth.users (id)
VALUES ('96000000-0000-4000-8000-000000000030');

INSERT INTO public.activity_events (
  user_id, event_type, entity_type, entity_id
)
VALUES (
  '96000000-0000-4000-8000-000000000030',
  'APPEND_ONLY_AUTH_CASCADE_TEST',
  'TEST',
  '96000000-0000-4000-8000-000000000030'
);

DELETE FROM auth.users
WHERE id = '96000000-0000-4000-8000-000000000030';

DO $auth_cascade$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.activity_events
    WHERE user_id = '96000000-0000-4000-8000-000000000030'
  ) THEN
    RAISE EXCEPTION 'Auth-account deletion must still cascade to activity_events.';
  END IF;
END;
$auth_cascade$;

ROLLBACK;

SELECT 'Application-role append-only activity-event access, owner isolation, maintenance privileges, and Auth cascade passed.' AS result;
