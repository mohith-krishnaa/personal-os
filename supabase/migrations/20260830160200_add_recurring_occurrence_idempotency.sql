-- Prevent concurrent completion requests from creating duplicate recurring occurrences.
create unique index if not exists tasks_recurring_occurrence_unique
  on public.tasks (user_id, recurrence_parent_id, due_at)
  where recurrence_parent_id is not null
    and recurrence_rule is not null
    and due_at is not null;
