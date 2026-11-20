BEGIN;

-- Authenticated clients may mutate tasks, but must not fabricate activity history
-- by inserting arbitrary event_type/entity_id/metadata rows directly.
DO $preflight$
DECLARE
  v_unexpected_policies text;
  v_claim_function oid;
  v_claim_owner text;
  v_claim_config text[];
  v_claim_is_definer boolean;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Trusted activity-event writer migration must run as postgres.';
  END IF;

  IF to_regclass('public.activity_events') IS NULL
     OR to_regclass('public.tasks') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_class
       WHERE oid = 'public.activity_events'::regclass
         AND relrowsecurity
     ) THEN
    RAISE EXCEPTION 'Trusted activity-event writer migration requires RLS-enabled activity_events and tasks.';
  END IF;

  SELECT string_agg(policyname, ', ' ORDER BY policyname)
    INTO v_unexpected_policies
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'activity_events'
    AND policyname NOT IN (
      'activity_events_select_owner',
      'activity_events_insert_owner'
    );

  IF v_unexpected_policies IS NOT NULL THEN
    RAISE EXCEPTION
      'Unexpected activity_events RLS policies require review before trusted-writer enforcement: %',
      v_unexpected_policies;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'activity_events'
      AND policyname = 'activity_events_select_owner'
      AND cmd = 'SELECT'
      AND roles @> ARRAY['authenticated']::name[]
      AND qual ILIKE '%auth.uid%'
  ) THEN
    RAISE EXCEPTION 'The authenticated owner-scoped activity-event SELECT policy is required.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'activity_events'
      AND policyname = 'activity_events_insert_owner'
      AND (
        cmd <> 'INSERT'
        OR NOT (roles @> ARRAY['authenticated']::name[])
        OR with_check NOT ILIKE '%auth.uid%'
      )
  ) THEN
    RAISE EXCEPTION 'The existing activity-event INSERT policy has an unexpected definition.';
  END IF;

  v_claim_function := to_regprocedure('public.claim_due_reminders(integer)');
  IF v_claim_function IS NULL THEN
    RAISE EXCEPTION 'The trusted reminder activity-event writer is missing.';
  END IF;

  SELECT p.prosecdef, pg_get_userbyid(p.proowner), p.proconfig
    INTO v_claim_is_definer, v_claim_owner, v_claim_config
  FROM pg_proc p
  WHERE p.oid = v_claim_function;

  IF NOT coalesce(v_claim_is_definer, false)
     OR v_claim_owner <> 'postgres'
     OR NOT coalesce(v_claim_config, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public']::text[]
     OR NOT has_function_privilege('service_role', v_claim_function, 'EXECUTE')
     OR has_function_privilege('authenticated', v_claim_function, 'EXECUTE')
     OR has_function_privilege('anon', v_claim_function, 'EXECUTE') THEN
    RAISE EXCEPTION 'claim_due_reminders must remain a postgres-owned, fixed-search-path SECURITY DEFINER writer executable only by service_role.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.tasks'::regclass
      AND t.tgname = 'tasks_record_activity_event'
      AND NOT t.tgisinternal
      AND t.tgenabled = 'O'
      AND p.proname = 'record_task_activity_event'
  ) THEN
    RAISE EXCEPTION 'The enabled task activity-event trigger is required before writer hardening.';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.record_task_activity_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_event_type text;
  v_metadata jsonb;
  v_source_task_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Do not block account deletion: tasks.user_id and activity_events.user_id
    -- both cascade from auth.users. Admin/service-role cleanup has no owner subject.
    IF auth.uid() IS DISTINCT FROM OLD.user_id THEN
      RETURN OLD;
    END IF;

    v_event_type := 'TASK_DELETED';
    v_metadata := jsonb_build_object(
      'source', 'database',
      'title', OLD.title,
      'status', OLD.status,
      'project_id', OLD.project_id,
      'parent_task_id', OLD.parent_task_id,
      'recurrence_parent_id', OLD.recurrence_parent_id
    );

    INSERT INTO public.activity_events (user_id, event_type, entity_type, entity_id, metadata)
    VALUES (OLD.user_id, v_event_type, 'TASK', OLD.id, coalesce(v_metadata, '{}'::jsonb));

    RETURN OLD;
  ELSIF TG_OP = 'INSERT' THEN
    -- SECURITY DEFINER bypasses activity_events RLS so the trigger can write
    -- without granting authenticated clients direct INSERT. Keep the owner
    -- boundary explicit even though tasks RLS also enforces it.
    IF auth.uid() IS NOT NULL AND auth.uid() IS DISTINCT FROM NEW.user_id THEN
      RAISE EXCEPTION 'Task activity event owner does not match the authenticated user.'
        USING ERRCODE = '42501';
    END IF;

    IF NEW.recurrence_parent_id IS NOT NULL THEN
      v_event_type := 'TASK_RECURRENCE_GENERATED';
      SELECT candidate.id INTO v_source_task_id
      FROM public.tasks candidate
      WHERE candidate.user_id = NEW.user_id
        AND candidate.id <> NEW.id
        AND (candidate.id = NEW.recurrence_parent_id OR candidate.recurrence_parent_id = NEW.recurrence_parent_id)
        AND candidate.due_at IS NOT NULL
        AND NEW.due_at IS NOT NULL
        AND candidate.due_at < NEW.due_at
      ORDER BY candidate.due_at DESC, candidate.created_at DESC, candidate.id
      LIMIT 1;
      v_metadata := jsonb_build_object('source_task_id', coalesce(v_source_task_id, NEW.recurrence_parent_id));
    ELSE
      v_event_type := 'TASK_CREATED';
      v_metadata := jsonb_build_object('source', 'database', 'recurring', NEW.recurrence_rule IS NOT NULL);
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF auth.uid() IS NOT NULL AND auth.uid() IS DISTINCT FROM NEW.user_id THEN
      RAISE EXCEPTION 'Task activity event owner does not match the authenticated user.'
        USING ERRCODE = '42501';
    END IF;

    IF ROW(
      NEW.id, NEW.user_id, NEW.title, NEW.description, NEW.status, NEW.priority,
      NEW.due_at, NEW.scheduled_start, NEW.scheduled_end, NEW.estimated_minutes,
      NEW.actual_minutes, NEW.completed_at, NEW.project_id, NEW.parent_task_id,
      NEW.recurrence_rule, NEW.recurrence_until, NEW.recurrence_parent_id
    ) IS NOT DISTINCT FROM ROW(
      OLD.id, OLD.user_id, OLD.title, OLD.description, OLD.status, OLD.priority,
      OLD.due_at, OLD.scheduled_start, OLD.scheduled_end, OLD.estimated_minutes,
      OLD.actual_minutes, OLD.completed_at, OLD.project_id, OLD.parent_task_id,
      OLD.recurrence_rule, OLD.recurrence_until, OLD.recurrence_parent_id
    ) THEN
      RETURN NEW;
    END IF;

    -- createTask initializes a recurring root with recurrence_parent_id = id.
    -- This internal link does not represent a second user-visible mutation.
    IF OLD.recurrence_parent_id IS NULL
       AND NEW.recurrence_parent_id = NEW.id
       AND ROW(
         NEW.id, NEW.user_id, NEW.title, NEW.description, NEW.status, NEW.priority,
         NEW.due_at, NEW.scheduled_start, NEW.scheduled_end, NEW.estimated_minutes,
         NEW.actual_minutes, NEW.completed_at, NEW.project_id, NEW.parent_task_id,
         NEW.recurrence_rule, NEW.recurrence_until
       ) IS NOT DISTINCT FROM ROW(
         OLD.id, OLD.user_id, OLD.title, OLD.description, OLD.status, OLD.priority,
         OLD.due_at, OLD.scheduled_start, OLD.scheduled_end, OLD.estimated_minutes,
         OLD.actual_minutes, OLD.completed_at, OLD.project_id, OLD.parent_task_id,
         OLD.recurrence_rule, OLD.recurrence_until
       ) THEN
      RETURN NEW;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF NEW.status = 'COMPLETED' THEN
        v_event_type := 'TASK_COMPLETED';
      ELSE
        v_event_type := 'TASK_STATUS_CHANGED';
      END IF;
      v_metadata := jsonb_build_object('status', NEW.status);
    ELSE
      v_event_type := 'TASK_UPDATED';
      v_metadata := jsonb_build_object('source', 'database');
    END IF;
  ELSE
    RETURN NEW;
  END IF;

  INSERT INTO public.activity_events (user_id, event_type, entity_type, entity_id, metadata)
  VALUES (NEW.user_id, v_event_type, 'TASK', NEW.id, coalesce(v_metadata, '{}'::jsonb));

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.record_task_activity_event() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_task_activity_event() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_task_activity_event() TO service_role;

