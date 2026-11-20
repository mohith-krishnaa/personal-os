#!/usr/bin/env bash
set -euo pipefail

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export PGDATABASE="${PGDATABASE:-personal_os_test}"

psql -X -v ON_ERROR_STOP=1 -c 'select 1' >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/organization-task-hierarchy.sql

tmpdir="$(mktemp -d)"
writer_a_pid=""
writer_b_pid=""

cleanup() {
  for pid in "$writer_a_pid" "$writer_b_pid"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$tmpdir"
}
trap cleanup EXIT

PGAPPNAME=personal-os-cycle-writer-a psql -X -v ON_ERROR_STOP=1 \
  -c "begin isolation level read committed;
      update public.tasks
         set parent_task_id = '10000000-0000-4000-8000-000000000007'
       where id = '10000000-0000-4000-8000-000000000006';
      select pg_sleep(3);
      commit;" >"$tmpdir/writer-a.log" 2>&1 &
writer_a_pid=$!

sleeping=0
for _ in $(seq 1 100); do
  sleeping="$(psql -X -Atq -c "select count(*) from pg_stat_activity
    where application_name = 'personal-os-cycle-writer-a'
      and state = 'active'
      and query like '%pg_sleep(3)%'")"
  if [[ "$sleeping" == "1" ]]; then break; fi
  if ! kill -0 "$writer_a_pid" 2>/dev/null; then break; fi
  sleep 0.05
done

if [[ "$sleeping" != "1" ]]; then
  echo "Writer A did not reach the expected in-transaction sleep."
  cat "$tmpdir/writer-a.log"
  exit 1
fi

PGAPPNAME=personal-os-cycle-writer-b psql -X -v ON_ERROR_STOP=1 \
  -c "begin isolation level read committed;
      update public.tasks
         set parent_task_id = '10000000-0000-4000-8000-000000000006'
       where id = '10000000-0000-4000-8000-000000000007';
      commit;" >"$tmpdir/writer-b.log" 2>&1 &
writer_b_pid=$!

blocked=0
for _ in $(seq 1 100); do
  blocked="$(psql -X -Atq -c "select count(*) from pg_stat_activity
    where application_name = 'personal-os-cycle-writer-b'
      and state = 'active'
      and wait_event_type = 'Lock'
      and wait_event = 'advisory'")"
  if [[ "$blocked" == "1" ]]; then break; fi
  active="$(psql -X -Atq -c "select count(*) from pg_stat_activity
    where application_name = 'personal-os-cycle-writer-b'
      and state = 'active'")"
  if [[ "$active" == "0" ]]; then break; fi
  sleep 0.05
done

if [[ "$blocked" != "1" ]]; then
  echo "Writer B did not wait on the owner-scoped advisory transaction lock."
  cat "$tmpdir/writer-a.log" "$tmpdir/writer-b.log"
  exit 1
fi

set +e
wait "$writer_a_pid"
writer_a_status=$?
wait "$writer_b_pid"
writer_b_status=$?
set -e

if [[ "$writer_a_status" -ne 0 ]]; then
  echo "Writer A unexpectedly failed."
  cat "$tmpdir/writer-a.log"
  exit 1
fi

if [[ "$writer_b_status" -eq 0 ]]; then
  echo "Writer B committed an edge that should have completed a cycle."
  cat "$tmpdir/writer-b.log"
  exit 1
fi

if ! grep -q 'Task hierarchy cannot contain cycles.' "$tmpdir/writer-b.log"; then
  echo "Writer B failed for an unexpected reason."
  cat "$tmpdir/writer-b.log"
  exit 1
fi

echo "Organization task-link checks passed, including concurrent cycle rejection."

writer_a_pid=""
writer_b_pid=""

wait_for_sleep() {
  local app_name="$1"
  local sleeping=0

  for _ in $(seq 1 200); do
    sleeping="$(psql -X -Atq -v app_name="$app_name" -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = :'app_name' AND state = 'active' AND query LIKE '%pg_sleep(2)%';")"
    if [[ "$sleeping" == "1" ]]; then return 0; fi
    sleep 0.05
  done

  echo "Session $app_name did not reach the expected in-transaction sleep."
  return 1
}

wait_for_blocker() {
  local waiting_app="$1"
  local blocking_app="$2"
  local blocked=0

  for _ in $(seq 1 200); do
    blocked="$(psql -X -Atq -v waiting_app="$waiting_app" -v blocking_app="$blocking_app" -c "SELECT count(*) FROM pg_stat_activity AS waiting WHERE waiting.application_name = :'waiting_app' AND EXISTS (SELECT 1 FROM pg_stat_activity AS blocking WHERE blocking.application_name = :'blocking_app' AND blocking.pid = ANY(pg_blocking_pids(waiting.pid)));")"
    if [[ "$blocked" == "1" ]]; then return 0; fi
    active="$(psql -X -Atq -v waiting_app="$waiting_app" -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = :'waiting_app' AND state = 'active';")"
    if [[ "$active" == "0" ]]; then break; fi
    sleep 0.05
  done

  echo "Session $waiting_app was not observed blocked by $blocking_app."
  return 1
}

