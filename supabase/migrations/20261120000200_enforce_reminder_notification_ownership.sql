-- Enforce reminder/task and notification/reminder/task ownership at the database boundary.
-- Composite foreign keys preserve the existing CASCADE behavior while making
-- cross-owner and mismatched notification links impossible for every SQL role.
--
-- RLS policies remain owner-scoped and unchanged. Application preflight remains
-- defense in depth; these constraints are authoritative for PostgREST and service_role.

DO $preflight$
BEGIN
  IF to_regclass('public.tasks') IS NULL
     OR to_regclass('public.reminders') IS NULL
     OR to_regclass('public.notifications') IS NULL THEN
    RAISE EXCEPTION 'Reminder ownership integrity requires public.tasks, public.reminders, and public.notifications.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reminders r
    LEFT JOIN public.tasks t ON t.id = r.task_id
    WHERE t.id IS NULL
       OR r.user_id IS DISTINCT FROM t.user_id
  ) THEN
    RAISE EXCEPTION 'Existing reminder rows contain a missing or cross-owner task link; reconcile the data before installing reminder ownership constraints.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.notifications n
    LEFT JOIN public.reminders r ON r.id = n.reminder_id
    WHERE r.id IS NULL
       OR n.user_id IS DISTINCT FROM r.user_id
       OR n.task_id IS DISTINCT FROM r.task_id
  ) THEN
    RAISE EXCEPTION 'Existing notification rows contain a missing, cross-owner, or mismatched reminder/task link; reconcile the data before installing notification ownership constraints.';
  END IF;
END
$preflight$;

-- PostgreSQL requires a unique key over every referenced composite column set.
-- The leading id is already a primary key; these additional keys are required
-- so the foreign keys can include user_id (and task_id for notifications).
DO $unique_keys$
DECLARE
  tasks_id_attnum smallint;
  tasks_user_attnum smallint;
  reminders_id_attnum smallint;
  reminders_user_attnum smallint;
  reminders_task_attnum smallint;
BEGIN
  SELECT attnum INTO tasks_id_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.tasks'::regclass
    AND attname = 'id' AND NOT attisdropped;

  SELECT attnum INTO tasks_user_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.tasks'::regclass
    AND attname = 'user_id' AND NOT attisdropped;

  SELECT attnum INTO reminders_id_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass
    AND attname = 'id' AND NOT attisdropped;

  SELECT attnum INTO reminders_user_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass
    AND attname = 'user_id' AND NOT attisdropped;

  SELECT attnum INTO reminders_task_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass
    AND attname = 'task_id' AND NOT attisdropped;

  IF tasks_id_attnum IS NULL OR tasks_user_attnum IS NULL
     OR reminders_id_attnum IS NULL OR reminders_user_attnum IS NULL
     OR reminders_task_attnum IS NULL THEN
    RAISE EXCEPTION 'Reminder ownership integrity is missing a required id, user_id, or task_id column.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tasks'::regclass
      AND conname = 'tasks_id_user_id_key'
  ) THEN
    IF to_regclass('public.tasks_id_user_id_key') IS NOT NULL THEN
      RAISE EXCEPTION 'Relation name public.tasks_id_user_id_key is occupied by an unexpected object.';
    END IF;

    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_id_user_id_key UNIQUE (id, user_id);
  ELSIF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tasks'::regclass
      AND conname = 'tasks_id_user_id_key'
      AND contype = 'u'
      AND convalidated
      AND NOT condeferrable
      AND conkey = ARRAY[tasks_id_attnum, tasks_user_attnum]::smallint[]
  ) THEN
    RAISE EXCEPTION 'Constraint tasks_id_user_id_key exists with an unexpected contract.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_id_user_id_task_id_key'
  ) THEN
    IF to_regclass('public.reminders_id_user_id_task_id_key') IS NOT NULL THEN
      RAISE EXCEPTION 'Relation name public.reminders_id_user_id_task_id_key is occupied by an unexpected object.';
    END IF;

    ALTER TABLE public.reminders
      ADD CONSTRAINT reminders_id_user_id_task_id_key UNIQUE (id, user_id, task_id);
  ELSIF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_id_user_id_task_id_key'
      AND contype = 'u'
      AND convalidated
      AND NOT condeferrable
      AND conkey = ARRAY[
        reminders_id_attnum,
        reminders_user_attnum,
        reminders_task_attnum
      ]::smallint[]
  ) THEN
    RAISE EXCEPTION 'Constraint reminders_id_user_id_task_id_key exists with an unexpected contract.';
  END IF;
