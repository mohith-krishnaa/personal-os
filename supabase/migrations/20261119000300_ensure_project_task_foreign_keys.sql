-- Ensure the project/task foreign-key contracts are exact before Organization rollout.
-- Repair a missing relationship, validate an exact NOT VALID relationship, and
-- fail closed on any unexpected FK involving the source column. Never drop or
-- rewrite an existing constraint automatically.
DO $foreign_keys$
DECLARE
  expected record;
  source_relation regclass;
  target_relation regclass;
  source_attnum smallint;
  target_attnum smallint;
  foreign_key_count integer;
  exact_foreign_key_count integer;
  exact_constraint_name text;
  exact_constraint_validated boolean;
BEGIN
  FOR expected IN
    SELECT *
    FROM (VALUES
      ('tasks', 'project_id', 'projects', 'id', 'SET NULL', 'n'::"char", 'tasks_project_id_fkey'),
      ('tasks', 'parent_task_id', 'tasks', 'id', 'CASCADE', 'c'::"char", 'tasks_parent_task_id_fkey'),
      ('projects', 'goal_id', 'goals', 'id', 'SET NULL', 'n'::"char", 'projects_goal_id_fkey')
    ) AS contracts(
      source_table, source_column, target_table, target_column,
      delete_action, delete_action_code, constraint_name
    )
  LOOP
    source_relation := to_regclass(format('public.%I', expected.source_table));
    target_relation := to_regclass(format('public.%I', expected.target_table));

    IF source_relation IS NULL OR target_relation IS NULL THEN
      RAISE EXCEPTION
        'Cannot verify Organization foreign key public.%.% -> public.%.%: source or target table is missing.',
        expected.source_table, expected.source_column,
        expected.target_table, expected.target_column;
    END IF;

    SELECT attnum INTO source_attnum
    FROM pg_attribute
    WHERE attrelid = source_relation
      AND attname = expected.source_column
      AND NOT attisdropped;

    SELECT attnum INTO target_attnum
    FROM pg_attribute
    WHERE attrelid = target_relation
      AND attname = expected.target_column
      AND NOT attisdropped;

    IF source_attnum IS NULL OR target_attnum IS NULL THEN
      RAISE EXCEPTION
        'Cannot verify Organization foreign key public.%.% -> public.%.%: source or target column is missing.',
        expected.source_table, expected.source_column,
        expected.target_table, expected.target_column;
    END IF;

    SELECT
      count(*)::integer,
      count(*) FILTER (
        WHERE con.confrelid = target_relation
          AND con.conkey = ARRAY[source_attnum]::smallint[]
          AND con.confkey = ARRAY[target_attnum]::smallint[]
          AND con.confdeltype = expected.delete_action_code
      )::integer,
      min(con.conname::text) FILTER (
        WHERE con.confrelid = target_relation
          AND con.conkey = ARRAY[source_attnum]::smallint[]
          AND con.confkey = ARRAY[target_attnum]::smallint[]
          AND con.confdeltype = expected.delete_action_code
      ),
      bool_and(con.convalidated) FILTER (
        WHERE con.confrelid = target_relation
          AND con.conkey = ARRAY[source_attnum]::smallint[]
          AND con.confkey = ARRAY[target_attnum]::smallint[]
          AND con.confdeltype = expected.delete_action_code
      )
    INTO
      foreign_key_count,
      exact_foreign_key_count,
      exact_constraint_name,
      exact_constraint_validated
    FROM pg_constraint con
    WHERE con.conrelid = source_relation
      AND con.contype = 'f'
      AND source_attnum = ANY(con.conkey);

    IF foreign_key_count = 0 THEN
      IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = source_relation
          AND conname = expected.constraint_name
      ) THEN
        RAISE EXCEPTION
          'Constraint name % already exists on public.% but is not the expected foreign key.',
          expected.constraint_name, expected.source_table;
      END IF;

      EXECUTE format(
        'ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I.%I (%I) ON DELETE %s',
        'public', expected.source_table, expected.constraint_name,
        expected.source_column, 'public', expected.target_table,
        expected.target_column, expected.delete_action
      );
      RAISE NOTICE 'Created missing foreign key % on public.%.%',
        expected.constraint_name, expected.source_table, expected.source_column;

    ELSIF foreign_key_count = 1 AND exact_foreign_key_count = 1 THEN
      IF NOT coalesce(exact_constraint_validated, false) THEN
        EXECUTE format(
          'ALTER TABLE %I.%I VALIDATE CONSTRAINT %I',
          'public', expected.source_table, exact_constraint_name
        );
        RAISE NOTICE 'Validated existing foreign key % on public.%.%',
          exact_constraint_name, expected.source_table, expected.source_column;
      END IF;

    ELSE
      RAISE EXCEPTION
        'Unexpected foreign-key contract for public.%.%: found % foreign key(s), % matching the required target/action. No existing constraint was removed; inspect and repair manually.',
        expected.source_table, expected.source_column,
        foreign_key_count, exact_foreign_key_count;
    END IF;
  END LOOP;
END
$foreign_keys$;
