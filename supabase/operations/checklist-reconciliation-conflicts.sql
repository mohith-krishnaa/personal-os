-- Read-only report for legacy/canonical checklist ID collisions.
-- Run only after both checklist tables exist (after Organization migrations).
-- Reconciliation uses ON CONFLICT (id) DO NOTHING: the canonical row wins,
-- while the legacy source row remains intact. Each result is a row not copied
-- into the canonical table and must be reviewed before rollout is accepted.
select
  legacy.id as checklist_id,
  legacy.user_id as legacy_owner_id,
  canonical.user_id as canonical_owner_id,
  legacy.task_id as legacy_task_id,
  canonical.task_id as canonical_task_id,
  (legacy.user_id is distinct from canonical.user_id) as owner_mismatch,
  (legacy.task_id is distinct from canonical.task_id) as task_mismatch,
  (
    legacy.title is distinct from canonical.title
    or legacy.is_completed is distinct from canonical.is_completed
    or legacy.position is distinct from canonical.position
    or legacy.created_at is distinct from canonical.created_at
    or legacy.updated_at is distinct from canonical.updated_at
  ) as payload_mismatch
from public.task_checklist_items as legacy
join public.checklist_items as canonical on canonical.id = legacy.id
where legacy.user_id is distinct from canonical.user_id
   or legacy.task_id is distinct from canonical.task_id
   or legacy.title is distinct from canonical.title
   or legacy.is_completed is distinct from canonical.is_completed
   or legacy.position is distinct from canonical.position
   or legacy.created_at is distinct from canonical.created_at
   or legacy.updated_at is distinct from canonical.updated_at
order by legacy.id;
