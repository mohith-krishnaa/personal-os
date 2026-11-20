-- Read-only report for legacy checklist rows that reconciliation does not fully resolve.
-- Run only after both checklist tables exist (after Organization migrations).
-- This file contains SELECT only: it never copies, repairs, deletes, or reassigns rows.
-- Reconciliation is a one-time copy: it accepts only same-owner task links,
-- while ON CONFLICT (id) DO NOTHING preserves an existing canonical row.
-- This report also detects legacy writes made after that one-time copy.
--
-- canonical_id_collision is an umbrella classification. Use the owner/task/payload
-- flags and side-by-side values below to distinguish the exact collision shape.
-- Classification priority is missing_task, task_owner_mismatch, missing_canonical,
-- then canonical_id_collision.

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
  ) as payload_mismatch,
  legacy.title as legacy_title,
  canonical.title as canonical_title,
  legacy.is_completed as legacy_is_completed,
  canonical.is_completed as canonical_is_completed,
  legacy.position as legacy_position,
  canonical.position as canonical_position,
  legacy.created_at as legacy_created_at,
  canonical.created_at as canonical_created_at,
  legacy.updated_at as legacy_updated_at,
  canonical.updated_at as canonical_updated_at,
  (canonical.id is not null and legacy.title is distinct from canonical.title) as title_mismatch,
  (canonical.id is not null and legacy.is_completed is distinct from canonical.is_completed) as is_completed_mismatch,
  (canonical.id is not null and legacy.position is distinct from canonical.position) as position_mismatch,
  (canonical.id is not null and legacy.created_at is distinct from canonical.created_at) as created_at_mismatch,
  (canonical.id is not null and legacy.updated_at is distinct from canonical.updated_at) as updated_at_mismatch
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
