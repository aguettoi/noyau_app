-- Explicit role revocations keep the new SECURITY DEFINER RPCs off the anon API.
begin;

revoke all on function public.assert_shopping_item_links(uuid, uuid, uuid) from anon;
revoke all on function public.create_shopping_item(uuid, text, numeric, text, date, uuid, uuid, integer) from anon;
revoke all on function public.update_shopping_item(uuid, uuid, text, numeric, text, date, uuid, uuid, integer) from anon;
revoke all on function public.set_shopping_item_member_priority(uuid, uuid, uuid, integer) from anon;
revoke all on function public.cancel_shopping_item(uuid, uuid, text) from anon;
revoke all on function public.archive_shopping_item(uuid, uuid, text) from anon;

commit;
