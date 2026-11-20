-- Application-role append-only access and retention-owner regression.
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

  IF v_policy_count <> 2
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'activity_events'
         AND policyname = 'activity_events_select_owner'
         AND cmd = 'SELECT'
         AND roles @> ARRAY['authenticated']::name[]
         AND qual ILIKE '%auth.uid%'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'activity_events'
         AND policyname = 'activity_events_insert_owner'
         AND cmd = 'INSERT'
         AND roles @> ARRAY['authenticated']::name[]
         AND with_check ILIKE '%auth.uid%'
     )
     OR EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'activity_events'
         AND cmd IN ('ALL', 'UPDATE', 'DELETE')
     ) THEN
    RAISE EXCEPTION 'activity_events must have exactly owner-scoped SELECT/INSERT policies and no mutation policy.';
  END IF;

  IF NOT has_table_privilege('authenticated', 'public.activity_events', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.activity_events', 'INSERT')
     OR has_table_privilege('authenticated', 'public.activity_events', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.activity_events', 'DELETE')
     OR has_table_privilege('authenticated', 'public.activity_events', 'TRUNCATE') THEN
    RAISE EXCEPTION 'authenticated must have SELECT/INSERT only on activity_events.';
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

  IF NOT has_table_privilege('postgres', 'public.activity_events', 'DELETE')
     OR NOT has_table_privilege('postgres', 'public.activity_events', 'TRUNCATE') THEN
    RAISE EXCEPTION 'The postgres table owner must retain controlled maintenance privileges.';
  END IF;
END;
$catalog_contract$;

INSERT INTO public.activity_events (
  id, user_id, event_type, entity_type, entity_id, metadata
)
VALUES (
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

  INSERT INTO public.activity_events (
    id, user_id, event_type, entity_type, entity_id, metadata
  )
  VALUES (
    v_event_id, auth.uid(), 'APPEND_ONLY_TEST', 'TEST', v_event_id,
    '{"marker":"owner-a"}'::jsonb
  );

  SELECT count(*) INTO v_visible_count
  FROM public.activity_events
  WHERE id = '96000000-0000-4000-8000-000000000002';

  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'Owner A can read Owner B activity events.';
  END IF;

  v_error_code := NULL;
  BEGIN
    INSERT INTO public.activity_events (
      user_id, event_type, entity_type, entity_id
    )
    VALUES (
      '22222222-2222-4222-8222-222222222222',
      'APPEND_ONLY_CROSS_OWNER_TEST',
      'TEST',
      '96000000-0000-4000-8000-000000000003'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
  END;

  IF v_error_code IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'Cross-owner activity-event INSERT must fail with SQLSTATE 42501; got %.', v_error_code;
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
