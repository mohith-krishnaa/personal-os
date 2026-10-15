-- Prevent indirect task hierarchy cycles, not just direct self-parenting.
-- A cycle would make recursive task traversal and hierarchy display unsafe.
create or replace function public.validate_task_organization_links()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  parent_user uuid;
  parent_project uuid;
  project_user uuid;
  creates_cycle boolean;
begin
  if new.parent_task_id is not null then
    if new.parent_task_id = new.id then
      raise exception 'A task cannot be its own parent.' using errcode = '23514';
    end if;

    select user_id, project_id into parent_user, parent_project
      from public.tasks where id = new.parent_task_id;

    if parent_user is null or parent_user <> new.user_id then
      raise exception 'Parent task must belong to the same user.' using errcode = '42501';
    end if;

    if new.project_id is distinct from parent_project then
      raise exception 'Subtask must belong to the same project as its parent.' using errcode = '23514';
    end if;

    with recursive ancestors(id, parent_task_id) as (
      select id, parent_task_id
        from public.tasks
       where id = new.parent_task_id
         and user_id = new.user_id
      union
      select parent.id, parent.parent_task_id
        from public.tasks as parent
        join ancestors as child on parent.id = child.parent_task_id
       where parent.user_id = new.user_id
    )
    select exists(select 1 from ancestors where id = new.id)
      into creates_cycle;

    if creates_cycle then
      raise exception 'Task hierarchy cannot contain cycles.' using errcode = '23514';
    end if;
  end if;

  if new.project_id is not null then
    select user_id into project_user from public.projects where id = new.project_id;
    if project_user is null or project_user <> new.user_id then
      raise exception 'Project must belong to the same user as the task.' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;
