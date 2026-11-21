-- Apply ONLY to a freshly restored isolated Supabase target.
-- public.rls_auto_enable() must already exist from the public schema dump.
-- This script never creates or replaces the function body.
-- Run from a provider-supported superuser-capable session, verify the target project
-- reference in the Dashboard, then set in this same session:
--   SET app.personal_os_restore_target = 'isolated';
-- A newly created event trigger is transferred to owner postgres after creation.
DO $restore_ensure_rls$
DECLARE
  function_oid oid;
  function_owner_oid oid;
  function_owner text;
  function_security_definer boolean;
  function_config text[];
  function_source text;
  unexpected_execute_grantees text[];
  actual_execute_grantees text[];
  existing_event_trigger record;
  final_event_trigger record;
  event_trigger_missing boolean;
BEGIN
  IF current_setting('app.personal_os_restore_target', true) IS DISTINCT FROM 'isolated' THEN
    RAISE EXCEPTION 'Refusing ensure_rls restoration: verify the target project reference and set app.personal_os_restore_target=isolated only on the isolated target.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = current_user
      AND rolsuper
  ) THEN
    RAISE EXCEPTION 'Refusing ensure_rls restoration: execute from a superuser-capable session on the isolated target.';
  END IF;

  SELECT
    p.oid,
    p.proowner,
    pg_get_userbyid(p.proowner),
    p.prosecdef,
    p.proconfig,
    p.prosrc
  INTO
    function_oid,
    function_owner_oid,
    function_owner,
    function_security_definer,
    function_config,
    function_source
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'rls_auto_enable'
    AND p.pronargs = 0
    AND p.prorettype = 'event_trigger'::regtype
    AND p.prokind = 'f';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Restore public.rls_auto_enable() from schema.sql before restoring ensure_rls; this script does not create or replace the function.';
  END IF;

  IF function_owner IS DISTINCT FROM 'postgres'
     OR function_security_definer IS DISTINCT FROM true
     OR function_config IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[] THEN
    RAISE EXCEPTION 'public.rls_auto_enable() does not match the expected postgres-owned SECURITY DEFINER/search_path=pg_catalog contract.';
  END IF;

  IF md5(function_source) IS DISTINCT FROM '99be20677b456ea8d3be47bdd44fb369' THEN
    RAISE EXCEPTION 'public.rls_auto_enable() source fingerprint differs from the reviewed source body; stop and review the restored dump before creating ensure_rls.';
  END IF;

  SELECT ARRAY(
    SELECT DISTINCT
      CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(acl.grantee) END
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    WHERE p.oid = function_oid
      AND acl.privilege_type = 'EXECUTE'
      AND CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(acl.grantee) END
          NOT IN ('postgres', 'service_role', 'anon', 'authenticated', 'PUBLIC')
    ORDER BY 1
  )
  INTO unexpected_execute_grantees;

  IF cardinality(coalesce(unexpected_execute_grantees, ARRAY[]::text[])) > 0 THEN
    RAISE EXCEPTION 'public.rls_auto_enable() has unexpected direct EXECUTE grantees: %', unexpected_execute_grantees;
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
    RAISE EXCEPTION 'public.rls_auto_enable() has a non-owner EXECUTE grant option; review it instead of normalizing it automatically.';
  END IF;

  SELECT e.evtfoid, e.evtevent, e.evttags, e.evtenabled, e.evtowner
  INTO existing_event_trigger
  FROM pg_event_trigger e
  WHERE e.evtname = 'ensure_rls';

  event_trigger_missing := NOT FOUND;

  IF NOT event_trigger_missing AND (
    existing_event_trigger.evtfoid IS DISTINCT FROM function_oid
    OR existing_event_trigger.evtevent IS DISTINCT FROM 'ddl_command_end'
    OR existing_event_trigger.evttags IS DISTINCT FROM ARRAY['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
    OR existing_event_trigger.evtenabled IS DISTINCT FROM 'O'
    OR existing_event_trigger.evtowner IS DISTINCT FROM function_owner_oid
  ) THEN
    RAISE EXCEPTION 'An existing ensure_rls event trigger conflicts with the reviewed source contract; inspect it manually instead of replacing it.';
  END IF;

  EXECUTE 'REVOKE ALL PRIVILEGES ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.rls_auto_enable() TO service_role';

  SELECT ARRAY(
    SELECT DISTINCT
      CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(acl.grantee) END
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    WHERE p.oid = function_oid
      AND acl.privilege_type = 'EXECUTE'
    ORDER BY 1
  )
  INTO actual_execute_grantees;

  IF actual_execute_grantees IS DISTINCT FROM ARRAY['postgres', 'service_role']::text[]
     OR has_function_privilege('anon', function_oid, 'EXECUTE')
     OR has_function_privilege('authenticated', function_oid, 'EXECUTE')
     OR NOT has_function_privilege('service_role', function_oid, 'EXECUTE')
     OR NOT has_function_privilege('postgres', function_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'public.rls_auto_enable() did not reach the exact postgres/service_role-only EXECUTE contract; direct grantees: %', actual_execute_grantees;
  END IF;

  IF event_trigger_missing THEN
    EXECUTE $ddl$
      CREATE EVENT TRIGGER ensure_rls
      ON ddl_command_end
      WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      EXECUTE FUNCTION public.rls_auto_enable()
    $ddl$;
    EXECUTE 'ALTER EVENT TRIGGER ensure_rls OWNER TO postgres';
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
    RAISE EXCEPTION 'ensure_rls was not restored with the exact enabled ddl_command_end/tag/function/owner contract.';
  END IF;

  RAISE NOTICE 'ensure_rls restored/verified: postgres-owned event trigger; public.rls_auto_enable() EXECUTE is limited to postgres and service_role.';
END
$restore_ensure_rls$;
