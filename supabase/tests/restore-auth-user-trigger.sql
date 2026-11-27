DO $assert_auth_trigger_restore$
DECLARE
  trigger_definition text;
  function_owner text;
  function_security_definer boolean;
  function_settings text[];
  trigger_enabled "char";
BEGIN
  SELECT pg_get_triggerdef(t.oid), pg_get_userbyid(p.proowner),
         p.prosecdef, p.proconfig, t.tgenabled
  INTO trigger_definition, function_owner, function_security_definer,
       function_settings, trigger_enabled
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid=t.tgfoid
  WHERE t.tgrelid='auth.users'::regclass
    AND t.tgname='on_auth_user_created'
    AND NOT t.tgisinternal;

  IF trigger_definition IS NULL
     OR trigger_definition NOT ILIKE '%AFTER INSERT ON auth.users%'
     OR trigger_definition NOT ILIKE '%EXECUTE FUNCTION handle_new_user()%' THEN
    RAISE EXCEPTION 'on_auth_user_created does not match the expected AFTER INSERT trigger definition.';
  END IF;

  IF trigger_enabled IS DISTINCT FROM 'O' THEN
    RAISE EXCEPTION 'on_auth_user_created must be enabled.';
  END IF;

  IF function_owner IS DISTINCT FROM 'postgres'
     OR function_security_definer IS DISTINCT FROM false
     OR NOT COALESCE(function_settings @> ARRAY['search_path=public']::text[], false) THEN
    RAISE EXCEPTION 'handle_new_user must remain postgres-owned SECURITY INVOKER with search_path=public.';
  END IF;
END
$assert_auth_trigger_restore$;
