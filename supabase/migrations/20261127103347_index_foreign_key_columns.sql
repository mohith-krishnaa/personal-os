-- Cover all referencing columns used by the Organization V1 reminder/task foreign keys.
-- Supabase's performance advisor reported these three foreign keys as unindexed.
CREATE INDEX IF NOT EXISTS notifications_reminder_owner_task_idx
  ON public.notifications (reminder_id, user_id, task_id);

CREATE INDEX IF NOT EXISTS notifications_task_id_idx
  ON public.notifications (task_id);

CREATE INDEX IF NOT EXISTS reminders_task_owner_idx
  ON public.reminders (task_id, user_id);

