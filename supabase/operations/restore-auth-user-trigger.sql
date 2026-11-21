-- Apply ONLY to a freshly restored isolated Supabase target.
-- Standard Supabase CLI dumps exclude the auth schema, so this trigger is restored separately.
-- public.handle_new_user() must already exist from the public schema dump.
DO $preflight_auth_trigger_restore$
DECLARE
  function_oid oid;
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'Restore auth.users from the Supabase-managed target before restoring the custom trigger.';
  END IF;
  IF to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'Restore public.profiles before restoring the Auth profile trigger.';
  END IF;

  function_oid := to_regprocedure('public.handle_new_user()');
  IF function_oid IS NULL THEN
    RAISE EXCEPTION 'public.handle_new_user() must exist before restoring on_auth_user_created.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = function_oid
      AND pg_get_userbyid(p.proowner) = 'postgres'
      AND NOT p.prosecdef
      AND COALESCE(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public']::text[]
  ) THEN
    RAISE EXCEPTION 'public.handle_new_user() does not match the expected postgres-owned SECURITY INVOKER/search_path contract.';
  END IF;
END
$preflight_auth_trigger_restore$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();
