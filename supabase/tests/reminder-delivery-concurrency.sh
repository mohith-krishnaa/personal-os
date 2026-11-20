#!/usr/bin/env bash
set -euo pipefail

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export PGDATABASE="${PGDATABASE:-personal_os_migration_test}"

reminder_id="85000000-0000-4000-8000-000000000001"
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
  psql -X -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL || true
DELETE FROM public.activity_events
WHERE event_type = 'REMINDER_DELIVERED' AND entity_id = '$reminder_id';
DELETE FROM public.notifications WHERE reminder_id = '$reminder_id';
DELETE FROM public.reminders WHERE id = '$reminder_id';
SQL
  rm -rf "$tmpdir"
}
trap cleanup EXIT

psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.reminders
    WHERE enabled = true AND delivered_at IS NULL AND remind_at <= now()
  ) THEN
    RAISE EXCEPTION 'Reminder concurrency fixture requires no pre-existing due reminders.';
  END IF;
END
$preflight$;

INSERT INTO public.reminders (id, user_id, task_id, remind_at)
VALUES (
  '85000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '10000000-0000-4000-8000-000000000001',
  now() - interval '1 minute'
);
SQL

PGAPPNAME=personal-os-reminder-claim-a PGOPTIONS='-c lock_timeout=15s -c statement_timeout=15s' \
  psql -X -Atq -v ON_ERROR_STOP=1 \
  -c "BEGIN ISOLATION LEVEL READ COMMITTED;
      SET ROLE service_role;
      SELECT count(*) FROM public.claim_due_reminders(100);
      RESET ROLE;
      SELECT pg_sleep(2);
      COMMIT;" >"$tmpdir/claim-a.log" 2>&1 &
writer_a_pid=$!

sleeping=0
for _ in $(seq 1 200); do
  sleeping="$(psql -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'personal-os-reminder-claim-a' AND state = 'active' AND query LIKE '%pg_sleep(2)%';")"
  if [[ "$sleeping" == "1" ]]; then break; fi
  if ! kill -0 "$writer_a_pid" 2>/dev/null; then break; fi
  sleep 0.05
done

if [[ "$sleeping" != "1" ]]; then
  echo "Worker A did not hold the claimed reminder lock during the expected sleep."
  cat "$tmpdir/claim-a.log"
  exit 1
fi

PGAPPNAME=personal-os-reminder-claim-b PGOPTIONS='-c lock_timeout=5s -c statement_timeout=5s' \
  psql -X -Atq -v ON_ERROR_STOP=1 \
  -c "SET ROLE service_role;
      SELECT count(*) FROM public.claim_due_reminders(100);
      RESET ROLE;" >"$tmpdir/claim-b.log" 2>&1 &
writer_b_pid=$!

finished=0
blocked=0
for _ in $(seq 1 200); do
  if ! kill -0 "$writer_b_pid" 2>/dev/null; then
    finished=1
    break
  fi
  blocked="$(psql -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'personal-os-reminder-claim-b' AND state = 'active' AND wait_event_type = 'Lock';")"
  if [[ "$blocked" != "0" ]]; then break; fi
  sleep 0.05
done

if [[ "$blocked" != "0" ]]; then
  echo "Worker B waited on a lock instead of skipping the reminder already claimed by Worker A."
  cat "$tmpdir/claim-a.log" "$tmpdir/claim-b.log"
  exit 1
fi

if [[ "$finished" != "1" ]]; then
  echo "Worker B did not finish while Worker A still held the reminder lock."
  cat "$tmpdir/claim-a.log" "$tmpdir/claim-b.log"
  exit 1
fi

set +e
wait "$writer_b_pid"
writer_b_status=$?
wait "$writer_a_pid"
writer_a_status=$?
set -e
writer_a_pid=""
writer_b_pid=""

if [[ "$writer_a_status" -ne 0 || "$writer_b_status" -ne 0 ]]; then
  echo "One of the concurrent reminder workers failed."
  cat "$tmpdir/claim-a.log" "$tmpdir/claim-b.log"
  exit 1
fi

claim_a_output="$(tr -d '\r\n ' <"$tmpdir/claim-a.log")"
claim_b_output="$(tr -d '\r\n ' <"$tmpdir/claim-b.log")"
if [[ "$claim_a_output" != "1" || "$claim_b_output" != "0" ]]; then
  echo "Expected Worker A to claim one reminder and Worker B to skip it; got A='$claim_a_output', B='$claim_b_output'."
  cat "$tmpdir/claim-a.log" "$tmpdir/claim-b.log"
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $assert_delivery$
DECLARE
  notification_count integer;
  event_count integer;
  delivered_at_value timestamptz;
BEGIN
  SELECT r.delivered_at INTO delivered_at_value
  FROM public.reminders r
  WHERE r.id = '85000000-0000-4000-8000-000000000001';
  SELECT count(*) INTO notification_count FROM public.notifications
  WHERE reminder_id = '85000000-0000-4000-8000-000000000001';
  SELECT count(*) INTO event_count FROM public.activity_events
  WHERE event_type = 'REMINDER_DELIVERED'
    AND entity_id = '85000000-0000-4000-8000-000000000001';

  IF delivered_at_value IS NULL OR notification_count <> 1 OR event_count <> 1 THEN
    RAISE EXCEPTION 'Concurrent workers did not produce exactly one delivery marker, notification, and activity event.';
  END IF;
END
$assert_delivery$;
SQL

repeat_output="$(psql -X -Atq -v ON_ERROR_STOP=1 -c "SET ROLE service_role; SELECT count(*) FROM public.claim_due_reminders(100); RESET ROLE;" | tr -d '\r\n ')"
if [[ "$repeat_output" != "0" ]]; then
  echo "A subsequent worker call reclaimed a delivered reminder: $repeat_output"
  exit 1
fi

remaining_sessions="$(psql -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name IN ('personal-os-reminder-claim-a', 'personal-os-reminder-claim-b');")"
if [[ "$remaining_sessions" != "0" ]]; then
  echo "Expected both reminder worker sessions to terminate; found $remaining_sessions."
  exit 1
fi

echo "Reminder delivery claims are atomic, idempotent, and skip rows locked by another worker."
