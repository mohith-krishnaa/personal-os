-- Reconcile the legacy checklist table into the canonical table used by the app.
-- Keep the legacy table intact to avoid destructive changes to existing installations.
-- Only copy rows whose task and checklist item have the same owner.
insert into public.checklist_items (
  id, user_id, task_id, title, is_completed, position, created_at, updated_at
)
select
  legacy.id,
  legacy.user_id,
  legacy.task_id,
  legacy.title,
  legacy.is_completed,
  legacy.position,
  legacy.created_at,
  legacy.updated_at
from public.task_checklist_items as legacy
join public.tasks as task
  on task.id = legacy.task_id
 and task.user_id = legacy.user_id
on conflict (id) do nothing;