echo "Seeding isolated projects/tasks for archive-assignment lock ordering"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO public.projects (id, user_id, status) VALUES
  ('d1000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'ACTIVE'),
  ('d1000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'ACTIVE');

INSERT INTO public.tasks (id, user_id, project_id) VALUES
  ('d2000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', NULL),
  ('d2000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', NULL);
SQL

echo "Concurrency case 1: task assignment locks the ACTIVE project before archive"
PGAPPNAME=personal-os-assignment-first PGOPTIONS='-c lock_timeout=15s -c statement_timeout=20s' psql -X -v ON_ERROR_STOP=1 \
  -c "BEGIN ISOLATION LEVEL READ COMMITTED;
      UPDATE public.tasks
         SET project_id = 'd1000000-0000-4000-8000-000000000001'
       WHERE id = 'd2000000-0000-4000-8000-000000000001';
      SELECT pg_sleep(2);
      COMMIT;" >"$tmpdir/assignment-first.log" 2>&1 &
writer_a_pid=$!

if ! wait_for_sleep "personal-os-assignment-first"; then
  cat "$tmpdir/assignment-first.log"
  exit 1
fi

PGAPPNAME=personal-os-archive-after-assignment PGOPTIONS='-c lock_timeout=15s -c statement_timeout=20s' psql -X -v ON_ERROR_STOP=1 \
  -c "BEGIN ISOLATION LEVEL READ COMMITTED;
      UPDATE public.projects
         SET status = 'ARCHIVED'
       WHERE id = 'd1000000-0000-4000-8000-000000000001';
      COMMIT;" >"$tmpdir/archive-after-assignment.log" 2>&1 &
writer_b_pid=$!

if ! wait_for_blocker "personal-os-archive-after-assignment" "personal-os-assignment-first"; then
  cat "$tmpdir/assignment-first.log" "$tmpdir/archive-after-assignment.log"
  exit 1
fi

set +e
wait "$writer_a_pid"
writer_a_status=$?
wait "$writer_b_pid"
writer_b_status=$?
set -e
writer_a_pid=""
writer_b_pid=""

if [[ "$writer_a_status" -ne 0 || "$writer_b_status" -ne 0 ]]; then
  echo "Assignment-first ordering should allow both transactions to commit."
  cat "$tmpdir/assignment-first.log" "$tmpdir/archive-after-assignment.log"
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $assert_assignment_first$
BEGIN
  IF (SELECT status FROM public.projects WHERE id = 'd1000000-0000-4000-8000-000000000001') <> 'ARCHIVED' THEN
    RAISE EXCEPTION 'The archive did not commit after the task assignment.';
  END IF;
  IF (SELECT project_id FROM public.tasks WHERE id = 'd2000000-0000-4000-8000-000000000001') IS DISTINCT FROM 'd1000000-0000-4000-8000-000000000001'::uuid THEN
    RAISE EXCEPTION 'The task assignment was not preserved when the subsequent archive committed.';
  END IF;
END
$assert_assignment_first$;
SQL

echo "Concurrency case 2: project completion locks the row before task assignment"
PGAPPNAME=personal-os-completion-first PGOPTIONS='-c lock_timeout=15s -c statement_timeout=20s' psql -X -v ON_ERROR_STOP=1 \
  -c "BEGIN ISOLATION LEVEL READ COMMITTED;
      UPDATE public.projects
         SET status = 'COMPLETED'
       WHERE id = 'd1000000-0000-4000-8000-000000000002';
      SELECT pg_sleep(2);
      COMMIT;" >"$tmpdir/completion-first.log" 2>&1 &
writer_a_pid=$!

if ! wait_for_sleep "personal-os-completion-first"; then
  cat "$tmpdir/completion-first.log"
  exit 1
fi

PGAPPNAME=personal-os-assignment-after-completion PGOPTIONS='-c lock_timeout=15s -c statement_timeout=20s' psql -X -v ON_ERROR_STOP=1 \
  -c "BEGIN ISOLATION LEVEL READ COMMITTED;
      UPDATE public.tasks
         SET project_id = 'd1000000-0000-4000-8000-000000000002'
       WHERE id = 'd2000000-0000-4000-8000-000000000002';
      COMMIT;" >"$tmpdir/assignment-after-completion.log" 2>&1 &
writer_b_pid=$!

if ! wait_for_blocker "personal-os-assignment-after-completion" "personal-os-completion-first"; then
  cat "$tmpdir/completion-first.log" "$tmpdir/assignment-after-completion.log"
  exit 1
fi

set +e
wait "$writer_a_pid"
writer_a_status=$?
wait "$writer_b_pid"
writer_b_status=$?
set -e
writer_a_pid=""
writer_b_pid=""

if [[ "$writer_a_status" -ne 0 ]]; then
  echo "Completion-first transaction unexpectedly failed."
  cat "$tmpdir/completion-first.log"
  exit 1
fi

if [[ "$writer_b_status" -eq 0 ]]; then
  echo "Task assignment committed after the project became COMPLETED."
  cat "$tmpdir/assignment-after-completion.log"
  exit 1
fi

if ! grep -Fq 'Tasks can only be linked to active projects.' "$tmpdir/assignment-after-completion.log"; then
  echo "Task assignment failed for an unexpected reason."
  cat "$tmpdir/assignment-after-completion.log"
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $assert_completion_first$
BEGIN
  IF (SELECT status FROM public.projects WHERE id = 'd1000000-0000-4000-8000-000000000002') <> 'COMPLETED' THEN
    RAISE EXCEPTION 'The project completion did not commit before the rejected assignment.';
  END IF;
  IF (SELECT project_id FROM public.tasks WHERE id = 'd2000000-0000-4000-8000-000000000002') IS NOT NULL THEN
    RAISE EXCEPTION 'The rejected task assignment left a project link behind.';
  END IF;
END
$assert_completion_first$;
SQL

remaining_sessions="$(psql -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name IN ('personal-os-assignment-first', 'personal-os-archive-after-assignment', 'personal-os-completion-first', 'personal-os-assignment-after-completion');")"
if [[ "$remaining_sessions" != "0" ]]; then
  echo "Expected both concurrency cases to terminate cleanly; found $remaining_sessions lingering sessions."
  exit 1
fi

echo "Project archive/completion and task assignment serialized correctly in both lock orders."

