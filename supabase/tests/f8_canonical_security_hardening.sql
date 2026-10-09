begin;

do $$
declare
  v_function regprocedure;
begin
  foreach v_function in array array[
    'public.create_financial_transaction_with_envelopes(uuid,text,timestamptz,text,numeric,uuid,uuid,uuid,text,text,jsonb)'::regprocedure,
    'public.create_envelope_transfer(uuid,uuid,uuid,numeric,timestamptz,text)'::regprocedure,
    'public.execute_accounts_import(uuid,uuid,jsonb)'::regprocedure,
    'public.import_household_envelopes(uuid,jsonb,uuid)'::regprocedure
  ] loop
    if has_function_privilege('authenticated', v_function, 'execute') then
      raise exception 'Legacy RPC remains executable: %', v_function;
    end if;
    if has_function_privilege('anon', v_function, 'execute') then
      raise exception 'Anonymous role can execute: %', v_function;
    end if;
  end loop;
end;
$$;

do $$
begin
  if has_table_privilege('authenticated', 'public.financial_events', 'insert')
     or has_table_privilege('authenticated', 'public.financial_transactions', 'update')
     or has_table_privilege('authenticated', 'public.envelope_movements', 'delete') then
    raise exception 'A canonical ledger still accepts direct client DML';
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.accounts'::regclass
      and tgname = 'accounts_opening_balance_legacy_guard'
      and not tgisinternal
  ) then
    raise exception 'Opening balance immutability trigger is missing';
  end if;
end;
$$;

rollback;
