-- Run ONLY on the disposable migration-test database or a verified isolated restore target.
-- The same-session marker is an attestation, not proof of isolation:
--   SET app.personal_os_restore_target = 'isolated';
DO $isolated_target_gate$
BEGIN
  IF current_setting('app.personal_os_restore_target', true) IS DISTINCT FROM 'isolated' THEN
    RAISE EXCEPTION 'Refusing ensure_rls behavior tests without the same-session isolated-target attestation.';
  END IF;
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Run ensure_rls behavior tests as postgres on the isolated target.';
  END IF;
END
$isolated_target_gate$;

DO $assert_ensure_rls_contract$
DECLARE
  function_oid oid := to_regprocedure('public.rls_auto_enable()');
  direct_execute_grantees text[];
  event_trigger record;
BEGIN
  IF function_oid IS NULL THEN
    RAISE EXCEPTION 'public.rls_auto_enable() is missing.';
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

  IF direct_execute_grantees IS DISTINCT FROM ARRAY['postgres', 'service_role']::text[] THEN
    RAISE EXCEPTION 'Unexpected direct rls_auto_enable EXECUTE ACL: %', direct_execute_grantees;
  END IF;

  IF has_function_privilege('anon', function_oid, 'EXECUTE')
     OR has_function_privilege('authenticated', function_oid, 'EXECUTE')
     OR NOT has_function_privilege('service_role', function_oid, 'EXECUTE')
     OR NOT has_function_privilege('postgres', function_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'Unexpected effective rls_auto_enable EXECUTE privileges.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = function_oid
      AND pg_get_userbyid(p.proowner) = 'postgres'
      AND p.prosecdef
      AND p.proconfig = ARRAY['search_path=pg_catalog']::text[]
      AND md5(p.prosrc) = '99be20677b456ea8d3be47bdd44fb369'
  ) THEN
    RAISE EXCEPTION 'rls_auto_enable does not match the reviewed source owner/security/search-path/body fingerprint.';
  END IF;

  SELECT e.evtfoid, e.evtevent, e.evttags, e.evtenabled, e.evtowner
  INTO event_trigger
  FROM pg_event_trigger e
  WHERE e.evtname = 'ensure_rls';

  IF NOT FOUND
     OR event_trigger.evtfoid IS DISTINCT FROM function_oid
     OR event_trigger.evtevent IS DISTINCT FROM 'ddl_command_end'
     OR event_trigger.evttags IS DISTINCT FROM ARRAY['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
     OR event_trigger.evtenabled IS DISTINCT FROM 'O'
     OR pg_get_userbyid(event_trigger.evtowner) IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'ensure_rls does not match the reviewed enabled event-trigger contract.';
  END IF;
END
$assert_ensure_rls_contract$;

-- A new public table is automatically marked RLS-enabled by the restored event trigger.
CREATE TABLE public.personal_os_ensure_rls_public_probe (id integer PRIMARY KEY);

DO $assert_public_table_rls$
DECLARE
  rls_enabled boolean;
BEGIN
  SELECT c.relrowsecurity
  INTO rls_enabled
  FROM pg_class c
  WHERE c.oid = to_regclass('public.personal_os_ensure_rls_public_probe');

  IF NOT FOUND OR rls_enabled IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'ensure_rls did not enable RLS on a newly created public table.';
  END IF;
END
$assert_public_table_rls$;

DROP TABLE public.personal_os_ensure_rls_public_probe;

-- The event-trigger function intentionally skips non-public schemas.
CREATE SCHEMA personal_os_ensure_rls_nonpublic_probe;
CREATE TABLE personal_os_ensure_rls_nonpublic_probe.table_probe (id integer PRIMARY KEY);

DO $assert_nonpublic_table_skip$
DECLARE
  rls_enabled boolean;
BEGIN
  SELECT c.relrowsecurity
  INTO rls_enabled
  FROM pg_class c
  WHERE c.oid = to_regclass('personal_os_ensure_rls_nonpublic_probe.table_probe');

  IF NOT FOUND OR rls_enabled IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'ensure_rls unexpectedly changed RLS for a non-public table.';
  END IF;
END
$assert_nonpublic_table_skip$;

DROP TABLE personal_os_ensure_rls_nonpublic_probe.table_probe;
DROP SCHEMA personal_os_ensure_rls_nonpublic_probe;

-- Fault-inject the inner RLS-enable operation inside a transaction. The test-only
-- branch is rolled back, so the reviewed source function is restored exactly.
BEGIN;

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
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        IF current_setting('app.personal_os_test_force_rls_enable_failure', true) = 'on' THEN
          RAISE EXCEPTION 'test-only forced RLS-enable failure';
        END IF;
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

SET LOCAL app.personal_os_test_force_rls_enable_failure = 'on';
CREATE TABLE public.personal_os_ensure_rls_failure_probe (id integer PRIMARY KEY);

DO $assert_swallowed_failure$
DECLARE
  rls_enabled boolean;
BEGIN
  SELECT c.relrowsecurity
  INTO rls_enabled
  FROM pg_class c
  WHERE c.oid = to_regclass('public.personal_os_ensure_rls_failure_probe');

  IF NOT FOUND OR rls_enabled IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Expected the injected inner RLS-enable failure to be logged/swallowed while CREATE TABLE succeeds without RLS.';
  END IF;
END
$assert_swallowed_failure$;

ROLLBACK;

-- The rollback must restore the reviewed function and leave the event trigger active.
DO $assert_source_function_restored$
DECLARE
  function_oid oid := to_regprocedure('public.rls_auto_enable()');
BEGIN
  IF function_oid IS NULL OR NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = function_oid
      AND md5(p.prosrc) = '99be20677b456ea8d3be47bdd44fb369'
      AND p.proconfig = ARRAY['search_path=pg_catalog']::text[]
      AND p.prosecdef
      AND pg_get_userbyid(p.proowner) = 'postgres'
  ) THEN
    RAISE EXCEPTION 'The exception-path transaction did not restore the exact source function.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_event_trigger e
    WHERE e.evtname = 'ensure_rls'
      AND e.evtfoid = function_oid
      AND e.evtenabled = 'O'
  ) THEN
    RAISE EXCEPTION 'ensure_rls was not left enabled after the exception-path rollback.';
  END IF;
END
$assert_source_function_restored$;

CREATE TABLE public.personal_os_ensure_rls_after_rollback_probe (id integer PRIMARY KEY);

DO $assert_after_rollback_rls$
DECLARE
  rls_enabled boolean;
BEGIN
  SELECT c.relrowsecurity
  INTO rls_enabled
  FROM pg_class c
  WHERE c.oid = to_regclass('public.personal_os_ensure_rls_after_rollback_probe');

  IF NOT FOUND OR rls_enabled IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'ensure_rls did not resume its normal behavior after the fault-injection transaction rolled back.';
  END IF;
END
$assert_after_rollback_rls$;

DROP TABLE public.personal_os_ensure_rls_after_rollback_probe;
