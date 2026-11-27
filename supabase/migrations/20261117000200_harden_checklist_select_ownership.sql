-- A checklist row must be visible only when both the row and its task belong
-- to the authenticated caller. This also hides malformed legacy rows that
-- survived in the compatibility table but were intentionally excluded from
-- canonical reconciliation.

DROP POLICY IF EXISTS checklist_items_select_own ON public.checklist_items;
CREATE POLICY checklist_items_select_own
  ON public.checklist_items
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.tasks AS t
      WHERE t.id = checklist_items.task_id
        AND t.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS task_checklist_items_select_own ON public.task_checklist_items;
CREATE POLICY task_checklist_items_select_own
  ON public.task_checklist_items
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.tasks AS t
      WHERE t.id = task_checklist_items.task_id
        AND t.user_id = (SELECT auth.uid())
    )
  );
