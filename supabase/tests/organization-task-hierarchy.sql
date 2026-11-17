-- Focused PostgreSQL integration fixture for the Organization task-link trigger.
-- Run only against a disposable database. The CI workflow provisions PostgreSQL 17.
\set ON_ERROR_STOP on

create table public.projects (
  id uuid primary key,
  user_id uuid not null
);

create table public.tasks (
  id uuid primary key,
  user_id uuid not null,
  project_id uuid references public.projects(id),
  parent_task_id uuid references public.tasks(id) on delete cascade
);

\ir ../migrations/20261015000300_prevent_task_hierarchy_cycles.sql

create trigger validate_task_organization_links
before insert or update of user_id, project_id, parent_task_id on public.tasks
for each row execute function public.validate_task_organization_links();

insert into public.projects (id, user_id) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '11111111-1111-4111-8111-111111111111'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '22222222-2222-4222-8222-222222222222');

insert into public.tasks (id, user_id, project_id) values
  ('10000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  ('10000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  ('10000000-0000-4000-8000-000000000003', '22222222-2222-4222-8222-222222222222', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  ('10000000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  ('10000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  ('10000000-0000-4000-8000-000000000006', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  ('10000000-0000-4000-8000-000000000007', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

-- Valid same-owner, same-project parent/child relationship.
insert into public.tasks (id, user_id, project_id, parent_task_id) values
  ('10000000-0000-4000-8000-000000000008', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000001');

-- Direct self-parenting must be rejected.
do $$
begin
  begin
    insert into public.tasks (id, user_id, project_id, parent_task_id) values
      ('10000000-0000-4000-8000-000000000009', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000009');
    raise exception 'Expected direct self-parenting to be rejected.';
  exception when check_violation then
    null;
  end;
end;
$$;

-- A parent owned by another user must be rejected.
do $$
begin
  begin
    insert into public.tasks (id, user_id, project_id, parent_task_id) values
      ('10000000-0000-4000-8000-000000000010', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000003');
    raise exception 'Expected a foreign-owned parent to be rejected.';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

-- A parent in a different project must be rejected.
do $$
begin
  begin
    insert into public.tasks (id, user_id, project_id, parent_task_id) values
      ('10000000-0000-4000-8000-000000000011', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000002');
    raise exception 'Expected a cross-project parent to be rejected.';
  exception when check_violation then
    null;
  end;
end;
$$;

-- A project owned by another user must be rejected.
do $$
begin
  begin
    insert into public.tasks (id, user_id, project_id) values
      ('10000000-0000-4000-8000-000000000012', '11111111-1111-4111-8111-111111111111', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    raise exception 'Expected a foreign-owned project to be rejected.';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

-- An ordinary two-node cycle must be rejected even without concurrent writers.
update public.tasks
   set parent_task_id = '10000000-0000-4000-8000-000000000005'
 where id = '10000000-0000-4000-8000-000000000004';

do $$
begin
  begin
    update public.tasks
       set parent_task_id = '10000000-0000-4000-8000-000000000004'
     where id = '10000000-0000-4000-8000-000000000005';
    raise exception 'Expected an indirect hierarchy cycle to be rejected.';
  exception when check_violation then
    null;
  end;
end;
$$;

-- A parent cannot move projects while it has children in the old project.
do $
begin
  begin
    update public.tasks
       set project_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
     where id = '10000000-0000-4000-8000-000000000001';
    raise exception 'Expected a parent project change to be rejected while children exist.';
  exception when check_violation then
    null;
  end;
end;
$;

-- A parent cannot change owners while existing children remain with the old owner.
do $
begin
  begin
    update public.tasks
       set user_id = '22222222-2222-4222-8222-222222222222',
           project_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
     where id = '10000000-0000-4000-8000-000000000001';
    raise exception 'Expected a parent owner change to be rejected while children exist.';
  exception when check_violation then
    null;
  end;
end;
$;

-- Rows 6 and 7 remain roots for the two-session concurrency test.
select 'organization hierarchy trigger fixture ready' as result;
