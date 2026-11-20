-- Persist stable per-owner request identities for first-party task/subtask creation.
-- Existing rows receive opaque server-generated keys; first-party clients pass a
-- stable UUID and a SHA-256 payload fingerprint so retries can resolve safely.
DO $migration_preflight$
DECLARE
  tasks_oid oid := to_regclass('public.tasks');
  request_id_attnum smallint;
  hash_attnum smallint;
  existing_constraint record;
BEGIN
  IF tasks_oid IS NULL THEN
    RAISE EXCEPTION 'Required table public.tasks is missing.';
  END IF;

  SELECT attnum INTO request_id_attnum
  FROM pg_attribute
  WHERE attrelid = tasks_oid AND attname = 'client_request_id' AND NOT attisdropped;
  IF request_id_attnum IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = tasks_oid AND attname = 'client_request_id'
      AND atttypid = 'uuid'::regtype AND NOT attnotnull AND NOT attisdropped
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = tasks_oid AND attname = 'client_request_id'
      AND atttypid = 'uuid'::regtype AND attnotnull AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'public.tasks.client_request_id has an unexpected type or dropped state.';
  END IF;

  SELECT attnum INTO hash_attnum
  FROM pg_attribute
  WHERE attrelid = tasks_oid AND attname = 'client_request_hash' AND NOT attisdropped;
  IF hash_attnum IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = tasks_oid AND attname = 'client_request_hash'
      AND atttypid = 'text'::regtype AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'public.tasks.client_request_hash has an unexpected type.';
  END IF;

  SELECT conname, contype, conkey, convalidated, condeferrable
  INTO existing_constraint
  FROM pg_constraint
  WHERE conrelid = tasks_oid AND conname = 'tasks_user_client_request_unique';

  IF FOUND AND (
    existing_constraint.contype <> 'u'
    OR existing_constraint.conkey <> ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = tasks_oid AND attname = 'user_id' AND NOT attisdropped),
      coalesce(request_id_attnum, 0)
    ]::smallint[]
    OR NOT existing_constraint.convalidated
    OR existing_constraint.condeferrable
  ) THEN
    RAISE EXCEPTION 'Existing tasks_user_client_request_unique has an unexpected definition.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint con
    WHERE con.conrelid = tasks_oid
      AND con.contype = 'u'
      AND con.conkey = ARRAY[
        (SELECT attnum FROM pg_attribute WHERE attrelid = tasks_oid AND attname = 'user_id' AND NOT attisdropped),
        coalesce(request_id_attnum, 0)
      ]::smallint[]
      AND con.conname <> 'tasks_user_client_request_unique'
  ) THEN
    RAISE EXCEPTION 'Unexpected duplicate unique constraint exists for task request identity.';
  END IF;
END;
$migration_preflight$;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS client_request_id uuid;

ALTER TABLE public.tasks
  ALTER COLUMN client_request_id SET DEFAULT gen_random_uuid();

UPDATE public.tasks
SET client_request_id = gen_random_uuid()
WHERE client_request_id IS NULL;

ALTER TABLE public.tasks
  ALTER COLUMN client_request_id SET NOT NULL;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS client_request_hash text;

DO $constraints$
DECLARE
  existing_definition text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO existing_definition
  FROM pg_constraint
  WHERE conrelid = 'public.tasks'::regclass
    AND conname = 'tasks_client_request_hash_check';

  IF existing_definition IS NOT NULL
     AND existing_definition NOT LIKE '%client_request_hash IS NULL%'
     AND existing_definition NOT LIKE '%client_request_hash ~%64%' THEN
    RAISE EXCEPTION 'Existing tasks_client_request_hash_check has an unexpected definition.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tasks'::regclass
      AND conname = 'tasks_user_client_request_unique'
      AND contype = 'u'
  ) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_user_client_request_unique UNIQUE (user_id, client_request_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tasks'::regclass
      AND conname = 'tasks_client_request_hash_check'
  ) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_client_request_hash_check
      CHECK (client_request_hash IS NULL OR client_request_hash ~ '^[0-9a-f]{64}$');
  END IF;
END;
$constraints$;

CREATE OR REPLACE FUNCTION public.prevent_task_request_identity_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.client_request_id IS DISTINCT FROM OLD.client_request_id
     OR NEW.client_request_hash IS DISTINCT FROM OLD.client_request_hash THEN
    RAISE EXCEPTION 'Task creation request identity is immutable.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.prevent_task_request_identity_change() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prevent_task_request_identity_change() TO authenticated, service_role;

DROP TRIGGER IF EXISTS tasks_request_identity_immutable ON public.tasks;
CREATE TRIGGER tasks_request_identity_immutable
BEFORE UPDATE OF client_request_id, client_request_hash ON public.tasks
FOR EACH ROW
EXECUTE FUNCTION public.prevent_task_request_identity_change();