DROP POLICY IF EXISTS activity_events_insert_owner ON public.activity_events;
REVOKE INSERT ON TABLE public.activity_events FROM PUBLIC, anon, authenticated;

DO $assert_contract$
DECLARE
  v_function oid := to_regprocedure('public.record_task_activity_event()');
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = v_function
      AND p.prosecdef
      AND pg_get_userbyid(p.proowner) = 'postgres'
      AND coalesce(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public']::text[]
  ) THEN
    RAISE EXCEPTION 'Task activity trigger must be postgres-owned SECURITY DEFINER with a fixed search_path.';
  END IF;

  IF has_function_privilege('anon', v_function, 'EXECUTE')
     OR has_function_privilege('authenticated', v_function, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
    RAISE EXCEPTION 'Task activity trigger EXECUTE grants are incorrect.';
  END IF;

  IF has_table_privilege('authenticated', 'public.activity_events', 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.activity_events', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.activity_events', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.activity_events', 'SELECT')
     OR has_table_privilege('anon', 'public.activity_events', 'INSERT')
     OR EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'activity_events'
         AND policyname = 'activity_events_insert_owner'
     ) THEN
    RAISE EXCEPTION 'Only the trusted task trigger and service_role may insert activity events; authenticated clients must be SELECT-only.';
  END IF;
END;
$assert_contract$;

COMMIT;
