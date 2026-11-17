-- Progress V1 compatibility repair.
-- The original core migration creates public.goals before the Progress V1
-- migration. Because Progress V1 used CREATE TABLE IF NOT EXISTS, its unit and
-- target columns were skipped on databases where goals already existed.
-- Keep those columns nullable so legacy non-measurable goals remain readable;
-- the application requires both values when creating a new measurable goal.

ALTER TABLE public.goals
  ADD COLUMN IF NOT EXISTS unit text,
  ADD COLUMN IF NOT EXISTS target numeric;

DO $constraints$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.goals'::regclass
      AND conname = 'goals_unit_nonempty'
  ) THEN
    ALTER TABLE public.goals
      ADD CONSTRAINT goals_unit_nonempty
      CHECK (unit IS NULL OR length(trim(unit)) > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.goals'::regclass
      AND conname = 'goals_target_positive'
  ) THEN
    ALTER TABLE public.goals
      ADD CONSTRAINT goals_target_positive
      CHECK (target IS NULL OR target > 0);
  END IF;
END
$constraints$;

COMMENT ON COLUMN public.goals.unit IS
  'Measurement unit; NULL is retained for legacy goals not configured for progress tracking.';
COMMENT ON COLUMN public.goals.target IS
  'Positive progress target; NULL is retained for legacy goals not configured for progress tracking.';
