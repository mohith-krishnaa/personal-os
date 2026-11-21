#!/usr/bin/env bash
set -euo pipefail

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export PGDATABASE="${PGDATABASE:-personal_os_migration_test}"

owner_id='11111111-1111-4111-8111-111111111111'
root_id="$(psql -X -A -t -v ON_ERROR_STOP=1 -c 'SELECT gen_random_uuid()' | tr -d '[:space:]')"
winner_id="$(psql -X -A -t -v ON_ERROR_STOP=1 -c 'SELECT gen_random_uuid()' | tr -d '[:space:]')"
loser_id="$(psql -X -A -t -v ON_ERROR_STOP=1 -c 'SELECT gen_random_uuid()' | tr -d '[:space:]')"
root_due='2099-01-01T09:00:00Z'
next_due='2099-01-02T09:00:00Z'
tmpdir="$(mktemp -d)"
first_pid=''

cleanup() {
  if [[ -n "$first_pid" ]]; then
    wait "$first_pid" 2>/dev/null || true
  fi
  psql -X -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL || true
DELETE FROM public.tasks WHERE id IN ('$winner_id', '$loser_id');
DELETE FROM public.tasks WHERE id = '$root_id';
DELETE FROM public.activity_events
WHERE entity_type = 'TASK'
  AND entity_id IN ('$root_id', '$winner_id', '$loser_id');
SQL
  rm -rf "$tmpdir"
}
trap cleanup EXIT

psql -X -v ON_ERROR_STOP=1 <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '$owner_id';
INSERT INTO public.tasks (id, user_id, title, status, due_at, recurrence_rule)
VALUES (
  '$root_id',
  auth.uid(),
  'Concurrent recurring root',
  'TODO',
  '$root_due',
  '{"frequency":"DAILY","interval":1}'::jsonb
);
UPDATE public.tasks
SET recurrence_parent_id = '$root_id', updated_at = now()
WHERE id = '$root_id' AND user_id = auth.uid();
COMMIT;
SQL

echo "Concurrent recurring completion: two authenticated requests share one owner/root/next-due key."

PGAPPNAME=personal-os-recurring-completion-first \
  psql -X -qAt -v ON_ERROR_STOP=1 >"$tmpdir/first.out" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '$owner_id';
UPDATE public.tasks
SET status = 'COMPLETED', completed_at = now(), updated_at = now()
WHERE id = '$root_id' AND user_id = auth.uid() AND status <> 'COMPLETED';
INSERT INTO public.tasks (
  id, user_id, recurrence_parent_id, recurrence_rule, due_at, title
)
VALUES (
  '$winner_id',
  auth.uid(),
  '$root_id',
  '{"frequency":"DAILY","interval":1}'::jsonb,
  '$next_due',
  'Concurrent recurring occurrence'
)
RETURNING id;
SELECT pg_sleep(2);
COMMIT;
SQL
first_pid=$!

for attempt in $(seq 1 100); do
  if grep -Fq "$winner_id" "$tmpdir/first.out"; then
    break
  fi
  if ! kill -0 "$first_pid" 2>/dev/null; then
    wait "$first_pid" || true
    echo "The first recurring completion worker exited before inserting its occurrence."
    cat "$tmpdir/first.out"
    exit 1
  fi
  sleep 0.05
done

if ! grep -Fq "$winner_id" "$tmpdir/first.out"; then
  echo "The first recurring completion worker did not acquire the occurrence key."
  cat "$tmpdir/first.out"
  exit 1
fi

PGAPPNAME=personal-os-recurring-completion-retry \
  psql -X -qAt -v ON_ERROR_STOP=1 >"$tmpdir/retry.out" <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '$owner_id';
UPDATE public.tasks
SET status = 'COMPLETED', completed_at = now(), updated_at = now()
WHERE id = '$root_id' AND user_id = auth.uid() AND status <> 'COMPLETED';
DO \$retry\$
DECLARE
  v_constraint text;
  v_existing_id uuid;
BEGIN
  BEGIN
    INSERT INTO public.tasks (
      id, user_id, recurrence_parent_id, recurrence_rule, due_at, title
    )
    VALUES (
      '$loser_id',
      auth.uid(),
      '$root_id',
      '{"frequency":"DAILY","interval":1}'::jsonb,
      '$next_due',
      'Concurrent recurring occurrence retry'
    );
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
  END;

  IF v_constraint IS DISTINCT FROM 'tasks_recurring_occurrence_unique' THEN
    RAISE EXCEPTION 'Expected the recurring-occurrence unique index conflict; got %.', v_constraint;
  END IF;

  SELECT id INTO v_existing_id
  FROM public.tasks
  WHERE user_id = auth.uid()
    AND recurrence_parent_id = '$root_id'
    AND due_at = '$next_due';

  IF v_existing_id IS DISTINCT FROM '$winner_id'::uuid THEN
    RAISE EXCEPTION 'The retry did not resolve to the committed winning occurrence.';
  END IF;
END;
\$retry\$;
SELECT id::text
FROM public.tasks
WHERE user_id = auth.uid()
  AND recurrence_parent_id = '$root_id'
  AND due_at = '$next_due';
COMMIT;
SQL

wait "$first_pid"
first_pid=''

if ! grep -Fq "$winner_id" "$tmpdir/retry.out"; then
  echo "The concurrent recurrence retry did not resolve to the winning occurrence."
  cat "$tmpdir/retry.out"
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 <<SQL
DO \$verify\$
DECLARE
  v_owner uuid := '$owner_id';
  v_root uuid := '$root_id';
  v_winner uuid := '$winner_id';
  v_loser uuid := '$loser_id';
  v_next_due timestamptz := '$next_due';
BEGIN
  IF (SELECT status FROM public.tasks WHERE id = v_root AND user_id = v_owner) IS DISTINCT FROM 'COMPLETED' THEN
    RAISE EXCEPTION 'Concurrent completion did not leave the recurring root completed.';
  END IF;

  IF (SELECT count(*) FROM public.activity_events
      WHERE user_id = v_owner AND entity_type = 'TASK'
        AND entity_id = v_root AND event_type = 'TASK_COMPLETED') <> 1 THEN
    RAISE EXCEPTION 'Concurrent completion must produce exactly one TASK_COMPLETED event.';
  END IF;

  IF (SELECT count(*) FROM public.tasks
      WHERE user_id = v_owner AND recurrence_parent_id = v_root AND due_at = v_next_due) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM public.tasks
       WHERE id = v_winner AND user_id = v_owner
         AND recurrence_parent_id = v_root AND due_at = v_next_due
         AND recurrence_rule IS NOT NULL
     )
     OR EXISTS (SELECT 1 FROM public.tasks WHERE id = v_loser) THEN
    RAISE EXCEPTION 'Concurrent completion created a duplicate or lost the winning recurrence occurrence.';
  END IF;

  IF (SELECT count(*) FROM public.activity_events
      WHERE user_id = v_owner AND entity_type = 'TASK'
        AND entity_id = v_winner AND event_type = 'TASK_RECURRENCE_GENERATED'
        AND metadata ->> 'source_task_id' = v_root::text) <> 1
     OR EXISTS (
       SELECT 1 FROM public.activity_events
       WHERE user_id = v_owner AND entity_type = 'TASK'
         AND entity_id = v_loser AND event_type = 'TASK_RECURRENCE_GENERATED'
     ) THEN
    RAISE EXCEPTION 'Concurrent occurrence creation must emit exactly one source-linked TASK_RECURRENCE_GENERATED event.';
  END IF;
END;
\$verify\$;
SQL

echo "Concurrent recurring completion, occurrence uniqueness, and event accounting passed."
