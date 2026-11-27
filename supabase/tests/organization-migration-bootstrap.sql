DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'CREATE ROLE anon NOLOGIN';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'CREATE ROLE authenticated NOLOGIN';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    EXECUTE 'CREATE ROLE service_role NOLOGIN BYPASSRLS';
  END IF;
  -- Test-only superuser identity used as a negative control: the restore script must
  -- require the Supabase postgres role, not accept an arbitrary SUPERUSER role.
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    EXECUTE 'CREATE ROLE supabase_admin NOLOGIN SUPERUSER';
  END IF;
END
$roles$;

ALTER ROLE anon NOBYPASSRLS;
ALTER ROLE authenticated NOBYPASSRLS;
ALTER ROLE service_role BYPASSRLS;

CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $function$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$function$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;

-- The source project has a project-installed event-trigger function outside the migration chain.
-- This source-shaped fixture matches the reviewed production body so the isolated restore
-- script and behavior test exercise the same event-trigger contract.
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
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rls_auto_enable() TO anon, authenticated, service_role;

-- The read-only rollout preflight inspects the Supabase migration ledger.
-- Provide its minimal shape in the disposable fixture so CI can execute the
-- exact production preflight SQL after replay without connecting to production.
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (
  version text PRIMARY KEY,
  name text NOT NULL
);
