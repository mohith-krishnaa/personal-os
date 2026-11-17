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
  if [[ -n "$writer_a_pid" ]]; then kill "$writer_a_pid" 2>/dev/null || true; fi
  if [[ -n "$writer_b_pid" ]]; then kill "$writer_b_pid" 2>/dev/null || true; fi
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
