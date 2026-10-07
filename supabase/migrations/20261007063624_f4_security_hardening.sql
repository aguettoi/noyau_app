begin;

-- These helpers are invoked internally by triggers/RPCs. They are not public
-- API surfaces and must not be callable directly by client roles.
revoke all on function public.assert_budget_run_approved_for_current_revision()
  from public, anon, authenticated;
revoke all on function public.budget_run_revision_hash(uuid, uuid)
  from public, anon, authenticated;

commit;
