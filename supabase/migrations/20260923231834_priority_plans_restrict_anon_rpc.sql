-- Explicitly remove the direct anon grants inherited by new RPC functions.
-- The public planning API is restricted to authenticated household members.
begin;

revoke all on function public.assert_priority_plan_source(uuid, uuid, uuid, uuid) from anon;
revoke all on function public.create_priority_plan(uuid, text, numeric, text) from anon;
revoke all on function public.update_priority_plan(uuid, uuid, text, numeric, text) from anon;
revoke all on function public.set_priority_plan_status(uuid, uuid, text) from anon;
revoke all on function public.add_priority_plan_item(uuid, uuid, uuid, uuid) from anon;
revoke all on function public.remove_priority_plan_item(uuid, uuid, uuid) from anon;
revoke all on function public.reorder_priority_plan_items(uuid, uuid, uuid[]) from anon;

commit;
