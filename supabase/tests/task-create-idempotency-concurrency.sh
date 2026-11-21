#!/usr/bin/env bash
set -euo pipefail

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export PGDATABASE="${PGDATABASE:-personal_os_migration_test}"

tmpdir="$(mktemp -d)"
cleanup() {
  psql -X -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL || true
DELETE FROM public.activity_events WHERE entity_type = 'TASK' AND entity_id IN ('$parent_id', '$winner_id', '$loser_id');
DELETE FROM public.tasks WHERE id IN ('$parent_id', '$winner_id', '$loser_id');
SQL
  rm -rf "$tmpdir"
}
trap cleanup EXIT

owner_id='11111111-1111-4111-8111-111111111111'
request_id='93000000-0000-4000-8000-000000000099'
winner_id='93000000-0000-4000-8000-000000000001'
loser_id='93000000-0000-4000-8000-000000000002'
parent_id='93000000-0000-4000-8000-000000000003'
request_hash="$(printf '%s' 'same concurrent subtask payload' | sha256sum | awk '{print $1}')"

psql -X -v ON_ERROR_STOP=1 <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '$owner_id';
INSERT INTO public.tasks (id, user_id, title)
VALUES ('$parent_id', auth.uid(), 'Concurrent subtask parent');
COMMIT;
SQL

echo "Concurrent subtask create case: two authenticated requests share one owner/request key."

PGAPPNAME=personal-os-task-create-winner psql -X -qAt -v ON_ERROR_STOP=1 >"$tmpdir/winner.out" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '$owner_id';
INSERT INTO public.tasks (id, user_id, parent_task_id, title, client_request_id, client_request_hash)
VALUES ('$winner_id', auth.uid(), '$parent_id', 'Concurrent subtask', '$request_id', '$request_hash')
ON CONFLICT (user_id, client_request_id) DO NOTHING
RETURNING id;
SELECT pg_sleep(2);
COMMIT;
SQL
winner_pid=$!

for attempt in $(seq 1 100); do
  if grep -Fq "$winner_id" "$tmpdir/winner.out"; then
    break
  fi
  sleep 0.05
done
if ! grep -Fq "$winner_id" "$tmpdir/winner.out"; then
  echo "The first worker did not acquire the request key before the retry started."
  wait "$winner_pid" || true
  cat "$tmpdir/winner.out"
  exit 1
fi

PGAPPNAME=personal-os-task-create-retry psql -X -qAt -v ON_ERROR_STOP=1 >"$tmpdir/retry.out" <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '$owner_id';
INSERT INTO public.tasks (id, user_id, parent_task_id, title, client_request_id, client_request_hash)
VALUES ('$loser_id', auth.uid(), '$parent_id', 'Concurrent subtask', '$request_id', '$request_hash')
ON CONFLICT (user_id, client_request_id) DO NOTHING
RETURNING id;
SELECT id::text || '|' || title
FROM public.tasks
WHERE user_id = auth.uid() AND client_request_id = '$request_id';
COMMIT;
SQL

wait "$winner_pid"

if ! grep -Fq "$winner_id|Concurrent subtask" "$tmpdir/retry.out"; then
  echo "The concurrent retry did not resolve to the winning task."
  cat "$tmpdir/winner.out" "$tmpdir/retry.out"
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 <<SQL
DO \$verify\$
BEGIN
  IF (SELECT count(*) FROM public.tasks WHERE user_id = '$owner_id' AND client_request_id = '$request_id') <> 1 THEN
    RAISE EXCEPTION 'Concurrent duplicate requests created more than one subtask.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE id = '$winner_id' AND parent_task_id = '$parent_id' AND user_id = '$owner_id') THEN
    RAISE EXCEPTION 'The winning concurrent subtask lost its owner or parent relationship.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.tasks WHERE id = '$loser_id') THEN
    RAISE EXCEPTION 'The losing concurrent request left a duplicate task row.';
  END IF;
  IF (SELECT count(*) FROM public.activity_events WHERE user_id = '$owner_id' AND entity_id = '$winner_id' AND event_type = 'TASK_CREATED') <> 1
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE user_id = '$owner_id' AND entity_id = '$loser_id' AND event_type = 'TASK_CREATED') THEN
    RAISE EXCEPTION 'Concurrent duplicate subtask requests did not produce exactly one TASK_CREATED event.';
  END IF;
END;
\$verify\$;
SQL

echo "Concurrent subtask create idempotency and activity-event accounting passed."
