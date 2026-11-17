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

INSERT INTO public.task_checklist_items (id, user_id, task_id, title, position)
VALUES
  ('30000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000001', 'Valid legacy item', 0),
  -- This malformed legacy association must not be copied to the canonical table.
  ('30000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '20000000-0000-4000-8000-000000000001', 'Foreign-task legacy item', 1);
