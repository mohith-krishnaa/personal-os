-- Verify the forward compatibility repair for legacy goals.
-- This runs only in the disposable migration-replay database.
BEGIN;

DO $goal_metric_compatibility$
DECLARE
  test_user_id constant uuid := '11111111-1111-4111-8111-111111111111';
  test_goal_id constant uuid := 'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f001';
  unit_type text;
  unit_nullable text;
  target_type text;
  target_nullable text;
  metric_constraint_count integer;
  unvalidated_constraint_count integer;
BEGIN
  SELECT data_type, is_nullable
    INTO unit_type, unit_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'goals'
    AND column_name = 'unit';

  SELECT data_type, is_nullable
    INTO target_type, target_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'goals'
    AND column_name = 'target';

  IF unit_type IS DISTINCT FROM 'text'
     OR unit_nullable IS DISTINCT FROM 'YES'
     OR target_type IS DISTINCT FROM 'numeric'
     OR target_nullable IS DISTINCT FROM 'YES' THEN
    RAISE EXCEPTION
      'Progress goal metrics must be nullable text/numeric columns; got unit %/% and target %/%.',
      unit_type, unit_nullable, target_type, target_nullable;
  END IF;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE NOT convalidated)::integer
    INTO metric_constraint_count, unvalidated_constraint_count
  FROM pg_constraint
  WHERE conrelid = 'public.goals'::regclass
    AND contype = 'c'
    AND conname IN ('goals_unit_nonempty', 'goals_target_positive');

  IF metric_constraint_count <> 2 OR unvalidated_constraint_count <> 0 THEN
    RAISE EXCEPTION
      'Expected both validated Progress metric checks; found % constraints, % unvalidated.',
      metric_constraint_count, unvalidated_constraint_count;
  END IF;

  -- Legacy goals without measurement metadata must remain valid.
  INSERT INTO public.goals (id, user_id, title, unit, target)
  VALUES (test_goal_id, test_user_id, 'Legacy non-measurable goal', NULL, NULL);
  DELETE FROM public.goals WHERE id = test_goal_id;

  -- A measurable goal with a non-empty unit and positive target remains valid.
  INSERT INTO public.goals (id, user_id, title, unit, target)
  VALUES (test_goal_id, test_user_id, 'Valid measurable goal', 'pages', 10);
  DELETE FROM public.goals WHERE id = test_goal_id;

  BEGIN
    INSERT INTO public.goals (id, user_id, title, unit, target)
    VALUES (test_goal_id, test_user_id, 'Blank unit must fail', '   ', 10);
    RAISE EXCEPTION 'The goals_unit_nonempty constraint accepted a whitespace-only unit.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.goals (id, user_id, title, unit, target)
    VALUES (test_goal_id, test_user_id, 'Zero target must fail', 'pages', 0);
    RAISE EXCEPTION 'The goals_target_positive constraint accepted a zero target.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.goals (id, user_id, title, unit, target)
    VALUES (test_goal_id, test_user_id, 'Negative target must fail', 'pages', -1);
    RAISE EXCEPTION 'The goals_target_positive constraint accepted a negative target.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END
$goal_metric_compatibility$;

ROLLBACK;
