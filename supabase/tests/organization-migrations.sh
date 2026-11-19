#!/usr/bin/env bash
set -euo pipefail

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export PGDATABASE="${PGDATABASE:-personal_os_migration_test}"

psql -X -v ON_ERROR_STOP=1 -c 'select 1' >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/organization-migration-bootstrap.sql

expected_migrations=18
actual_migrations="$(find supabase/migrations -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')"

if [[ "$actual_migrations" -ne "$expected_migrations" ]]; then
  echo "Expected $expected_migrations migration files, found $actual_migrations."
  exit 1
fi

applied_migrations=0
for migration in supabase/migrations/*.sql; do
  migration_name="$(basename "$migration")"
  echo "Replaying $migration_name"
  psql -X -v ON_ERROR_STOP=1 -f "$migration"
  applied_migrations=$((applied_migrations + 1))

  if [[ "$migration_name" == "20260905170100_organization_v1_checklists.sql" ]]; then
    echo "Seeding legacy projects and checklist rows before reconciliation"
    psql -X -v ON_ERROR_STOP=1 -f supabase/tests/organization-migration-seed-legacy-checklist.sql
  fi
done

if [[ "$applied_migrations" -ne "$expected_migrations" ]]; then
  echo "Applied $applied_migrations migrations; expected $expected_migrations."
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 -f supabase/tests/organization-migration-assertions.sql

echo "Executing read-only Organization rollout preflight against the replayed schema"
psql -X -v ON_ERROR_STOP=1 -f supabase/operations/organization-v1-preflight.sql >/dev/null

echo "Executing read-only checklist reconciliation conflict report"
conflict_report="$(psql -X -v ON_ERROR_STOP=1 -A -t -f supabase/operations/checklist-reconciliation-conflicts.sql)"
printf '%s\n' "$conflict_report"

if ! grep -Fq '30000000-0000-4000-8000-000000000002|task_owner_mismatch|' <<<"$conflict_report"; then
  echo "Checklist conflict report did not identify the legacy row linked to another owner's task."
  exit 1
fi

if ! grep -Fq '30000000-0000-4000-8000-000000000005|canonical_id_collision|' <<<"$conflict_report"; then
  echo "Checklist conflict report did not identify the non-identical canonical ID collision."
  exit 1
fi

reported_conflicts="$(printf '%s\n' "$conflict_report" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
if [[ "$reported_conflicts" -ne 2 ]]; then
  echo "Expected exactly two seeded checklist reconciliation conflicts, found $reported_conflicts."
  exit 1
fi
