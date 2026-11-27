create or replace function public.claim_due_reminders(p_limit integer default 100)
returns table(id uuid, user_id uuid, task_id uuid, remind_at timestamptz, channel text)
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select rm.id, rm.user_id, rm.task_id, rm.remind_at, rm.channel
    from public.reminders rm
    where rm.enabled = true
      and rm.delivered_at is null
      and rm.remind_at <= now()
    order by rm.remind_at asc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
    for update of rm skip locked
  loop
    update public.reminders
      set delivered_at = now(), updated_at = now()
      where reminders.id = r.id;

    insert into public.activity_events (user_id, event_type, entity_type, entity_id, metadata)
    values (
      r.user_id,
      'REMINDER_DELIVERED',
      'REMINDER',
      r.id,
      jsonb_build_object('task_id', r.task_id, 'channel', r.channel)
    );

    id := r.id;
    user_id := r.user_id;
    task_id := r.task_id;
    remind_at := r.remind_at;
    channel := r.channel;
    return next;
  end loop;
end;
$$;

revoke execute on function public.claim_due_reminders(integer) from public, anon, authenticated;
grant execute on function public.claim_due_reminders(integer) to service_role;