END
$unique_keys$;

-- Replace the single-column reminder.task_id FK with an owner-aware composite FK.
-- Fail closed if another FK already references task_id; do not silently remove it.
DO $reminder_task_fk$
DECLARE
  source_task_attnum smallint;
  source_user_attnum smallint;
  target_id_attnum smallint;
  target_user_attnum smallint;
  foreign_key_count integer;
  old_name_exists boolean;
  old_exact boolean;
  new_name_exists boolean;
  new_exact boolean;
BEGIN
  SELECT attnum INTO source_task_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass
    AND attname = 'task_id' AND NOT attisdropped;
  SELECT attnum INTO source_user_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass
    AND attname = 'user_id' AND NOT attisdropped;
  SELECT attnum INTO target_id_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.tasks'::regclass
    AND attname = 'id' AND NOT attisdropped;
  SELECT attnum INTO target_user_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.tasks'::regclass
    AND attname = 'user_id' AND NOT attisdropped;

  SELECT count(*)::integer INTO foreign_key_count
  FROM pg_constraint
  WHERE conrelid = 'public.reminders'::regclass
    AND contype = 'f'
    AND source_task_attnum = ANY(conkey);

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_task_id_fkey'
  ) INTO old_name_exists;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_task_id_fkey'
      AND contype = 'f'
      AND confrelid = 'public.tasks'::regclass
      AND conkey = ARRAY[source_task_attnum]::smallint[]
      AND confkey = ARRAY[target_id_attnum]::smallint[]
      AND confdeltype = 'c'
      AND confupdtype = 'a'
  ) INTO old_exact;

  IF old_name_exists THEN
    IF NOT old_exact OR foreign_key_count <> 1 THEN
      RAISE EXCEPTION 'Unexpected foreign-key contract for public.reminders.task_id; refusing to remove an unknown or duplicate constraint.';
    END IF;

    ALTER TABLE public.reminders DROP CONSTRAINT reminders_task_id_fkey;
    foreign_key_count := foreign_key_count - 1;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_task_owner_fkey'
  ) INTO new_name_exists;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_task_owner_fkey'
      AND contype = 'f'
      AND confrelid = 'public.tasks'::regclass
      AND conkey = ARRAY[source_task_attnum, source_user_attnum]::smallint[]
      AND confkey = ARRAY[target_id_attnum, target_user_attnum]::smallint[]
      AND confdeltype = 'c'
      AND confupdtype = 'a'
      AND convalidated
  ) INTO new_exact;

  IF new_name_exists THEN
    IF NOT new_exact OR foreign_key_count <> 1 THEN
      RAISE EXCEPTION 'Unexpected foreign-key contract for public.reminders.task_id; the composite owner FK is not the sole exact relationship.';
    END IF;
  ELSIF foreign_key_count = 0 THEN
    ALTER TABLE public.reminders
      ADD CONSTRAINT reminders_task_owner_fkey
      FOREIGN KEY (task_id, user_id)
      REFERENCES public.tasks (id, user_id)
      ON DELETE CASCADE;
  ELSE
    RAISE EXCEPTION 'Unexpected foreign-key contract for public.reminders.task_id; inspect existing constraints before rollout.';
  END IF;

  SELECT count(*)::integer INTO foreign_key_count
  FROM pg_constraint
  WHERE conrelid = 'public.reminders'::regclass
    AND contype = 'f'
    AND source_task_attnum = ANY(conkey);

  IF foreign_key_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reminders'::regclass
      AND conname = 'reminders_task_owner_fkey'
      AND contype = 'f'
      AND confrelid = 'public.tasks'::regclass
      AND conkey = ARRAY[source_task_attnum, source_user_attnum]::smallint[]
      AND confkey = ARRAY[target_id_attnum, target_user_attnum]::smallint[]
      AND confdeltype = 'c'
      AND confupdtype = 'a'
      AND convalidated
  ) THEN
    RAISE EXCEPTION 'The exact validated reminders_task_owner_fkey contract was not installed.';
  END IF;
END
$reminder_task_fk$;

