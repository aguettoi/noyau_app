-- Month-close read projections must inherit caller RLS. In particular,
-- private accounts/reconciliations must not enter account counts or todo
-- labels through the former SECURITY DEFINER bypass.
alter function public.monthly_close_snapshot(uuid,date) security invoker;
alter function public.monthly_close_todo_items(uuid,date) security invoker;
alter function public.monthly_close_automatic_target_preview(uuid,date)
  security invoker;
alter function public.monthly_savings_sweep_preview(uuid,date)
  security invoker;

revoke all on function public.monthly_close_snapshot(uuid,date),
  public.monthly_close_todo_items(uuid,date),
  public.monthly_close_automatic_target_preview(uuid,date),
  public.monthly_savings_sweep_preview(uuid,date)
  from public, anon, authenticated, service_role;
grant execute on function public.monthly_close_snapshot(uuid,date),
  public.monthly_close_todo_items(uuid,date),
  public.monthly_close_automatic_target_preview(uuid,date),
  public.monthly_savings_sweep_preview(uuid,date)
  to authenticated;
