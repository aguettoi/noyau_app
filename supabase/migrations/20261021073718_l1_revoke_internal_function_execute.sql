-- Internal trigger/helper entrypoints must not be client RPCs. The trigger
-- owner and SECURITY DEFINER business functions retain their server calls.
revoke execute on function public.handle_new_user() from authenticated;
revoke execute on function public.assert_shopping_item_links(uuid,uuid,uuid)
  from authenticated;
