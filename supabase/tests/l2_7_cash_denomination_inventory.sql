begin;

do $$
begin
  if not (select relrowsecurity from pg_class where oid='public.cash_denominations'::regclass) then
    raise exception 'cash denomination catalogue must have RLS enabled';
  end if;
  if has_table_privilege('anon','public.cash_denominations','select')
     or has_table_privilege('authenticated','public.cash_denominations','select') then
    raise exception 'cash denomination catalogue must remain server-internal';
  end if;
  if has_function_privilege(
       'anon',
       'public.record_cash_inventory_observation(uuid,timestamptz,text,numeric,jsonb,text,uuid)',
       'execute'
     ) then
    raise exception 'anon must not record a cash inventory';
  end if;
  if not has_function_privilege(
       'authenticated',
       'public.record_cash_inventory_observation(uuid,timestamptz,text,numeric,jsonb,text,uuid)',
       'execute'
     ) then
    raise exception 'authenticated inventory RPC grant is missing';
  end if;
  if not exists (
    select 1
    from pg_indexes
    where schemaname='public'
      and tablename='account_balance_observations'
      and indexname='account_balance_observations_idempotency_idx'
  ) then
    raise exception 'cash inventory idempotency index is missing';
  end if;
  if (select count(*) from public.cash_denominations where currency_code='MAD' and active) <> 11 then
    raise exception 'MAD cash denomination catalogue is incomplete';
  end if;
end $$;

rollback;
select 'PASS: L2.7 canonical observations, private denomination catalogue and explicit RPC audience' as certification;
