-- Preserve existing task/project links when a project is completed or archived,
-- but reject new task links to any project that is not ACTIVE.
--
-- The row lock serializes task-link creation/reassignment with concurrent project
-- status changes. The existing validate_task_organization_links trigger remains
-- authoritative for owner, parent/project consistency, and hierarchy-cycle checks.

DO $preflight$
BEGIN
  IF to_regclass('public.projects') IS NULL OR to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'Project archive lifecycle requires public.projects and public.tasks.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'projects'
      AND column_name IN ('id', 'user_id', 'status')
    GROUP BY table_name
    HAVING count(*) = 3
  ) OR NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'tasks'
      AND column_name IN ('user_id', 'project_id')
    GROUP BY table_name
    HAVING count(*) = 2
  ) THEN
    RAISE EXCEPTION 'Project archive lifecycle is missing required project/task columns.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.tasks'::regclass
      AND tgname = 'validate_task_organization_links'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'The Organization task-link validation trigger is missing; refusing to install the archive lifecycle guard.';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.require_active_project_for_new_task_links()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  project_status text;
BEGIN
  IF NEW.project_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- An unchanged link is historical state, not a new assignment. This allows
  -- existing tasks in completed/archived projects to keep working.
  IF TG_OP = 'UPDATE'
     AND NEW.project_id IS NOT DISTINCT FROM OLD.project_id
     AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id THEN
    RETURN NEW;
  END IF;

  -- FOR SHARE prevents a concurrent project archive/completion from racing
  -- past this check. If the project row is not visible to this caller, the
  -- existing owner-validation trigger below remains responsible for rejection.
  SELECT p.status
  INTO project_status
  FROM public.projects AS p
  WHERE p.id = NEW.project_id
    AND p.user_id = NEW.user_id
  FOR SHARE;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF project_status IS DISTINCT FROM 'ACTIVE' THEN
    RAISE EXCEPTION 'Tasks can only be linked to active projects.'
      USING errcode = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS require_active_project_for_new_task_links ON public.tasks;

CREATE TRIGGER require_active_project_for_new_task_links
BEFORE INSERT OR UPDATE OF user_id, project_id ON public.tasks
FOR EACH ROW
EXECUTE FUNCTION public.require_active_project_for_new_task_links();

COMMENT ON FUNCTION public.require_active_project_for_new_task_links()
IS 'Rejects new task/project links unless the project is ACTIVE while preserving existing links after completion or archive.';
