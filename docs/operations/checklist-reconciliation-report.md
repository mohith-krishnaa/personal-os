# Checklist reconciliation report: determinism and repeatability

## Scope

`supabase/operations/checklist-reconciliation-conflicts.sql` is a read-only snapshot report for the retained legacy table `public.task_checklist_items` and canonical table `public.checklist_items`. Run it only after both tables and the Organization checklist migrations exist, preferably against a complete isolated restoration.

The report joins each legacy row to its task by the task primary key and to the canonical row by checklist primary key. Those keys are unique, so a fixed database snapshot yields at most one report row per legacy checklist ID. The final `ORDER BY legacy.id` gives a stable row order for that snapshot. Classification priority is:

1. `missing_task`
2. `task_owner_mismatch`
3. `missing_canonical`
4. `canonical_id_collision`

`canonical_id_collision` is intentionally an umbrella category. Use the owner, task, payload and per-field mismatch flags plus the side-by-side values to distinguish the conflict shape. The report does not choose a winner or modify either table.

## Reconciliation migration repeatability

`20261015000200_reconcile_checklist_tables.sql` copies only legacy rows whose task belongs to the same owner and uses `ON CONFLICT (id) DO NOTHING`. With an unchanged source snapshot, reapplying it must leave both tables byte-for-byte equivalent at the row-value level. The Organization migration test runner captures ordered JSONB snapshots of both tables, reapplies the migration, and requires the snapshots to match.

This is not an ongoing synchronization mechanism. A valid legacy row inserted after the original reconciliation is newly eligible if the migration is manually rerun later; rerunning the migration can therefore copy that new row into the canonical table. Do not use migration reapplication as an automatic catch-up job. The report identifies such rows as `missing_canonical` so an owner can review and disposition them.

## Regression checks

The disposable PostgreSQL migration runner now verifies that:

- Reapplying the reconciliation migration with unchanged source rows leaves canonical and legacy row snapshots unchanged.
- The conflict report executes inside a `BEGIN READ ONLY` transaction.
- Two executions against the same fixture snapshot return identical output.
- Report execution leaves both tables unchanged.
- The exact seeded conflict IDs and classifications are returned in ascending legacy-ID order.
- Existing cross-owner/task and payload-only collision values and mismatch flags remain visible.
- A valid post-reconciliation legacy write remains reported as `missing_canonical`.

These checks do not establish production state or resolve real restored-copy conflicts. Owner review of the report on the restored isolated copy remains an Organization V1 acceptance requirement.
