-- Task-create request idempotency and immutable request identity assertions.
-- Fixtures are rolled back; run after all migrations and task activity assertions.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

DO $task_create_idempotency$
DECLARE
  request_id uuid := '92000000-0000-4000-8000-000000000099';
  first_task_id uuid := '92000000-0000-4000-8000-000000000001';
  duplicate_task_id uuid := '92000000-0000-4000-8000-000000000002';
  owner_b_task_id uuid := '92000000-0000-4000-8000-000000000003';
  request_hash text := repeat('a', 64);
  affected_rows integer;
  actual_id uuid;
  actual_title text;
  actual_hash text;
  error_constraint text;
BEGIN
  IF current_user <> 'authenticated' OR auth.uid() <> '11111111-1111-4111-8111-111111111111'::uuid THEN
    RAISE EXCEPTION 'Task request idempotency assertions must run as Owner A under authenticated role.';
  END IF;

  INSERT INTO public.tasks (id, user_id, title, client_request_id, client_request_hash)
  VALUES (first_task_id, auth.uid(), 'First request', request_id, request_hash)
  ON CONFLICT (user_id, client_request_id) DO NOTHING;
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'The first request must create exactly one task row.';
  END IF;

  INSERT INTO public.tasks (id, user_id, title, client_request_id, client_request_hash)
  VALUES (duplicate_task_id, auth.uid(), 'Duplicate request', request_id, request_hash)
  ON CONFLICT (user_id, client_request_id) DO NOTHING;
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 0 THEN
    RAISE EXCEPTION 'A same-owner duplicate request key created another task.';
  END IF;

  SELECT id, title, client_request_hash
  INTO actual_id, actual_title, actual_hash
  FROM public.tasks
  WHERE user_id = auth.uid() AND client_request_id = request_id;

  IF actual_id <> first_task_id
     OR actual_title <> 'First request'
     OR actual_hash <> request_hash THEN
    RAISE EXCEPTION 'A duplicate request changed the original task or its payload fingerprint.';
  END IF;

  IF (SELECT count(*) FROM public.activity_events
      WHERE user_id = auth.uid() AND entity_id = first_task_id AND event_type = 'TASK_CREATED') <> 1 THEN
    RAISE EXCEPTION 'A duplicate request created an extra TASK_CREATED event.';
  END IF;

  error_constraint := NULL;
  BEGIN
    UPDATE public.tasks
    SET client_request_id = '92000000-0000-4000-8000-000000000098'
    WHERE id = first_task_id;
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
  END;
  IF error_constraint IS DISTINCT FROM 'tasks_request_identity_immutable' THEN
    RAISE EXCEPTION 'Task request ID mutation was not rejected by its immutable identity trigger.';
  END IF;

  error_constraint := NULL;
  BEGIN
    UPDATE public.tasks
    SET client_request_hash = repeat('b', 64)
    WHERE id = first_task_id;
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
  END;
  IF error_constraint IS DISTINCT FROM 'tasks_request_identity_immutable' THEN
    RAISE EXCEPTION 'Task request hash mutation was not rejected by its immutable identity trigger.';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
  INSERT INTO public.tasks (id, user_id, title, client_request_id, client_request_hash)
  VALUES (owner_b_task_id, auth.uid(), 'Owner B same key', request_id, request_hash)
  ON CONFLICT (user_id, client_request_id) DO NOTHING;
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'The same request UUID must be reusable by a different owner.';
  END IF;

  IF (SELECT count(*) FROM public.tasks WHERE client_request_id = request_id) <> 2 THEN
    RAISE EXCEPTION 'Request uniqueness is not scoped to owner_id.';
  END IF;

  error_constraint := NULL;
  BEGIN
    INSERT INTO public.tasks (id, user_id, title, client_request_id, client_request_hash)
    VALUES ('92000000-0000-4000-8000-000000000004', auth.uid(), 'Invalid hash', '92000000-0000-4000-8000-000000000097', 'invalid');
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS error_constraint = CONSTRAINT_NAME;
  END;
  IF error_constraint IS DISTINCT FROM 'tasks_client_request_hash_check' THEN
    RAISE EXCEPTION 'Invalid task request hash was not rejected.';
  END IF;
END
$task_create_idempotency$;

RESET ROLE;
ROLLBACK;

SELECT 'Per-owner task request uniqueness, payload fingerprint immutability, and owner isolation passed.' AS result;
