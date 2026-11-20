-- Add transactional TASK_DELETED events for authenticated owner deletes.
-- Cascaded task descendants are covered by the same row trigger.
-- Service-role/admin cleanup (including auth.users ON DELETE CASCADE) has no
-- authenticated owner context and intentionally emits no per-user delete event.

CREATE OR REPLACE FUNCTION public.record_task_activity_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_event_type text;
  v_metadata jsonb;
  v_source_task_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Do not block account deletion: tasks.user_id and activity_events.user_id
    -- both cascade from auth.users. An admin/service-role cleanup has no
    -- authenticated owner subject and its activity rows are removed by FK too.
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

REVOKE ALL ON FUNCTION public.record_task_activity_event() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_task_activity_event() TO authenticated, service_role;

DROP TRIGGER IF EXISTS tasks_record_activity_event ON public.tasks;
CREATE TRIGGER tasks_record_activity_event
AFTER INSERT OR UPDATE OR DELETE ON public.tasks
FOR EACH ROW
EXECUTE FUNCTION public.record_task_activity_event();
