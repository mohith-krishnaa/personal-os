-- Forward-only compatibility migration for Organization V1.
-- Preserve the live legacy project schema while remaining safe on fresh installs.
-- Some installations use projects.title; newer installs use projects.name.
-- Do not drop legacy columns or narrow the existing status vocabulary.

alter table public.projects
  add column if not exists name text;

do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'projects' and column_name = 'title'
  ) then
    execute 'update public.projects set name = title where name is null';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.projects'::regclass
       and conname = 'projects_name_length_check'
  ) then
    alter table public.projects
      add constraint projects_name_length_check
      check (char_length(trim(name)) between 1 and 120) not valid;
  end if;
end $$;

alter table public.projects
  validate constraint projects_name_length_check;

alter table public.projects
  alter column name set not null;

create index if not exists projects_user_id_idx
  on public.projects(user_id);

-- Install the dual-write trigger only where the legacy title column exists.
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'projects' and column_name = 'title'
  ) then
    execute $function$
      create or replace function public.sync_project_name_title()
      returns trigger
      language plpgsql
      set search_path = public
      as $body$
      begin
        if tg_op = 'INSERT' then
          if new.name is null or trim(new.name) = '' then
            new.name := new.title;
          else
            new.title := new.name;
          end if;
        elsif new.name is distinct from old.name then
          new.title := new.name;
        elsif new.title is distinct from old.title then
          new.name := new.title;
        end if;

        if new.name is null or char_length(trim(new.name)) not between 1 and 120 then
          raise exception 'Project name must be between 1 and 120 characters.'
            using errcode = '23514';
        end if;

        return new;
      end;
      $body$;
    $function$;

    drop trigger if exists sync_project_name_title on public.projects;
    create trigger sync_project_name_title
    before insert or update of name, title on public.projects
    for each row execute function public.sync_project_name_title();
  end if;
end $$;

-- Keep existing COMPLETED statuses valid for older clients.
-- Organization V1 only writes ACTIVE or ARCHIVED, which are already supported.
