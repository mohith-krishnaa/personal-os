-- Make activity_events append-only for application roles.
-- The table owner retains controlled maintenance/retention privileges.
DO $append_only_preflight$
DECLARE
  v_unexpected_policies text;
BEGIN
  IF to_regclass('public.activity_events') IS NULL THEN
    RAISE EXCEPTION 'Append-only activity-event migration requires public.activity_events.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    WHERE c.oid = 'public.activity_events'::regclass
      AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'Append-only activity-event migration requires RLS to remain enabled.';
  END IF;

  SELECT string_agg(policyname, ', ' ORDER BY policyname)
    INTO v_unexpected_policies
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'activity_events'
    AND policyname NOT IN (
      'activity_events_owner',
      'activity_events_select_owner',
      'activity_events_insert_owner'
    );

  IF v_unexpected_policies IS NOT NULL THEN
    RAISE EXCEPTION
      'Unexpected activity_events RLS policies require review before append-only enforcement: %',
      v_unexpected_policies;
  END IF;
END;
$append_only_preflight$;

DROP POLICY IF EXISTS activity_events_owner ON public.activity_events;
DROP POLICY IF EXISTS activity_events_select_owner ON public.activity_events;
DROP POLICY IF EXISTS activity_events_insert_owner ON public.activity_events;

CREATE POLICY activity_events_select_owner
ON public.activity_events
FOR SELECT
TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY activity_events_insert_owner
ON public.activity_events
FOR INSERT
TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

REVOKE ALL PRIVILEGES
ON TABLE public.activity_events
FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT
ON TABLE public.activity_events
TO authenticated, service_role;
