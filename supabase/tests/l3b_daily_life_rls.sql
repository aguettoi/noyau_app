begin;
do $$
declare v_definition text;
begin
  if not (select relrowsecurity from pg_class where oid='public.household_grocery_items'::regclass)
     or not (select relrowsecurity from pg_class where oid='public.household_home_records'::regclass)
     or not (select relrowsecurity from pg_class where oid='public.member_cycle_events'::regclass)
     or not (select relrowsecurity from pg_class where oid='public.member_cycle_calendar_shares'::regclass) then
    raise exception 'L3B RLS must remain enabled';
  end if;
  if has_table_privilege('anon','public.member_cycle_events','select')
     or has_table_privilege('anon','public.household_grocery_items','select') then
    raise exception 'L3B anon table access';
  end if;
  if not has_function_privilege('authenticated','public.read_shared_cycle_calendar(uuid)','execute')
     or has_function_privilege('anon','public.read_shared_cycle_calendar(uuid)','execute') then
    raise exception 'L3B shared calendar RPC audience';
  end if;
  select pg_get_functiondef('public.read_shared_cycle_calendar(uuid)'::regprocedure) into v_definition;
  if position('notes' in v_definition)>0 or position('symptoms' in v_definition)>0
     or position('flow' in v_definition)>0 then
    raise exception 'L3B shared calendar exposes private detail';
  end if;
  if exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
    and tablename in ('household_grocery_items','household_home_records',
      'member_cycle_events','member_cycle_calendar_shares')) then
    raise exception 'L3B raw Realtime payload exposed';
  end if;
end $$;
select 'PASS: L3B RLS, RPC audience, minimal cycle projection and redacted Realtime' as certification;
rollback;

