-- Authorization contract: internal helpers are not client RPCs.
begin;
do $$ begin
  if has_function_privilege('authenticated',
       'public.handle_new_user()','EXECUTE')
    or has_function_privilege('authenticated',
       'public.assert_shopping_item_links(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'L1 internal helper exposed to authenticated';
  end if;
  if not has_function_privilege('authenticated',
       'public.create_shopping_item_with_member_priorities(uuid,text,numeric,text,date,uuid,uuid,integer,jsonb)',
       'EXECUTE') then
    raise exception 'L1 canonical Shopping RPC lost client access';
  end if;
end $$;
rollback;
