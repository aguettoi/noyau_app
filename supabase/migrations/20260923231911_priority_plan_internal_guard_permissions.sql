-- The source guard is an implementation detail of the mutation RPCs.
-- It must not be callable from the Data API.
begin;

revoke all on function public.assert_priority_plan_source(uuid, uuid, uuid, uuid)
  from anon, authenticated;

commit;