-- Replace the single-column notification.reminder_id FK with a composite key.
-- Matching all three values enforces both owner equality and reminder/task equality.
DO $notification_reminder_fk$
DECLARE
  source_reminder_attnum smallint;
  source_user_attnum smallint;
  source_task_attnum smallint;
  target_id_attnum smallint;
  target_user_attnum smallint;
  target_task_attnum smallint;
  foreign_key_count integer;
  old_name_exists boolean;
  old_exact boolean;
  new_name_exists boolean;
  new_exact boolean;
BEGIN
  SELECT attnum INTO source_reminder_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.notifications'::regclass
    AND attname = 'reminder_id' AND NOT attisdropped;
  SELECT attnum INTO source_user_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.notifications'::regclass
    AND attname = 'user_id' AND NOT attisdropped;
  SELECT attnum INTO source_task_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.notifications'::regclass
    AND attname = 'task_id' AND NOT attisdropped;
  SELECT attnum INTO target_id_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass
    AND attname = 'id' AND NOT attisdropped;
  SELECT attnum INTO target_user_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass
    AND attname = 'user_id' AND NOT attisdropped;
  SELECT attnum INTO target_task_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.reminders'::regclass
    AND attname = 'task_id' AND NOT attisdropped;

  SELECT count(*)::integer INTO foreign_key_count
  FROM pg_constraint
  WHERE conrelid = 'public.notifications'::regclass
    AND contype = 'f'
    AND source_reminder_attnum = ANY(conkey);

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_reminder_id_fkey'
  ) INTO old_name_exists;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_reminder_id_fkey'
      AND contype = 'f'
      AND confrelid = 'public.reminders'::regclass
      AND conkey = ARRAY[source_reminder_attnum]::smallint[]
      AND confkey = ARRAY[target_id_attnum]::smallint[]
      AND confdeltype = 'c'
      AND confupdtype = 'a'
  ) INTO old_exact;

  IF old_name_exists THEN
    IF NOT old_exact OR foreign_key_count <> 1 THEN
      RAISE EXCEPTION 'Unexpected foreign-key contract for public.notifications.reminder_id; refusing to remove an unknown or duplicate constraint.';
    END IF;

    ALTER TABLE public.notifications DROP CONSTRAINT notifications_reminder_id_fkey;
    foreign_key_count := foreign_key_count - 1;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_reminder_owner_task_fkey'
  ) INTO new_name_exists;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_reminder_owner_task_fkey'
      AND contype = 'f'
      AND confrelid = 'public.reminders'::regclass
      AND conkey = ARRAY[
        source_reminder_attnum,
        source_user_attnum,
        source_task_attnum
      ]::smallint[]
      AND confkey = ARRAY[
        target_id_attnum,
        target_user_attnum,
        target_task_attnum
      ]::smallint[]
      AND confdeltype = 'c'
      AND confupdtype = 'a'
      AND convalidated
  ) INTO new_exact;

  IF new_name_exists THEN
    IF NOT new_exact OR foreign_key_count <> 1 THEN
      RAISE EXCEPTION 'Unexpected foreign-key contract for public.notifications.reminder_id; the composite owner/task FK is not the sole exact relationship.';
    END IF;
  ELSIF foreign_key_count = 0 THEN
    ALTER TABLE public.notifications
      ADD CONSTRAINT notifications_reminder_owner_task_fkey
      FOREIGN KEY (reminder_id, user_id, task_id)
      REFERENCES public.reminders (id, user_id, task_id)
      ON DELETE CASCADE;
  ELSE
    RAISE EXCEPTION 'Unexpected foreign-key contract for public.notifications.reminder_id; inspect existing constraints before rollout.';
  END IF;

  SELECT count(*)::integer INTO foreign_key_count
  FROM pg_constraint
  WHERE conrelid = 'public.notifications'::regclass
    AND contype = 'f'
    AND source_reminder_attnum = ANY(conkey);

  IF foreign_key_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_reminder_owner_task_fkey'
      AND contype = 'f'
      AND confrelid = 'public.reminders'::regclass
      AND conkey = ARRAY[
        source_reminder_attnum,
        source_user_attnum,
        source_task_attnum
      ]::smallint[]
      AND confkey = ARRAY[
        target_id_attnum,
        target_user_attnum,
        target_task_attnum
      ]::smallint[]
      AND confdeltype = 'c'
      AND confupdtype = 'a'
      AND convalidated
  ) THEN
    RAISE EXCEPTION 'The exact validated notifications_reminder_owner_task_fkey contract was not installed.';
  END IF;
END
$notification_reminder_fk$;
