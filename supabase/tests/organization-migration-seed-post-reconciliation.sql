-- Simulate a valid legacy-client write after the one-time reconciliation migration.
-- The legacy table is retained, but no ongoing legacy-to-canonical sync trigger exists.
-- The read-only conflict report must identify this row as missing_canonical.
INSERT INTO public.task_checklist_items (
  id, user_id, task_id, title, is_completed, position
)
VALUES (
  '30000000-0000-4000-8000-000000000006',
  '11111111-1111-4111-8111-111111111111',
  '10000000-0000-4000-8000-000000000001',
  'Legacy-only write after reconciliation',
  false,
  5
);
