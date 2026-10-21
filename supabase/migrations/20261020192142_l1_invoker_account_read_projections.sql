-- These four read-only RPCs select household tables whose account-linked
-- rows now have restrictive RLS. SECURITY DEFINER bypassed that boundary.
alter function public.envelope_account_initial_position_draft(uuid)
  security invoker;
alter function public.envelope_account_initial_position_preview(uuid)
  security invoker;
alter function public.envelope_account_initial_position_unknowns(uuid)
  security invoker;
alter function public.envelope_account_opening_history(uuid)
  security invoker;

revoke all on function
  public.envelope_account_initial_position_draft(uuid),
  public.envelope_account_initial_position_preview(uuid),
  public.envelope_account_initial_position_unknowns(uuid),
  public.envelope_account_opening_history(uuid)
  from public, anon, authenticated, service_role;
grant execute on function
  public.envelope_account_initial_position_draft(uuid),
  public.envelope_account_initial_position_preview(uuid),
  public.envelope_account_initial_position_unknowns(uuid),
  public.envelope_account_opening_history(uuid)
  to authenticated;
