ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS recurrence_rule jsonb,
  ADD COLUMN IF NOT EXISTS recurrence_until timestamptz,
  ADD COLUMN IF NOT EXISTS recurrence_parent_id uuid;

ALTER TABLE public.tasks
  DROP CONSTRAINT IF EXISTS tasks_recurrence_rule_valid;

ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_recurrence_rule_valid
  CHECK (
    recurrence_rule IS NULL
    OR (
      jsonb_typeof(recurrence_rule) = 'object'
      AND recurrence_rule ? 'frequency'
      AND recurrence_rule ? 'interval'
      AND (recurrence_rule->>'frequency') IN ('DAILY', 'WEEKLY', 'MONTHLY')
      AND ((recurrence_rule->>'interval') ~ '^[1-9][0-9]*$')
    )
  );

ALTER TABLE public.tasks
  DROP CONSTRAINT IF EXISTS tasks_recurrence_until_after_schedule;

ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_recurrence_until_after_schedule
  CHECK (recurrence_until IS NULL OR due_at IS NULL OR recurrence_until >= due_at);

CREATE INDEX IF NOT EXISTS tasks_recurrence_parent_id_idx
  ON public.tasks (recurrence_parent_id)
  WHERE recurrence_parent_id IS NOT NULL;

ALTER TABLE public.tasks
  DROP CONSTRAINT IF EXISTS tasks_recurrence_parent_id_fkey;

ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_recurrence_parent_id_fkey
  FOREIGN KEY (recurrence_parent_id) REFERENCES public.tasks(id) ON DELETE SET NULL;
