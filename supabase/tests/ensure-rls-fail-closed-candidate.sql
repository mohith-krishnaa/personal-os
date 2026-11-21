-- Run ONLY in the disposable migration test database or a verified isolated target.
-- The owner-approval GUC is a CI/test attestation here, not a real owner decision.
DO $candidate_test_gate$
BEGIN
  IF current_setting('app.personal_os_restore_target', true) IS DISTINCT FROM 'isolated'
     OR current_setting('app.personal_os_fail_closed_rls_approval', true) IS DISTINCT FROM 'owner-approved' THEN
    RAISE EXCEPTION 'Fail-closed candidate tests require isolated-target and owner-approval attestations.';
  END IF;
  IF session_user IS DISTINCT FROM 'postgres'
     OR current_user IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'Fail-closed candidate tests require a direct postgres session.';
  END IF;
END
$candidate_test_gate$;

DO $candidate_contract$
DECLARE
  function_oid oid := to_regprocedure('public.rls_auto_enable()');
  direct_execute_grantees text[];
BEGIN
  IF function_oid IS NULL OR NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = function_oid
      AND pg_get_userbyid(p.proowner) = 'postgres'
      AND p.prosecdef
      AND p.proconfig = ARRAY['search_path=pg_catalog']::text[]
      AND md5(p.prosrc) = 'b95d4b52e100f89abf4b5afa270a4776'
  ) THEN
    RAISE EXCEPTION 'The exact reviewed fail-closed rls_auto_enable() candidate is not installed.';
  END IF;

  SELECT ARRAY(
    SELECT DISTINCT
      CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(acl.grantee) END
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    WHERE p.oid = function_oid
      AND acl.privilege_type = 'EXECUTE'
    ORDER BY 1
  )
  INTO direct_execute_grantees;

  IF direct_execute_grantees IS DISTINCT FROM ARRAY['postgres', 'service_role']::text[]
     OR has_function_privilege('anon', function_oid, 'EXECUTE')
     OR has_function_privilege('authenticated', function_oid, 'EXECUTE')
     OR NOT has_function_privilege('service_role', function_oid, 'EXECUTE')
     OR NOT has_function_privilege('postgres', function_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'Fail-closed candidate has an unexpected EXECUTE ACL: %', direct_execute_grantees;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_event_trigger e
    WHERE e.evtname = 'ensure_rls'
      AND e.evtfoid = function_oid
      AND e.evtevent = 'ddl_command_end'
      AND e.evttags = ARRAY['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
      AND e.evtenabled = 'O'
      AND pg_get_userbyid(e.evtowner) = 'postgres'
  ) THEN
    RAISE EXCEPTION 'The fail-closed candidate is not attached to the exact enabled ensure_rls trigger.';
  END IF;
END
$candidate_contract$;

-- The successful path still enables RLS on a newly created public table.
CREATE TABLE public.personal_os_fail_closed_success_probe (id integer PRIMARY KEY);

DO $candidate_success$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid = to_regclass('public.personal_os_fail_closed_success_probe')
      AND relrowsecurity
  ) THEN
    RAISE EXCEPTION 'Fail-closed candidate did not enable RLS on a public table.';
  END IF;
END
$candidate_success$;

DROP TABLE public.personal_os_fail_closed_success_probe;

-- Replace the candidate body temporarily with a test-only fault injector that
-- has the same re-raise behavior. The savepoint rollback restores the candidate.
SAVEPOINT fail_closed_candidate_exception_path;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
    IF cmd.schema_name = 'public' THEN
      BEGIN
        IF current_setting('app.personal_os_test_force_rls_enable_failure', true) = 'on' THEN
          RAISE EXCEPTION 'test-only forced RLS-enable failure';
        END IF;
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
          RAISE;
      END;
    END IF;
  END LOOP;
END;
$function$;

DO $assert_failure_aborts_ddl$
DECLARE
  caught_message text;
BEGIN
  PERFORM set_config('app.personal_os_test_force_rls_enable_failure', 'on', true);

  BEGIN
    EXECUTE 'CREATE TABLE public.personal_os_fail_closed_failure_probe (id integer PRIMARY KEY)';
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS caught_message = MESSAGE_TEXT;
  END;

  PERFORM set_config('app.personal_os_test_force_rls_enable_failure', 'off', true);

  IF caught_message IS NULL
     OR position('test-only forced RLS-enable failure' IN caught_message) = 0 THEN
    RAISE EXCEPTION 'Expected the event-trigger RLS failure to propagate and abort CREATE TABLE; received: %', caught_message;
  END IF;

  IF to_regclass('public.personal_os_fail_closed_failure_probe') IS NOT NULL THEN
    RAISE EXCEPTION 'CREATE TABLE left a public table behind after the fail-closed event-trigger error.';
  END IF;
END
$assert_failure_aborts_ddl$;

ROLLBACK TO SAVEPOINT fail_closed_candidate_exception_path;
RELEASE SAVEPOINT fail_closed_candidate_exception_path;

DO $candidate_restored$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = to_regprocedure('public.rls_auto_enable()')
      AND md5(p.prosrc) = 'b95d4b52e100f89abf4b5afa270a4776'
      AND p.prosecdef
      AND p.proconfig = ARRAY['search_path=pg_catalog']::text[]
      AND pg_get_userbyid(p.proowner) = 'postgres'
  ) THEN
    RAISE EXCEPTION 'The fail-closed candidate was not restored after fault-injection rollback.';
  END IF;
END
$candidate_restored$;

CREATE TABLE public.personal_os_fail_closed_after_rollback_probe (id integer PRIMARY KEY);

DO $candidate_after_rollback$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid = to_regclass('public.personal_os_fail_closed_after_rollback_probe')
      AND relrowsecurity
  ) THEN
    RAISE EXCEPTION 'Fail-closed candidate did not resume after fault-injection rollback.';
  END IF;
END
$candidate_after_rollback$;

DROP TABLE public.personal_os_fail_closed_after_rollback_probe;

SELECT 'Fail-closed ensure_rls candidate, successful RLS enablement, error propagation, and rollback restoration passed.' AS result;
