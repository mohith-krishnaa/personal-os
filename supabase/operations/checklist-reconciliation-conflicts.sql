-- Read-only report for legacy checklist rows that reconciliation does not fully resolve.
-- Run only after both checklist tables exist (after Organization migrations).
-- Reconciliation is a one-time copy: it accepts only same-owner task links,
-- while ON CONFLICT (id) DO NOTHING preserves an existing canonical row.
-- This report also detects legacy writes made after that one-time copy.
select
  legacy.id as checklist_id,
  case
    when task.id is null then 'missing_task'
    when task.user_id is distinct from legacy.user_id then 'task_owner_mismatch'
    when canonical.id is null then 'missing_canonical'
    else 'canonical_id_collision'
  end as conflict_type,
  legacy.user_id as legacy_owner_id,
  task.user_id as task_owner_id,
  canonical.user_id as canonical_owner_id,
  legacy.task_id as legacy_task_id,
  canonical.task_id as canonical_task_id,
  (task.id is null) as task_missing,
  (task.id is not null and task.user_id is distinct from legacy.user_id) as task_owner_mismatch,
  (canonical.id is null) as canonical_missing,
  (canonical.id is not null and legacy.user_id is distinct from canonical.user_id) as owner_mismatch,
  (canonical.id is not null and legacy.task_id is distinct from canonical.task_id) as task_mismatch,
  (
    canonical.id is not null and (
      legacy.title is distinct from canonical.title
      or legacy.is_completed is distinct from canonical.is_completed
      or legacy.position is distinct from canonical.position
      or legacy.created_at is distinct from canonical.created_at
      or legacy.updated_at is distinct from canonical.updated_at
    )
  ) as payload_mismatch
from public.task_checklist_items as legacy
left join public.tasks as task on task.id = legacy.task_id
left join public.checklist_items as canonical on canonical.id = legacy.id
where task.id is null
   or task.user_id is distinct from legacy.user_id
   or canonical.id is null
   or (
     canonical.id is not null and (
       legacy.user_id is distinct from canonical.user_id
       or legacy.task_id is distinct from canonical.task_id
       or legacy.title is distinct from canonical.title
       or legacy.is_completed is distinct from canonical.is_completed
       or legacy.position is distinct from canonical.position
       or legacy.created_at is distinct from canonical.created_at
       or legacy.updated_at is distinct from canonical.updated_at
     )
   )
order by legacy.id;
