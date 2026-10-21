-- L1 is not certified across all derived/SECURITY DEFINER outputs yet.
-- Keep the model and read-boundary testable, but prevent a household from
-- activating a mode that other routes could still disclose. An additive
-- certification migration will re-grant these RPCs after the hostile matrix.
revoke execute on function public.request_account_privacy_change(uuid,text),
  public.decide_account_privacy_change(uuid,text),
  public.cancel_account_privacy_change(uuid)
  from authenticated;
