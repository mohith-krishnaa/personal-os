-- Candidate fail-closed replacement for the project-installed ensure_rls function.
-- This is NOT a migration and must never be run against production by this automation.
-- Apply only to a fully restored isolated target after an explicit owner decision.
--
-- In this same session, after verifying the isolated project reference, set:
--   SET app.personal_os_restore_target = 'isolated';
--   SET app.personal_os_fail_closed_rls_approval = 'owner-approved';
-- The second setting is an operator attestation, not proof of approval.

DO $apply_fail_closed_rls$
DECLARE
  function_oid oid;
  function_owner_oid oid;
  function_owner text;
  function_security_definer boolean;
  function_config text[];
  function_source text;
  source_fingerprint text;
  direct_execute_grantees text[];
  event_trigger record;
  final_event_trigger record;
BEGIN
  IF current_setting('app.personal_os_restore_target', true) IS DISTINCT FROM 'isolated' THEN
    RAISE EXCEPTION 'Refusing fail-closed RLS candidate: isolated-target attestation is missing.';
  END IF;

  IF current_setting('app.personal_os_fail_closed_rls_approval', true) IS DISTINCT FROM 'owner-approved' THEN
    RAISE EXCEPTION 'Refusing fail-closed RLS candidate: explicit owner approval attestation is missing.';
  END IF;

  IF session_user IS DISTINCT FROM 'postgres'
     OR current_user IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'Refusing fail-closed RLS candidate: connect directly as the Supabase postgres role.';
  END IF;

  SELECT
    p.oid,
    p.proowner,
    pg_get_userbyid(p.proowner),
    p.prosecdef,
    p.proconfig,
    p.prosrc,
    md5(p.prosrc)
  INTO
    function_oid,
    function_owner_oid,
    function_owner,
    function_security_definer,
    function_config,
    function_source,
    source_fingerprint
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'rls_auto_enable'
    AND p.pronargs = 0
    AND p.prorettype = 'event_trigger'::regtype
    AND p.prokind = 'f';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'public.rls_auto_enable() is missing; restore and verify the reviewed source function first.';
  END IF;

  IF function_owner IS DISTINCT FROM 'postgres'
     OR function_security_definer IS DISTINCT FROM true
     OR function_config IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[] THEN
    RAISE EXCEPTION 'public.rls_auto_enable() owner/security/search_path differs from the reviewed contract.';
  END IF;

  IF source_fingerprint NOT IN (
    '99be20677b456ea8d3be47bdd44fb369',
    'b95d4b52e100f89abf4b5afa270a4776'
  ) THEN
    RAISE EXCEPTION 'public.rls_auto_enable() body is neither the reviewed source nor the reviewed fail-closed candidate; refusing replacement.';
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
    RAISE EXCEPTION 'public.rls_auto_enable() EXECUTE ACL differs from the reviewed postgres/service_role-only contract: %', direct_execute_grantees;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    WHERE p.oid = function_oid
      AND acl.privilege_type = 'EXECUTE'
      AND acl.is_grantable
      AND acl.grantee <> function_owner_oid
  ) THEN
    RAISE EXCEPTION 'public.rls_auto_enable() has a non-owner EXECUTE grant option; review it manually.';
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
     OR event_trigger.evtowner IS DISTINCT FROM function_owner_oid THEN
    RAISE EXCEPTION 'ensure_rls is missing or differs from the reviewed enabled postgres-owned event-trigger contract.';
  END IF;

  IF source_fingerprint = '99be20677b456ea8d3be47bdd44fb369' THEN
    EXECUTE $ddl$
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
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
          RAISE;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;
    $ddl$;
  END IF;

  SELECT
    p.proowner,
    pg_get_userbyid(p.proowner),
    p.prosecdef,
    p.proconfig,
    md5(p.prosrc)
  INTO
    function_owner_oid,
    function_owner,
    function_security_definer,
    function_config,
    source_fingerprint
  FROM pg_proc p
  WHERE p.oid = function_oid;

  IF function_owner IS DISTINCT FROM 'postgres'
     OR function_security_definer IS DISTINCT FROM true
     OR function_config IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
     OR source_fingerprint IS DISTINCT FROM 'b95d4b52e100f89abf4b5afa270a4776' THEN
    RAISE EXCEPTION 'Fail-closed rls_auto_enable() candidate did not reach the exact reviewed owner/security/search_path/body contract.';
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
    RAISE EXCEPTION 'Fail-closed candidate changed the reviewed function EXECUTE ACL: %', direct_execute_grantees;
  END IF;

  SELECT e.evtfoid, e.evtevent, e.evttags, e.evtenabled, e.evtowner
  INTO final_event_trigger
  FROM pg_event_trigger e
  WHERE e.evtname = 'ensure_rls';

  IF NOT FOUND
     OR final_event_trigger.evtfoid IS DISTINCT FROM function_oid
     OR final_event_trigger.evtevent IS DISTINCT FROM 'ddl_command_end'
     OR final_event_trigger.evttags IS DISTINCT FROM ARRAY['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
     OR final_event_trigger.evtenabled IS DISTINCT FROM 'O'
     OR final_event_trigger.evtowner IS DISTINCT FROM function_owner_oid THEN
    RAISE EXCEPTION 'Fail-closed candidate changed the reviewed ensure_rls event-trigger contract.';
  END IF;

  RAISE NOTICE 'Fail-closed rls_auto_enable() candidate installed/verified on the attested isolated target.';
END
$apply_fail_closed_rls$;
