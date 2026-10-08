-- F6 hardening: the task completion function is security definer so that the
-- append-only occurrence and the task transition remain atomic. Keep it out
-- of PUBLIC/anon and expose it only to authenticated callers; the function
-- itself still validates auth.uid() and household membership.
revoke all on function public.complete_household_task(uuid,text,text,uuid)
  from public, anon;
grant execute on function public.complete_household_task(uuid,text,text,uuid)
  to authenticated;

create index if not exists household_tasks_household_due_idx
  on public.household_tasks(household_id, due_date, id);

create index if not exists household_task_occurrences_task_acted_idx
  on public.household_task_occurrences(task_id, acted_at desc, id);
