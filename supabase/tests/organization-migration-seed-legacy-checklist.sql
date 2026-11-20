-- Seed a legacy project/checklist state after the legacy checklist table exists
-- and before the reconciliation migration runs.
INSERT INTO auth.users (id, raw_user_meta_data)
VALUES
  ('11111111-1111-4111-8111-111111111111', '{"full_name":"Owner A"}'::jsonb),
  ('22222222-2222-4222-8222-222222222222', '{"full_name":"Owner B"}'::jsonb);

INSERT INTO public.projects (id, user_id, title, description, status, priority)
VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'Owner A legacy project', NULL, 'ACTIVE', 'MEDIUM'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', 'Owner B legacy project', NULL, 'ACTIVE', 'MEDIUM');

INSERT INTO public.tasks (id, user_id, project_id, title)
VALUES
  ('10000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Owner A task'),
  ('20000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Owner B task');

-- Pre-existing canonical record: the same UUID is used by a valid legacy
-- row owned by A. Reconciliation must preserve the canonical B record and
-- leave the legacy A row intact for explicit review.
INSERT INTO public.checklist_items (
  id, user_id, task_id, title, is_completed, position
)
VALUES (
  '30000000-0000-4000-8000-000000000005',
  '22222222-2222-4222-8222-222222222222',
  '20000000-0000-4000-8000-000000000001',
  'Pre-existing canonical record wins',
  true,
  9
);

-- Payload-only collision: same ID, owner, and task, but different checklist values.
-- The canonical row must win unchanged and the legacy source must remain for review.
INSERT INTO public.checklist_items (
  id, user_id, task_id, title, is_completed, position, created_at, updated_at
)
VALUES (
  '30000000-0000-4000-8000-000000000007',
  '11111111-1111-4111-8111-111111111111',
  '10000000-0000-4000-8000-000000000001',
  'Canonical payload wins',
  false,
  6,
  '2026-01-01 00:00:00+00',
  '2026-01-02 00:00:00+00'
);

INSERT INTO public.task_checklist_items (id, user_id, task_id, title, is_completed, position)
VALUES
  ('30000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000001', 'Valid legacy item', false, 0),
  -- This malformed legacy association must not be copied to the canonical table.
  ('30000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '20000000-0000-4000-8000-000000000001', 'Foreign-task legacy item', false, 1),
  ('30000000-0000-4000-8000-000000000003', '22222222-2222-4222-8222-222222222222', '20000000-0000-4000-8000-000000000001', 'Owner B valid legacy item', false, 0),
  -- Same ID, different owner/task: ON CONFLICT must not overwrite the canonical row.
  ('30000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000001', 'Legacy record with colliding ID', false, 4);

-- Same owner/task and ID, but a different payload: preserve both sides for review.
INSERT INTO public.task_checklist_items (
  id, user_id, task_id, title, is_completed, position, created_at, updated_at
)
VALUES (
  '30000000-0000-4000-8000-000000000007',
  '11111111-1111-4111-8111-111111111111',
  '10000000-0000-4000-8000-000000000001',
  'Legacy payload differs',
  true,
  7,
  '2026-01-01 00:00:00+00',
  '2026-01-02 00:00:00+00'
);
