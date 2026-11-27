-- Make notification creation, activity logging, and reminder completion one transaction.
-- A failure at any stage must leave the reminder eligible for retry.
DO $preflight$
DECLARE
  reminder_id_attnum smallint;
BEGIN
  IF to_regclass('public.reminders') IS NULL
     OR to_regclass('public.notifications') IS NULL
     OR to_regclass('public.activity_events') IS NULL THEN
    RAISE EXCEPTION 'Atomic reminder delivery requires reminders, notifications, and activity_events.';
  END IF;

  SELECT attnum INTO reminder_id_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.notifications'::regclass
    AND attname = 'reminder_id'
    AND NOT attisdropped;

  IF reminder_id_attnum IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_index i
       WHERE i.indexrelid = to_regclass('public.notifications_reminder_unique')
         AND i.indrelid = 'public.notifications'::regclass
         AND i.indisunique
         AND i.indisvalid
         AND i.indisready
         AND i.indpred IS NULL
         AND i.indexprs IS NULL
         AND i.indnkeyatts = 1
         AND i.indnatts = 1
         AND i.indkey[0] = reminder_id_attnum
     ) THEN
    RAISE EXCEPTION 'Atomic reminder delivery requires the exact unique notifications(reminder_id) index.';
  END IF;

  IF to_regprocedure('public.claim_due_reminders(integer)') IS NULL THEN
    RAISE EXCEPTION 'The existing claim_due_reminders(integer) function is missing.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    RAISE EXCEPTION 'The service_role required by reminder delivery is missing.';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.claim_due_reminders(p_limit integer DEFAULT 100)
RETURNS TABLE(id uuid, user_id uuid, task_id uuid, remind_at timestamptz, channel text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  r record;
  notification_id uuid;
BEGIN
  FOR r IN
    SELECT rm.id, rm.user_id, rm.task_id, rm.remind_at, rm.channel
    FROM public.reminders AS rm
    WHERE rm.enabled = true
      AND rm.delivered_at IS NULL
      AND rm.remind_at <= now()
    ORDER BY rm.remind_at ASC
    LIMIT greatest(1, least(coalesce(p_limit, 100), 500))
    FOR UPDATE OF rm SKIP LOCKED
  LOOP
    notification_id := NULL;

    INSERT INTO public.notifications AS existing_notification (
      user_id, reminder_id, task_id, title, body
    )
    VALUES (
      r.user_id,
      r.id,
      r.task_id,
      'Reminder',
      'Task reminder scheduled for ' ||
        to_char(
          date_trunc('milliseconds', r.remind_at) AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
        )
    )
    ON CONFLICT (reminder_id) DO UPDATE
      SET reminder_id = EXCLUDED.reminder_id
      WHERE existing_notification.user_id = EXCLUDED.user_id
        AND existing_notification.task_id = EXCLUDED.task_id
    RETURNING existing_notification.id INTO notification_id;

    IF notification_id IS NULL THEN
      RAISE EXCEPTION 'Existing notification for reminder % has a different owner or task.', r.id
        USING ERRCODE = '23514';
    END IF;

    INSERT INTO public.activity_events (
      user_id, event_type, entity_type, entity_id, metadata
    )
    VALUES (
      r.user_id,
      'REMINDER_DELIVERED',
      'REMINDER',
      r.id,
      jsonb_build_object('task_id', r.task_id, 'channel', r.channel)
    );

    UPDATE public.reminders AS rm
    SET delivered_at = now(),
        updated_at = now()
    WHERE rm.id = r.id
      AND rm.enabled = true
      AND rm.delivered_at IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Reminder % changed before delivery completed.', r.id
        USING ERRCODE = '40001';
    END IF;

    id := r.id;
    user_id := r.user_id;
    task_id := r.task_id;
    remind_at := r.remind_at;
    channel := r.channel;
    RETURN NEXT;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.claim_due_reminders(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_due_reminders(integer) TO service_role;

DO $assert_contract$
DECLARE
  function_config text[];
BEGIN
  SELECT p.proconfig INTO function_config
  FROM pg_proc p
  WHERE p.oid = 'public.claim_due_reminders(integer)'::regprocedure;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = 'public.claim_due_reminders(integer)'::regprocedure
      AND p.prosecdef
  ) OR NOT coalesce(function_config, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public']::text[] THEN
    RAISE EXCEPTION 'claim_due_reminders must remain SECURITY DEFINER with search_path pg_catalog, public.';
  END IF;

  IF NOT has_function_privilege('service_role', 'public.claim_due_reminders(integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.claim_due_reminders(integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.claim_due_reminders(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'claim_due_reminders must be executable only by service_role.';
  END IF;
END
$assert_contract$;
