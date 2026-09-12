begin;

-- Obligations are the canonical persistence model for debts and receivables.
-- Replace the obsolete table aliases left in the first reversal function body.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.reverse_obligation_settlement_event(uuid,uuid,timestamptz,numeric,text,text,uuid,text,jsonb)'::regprocedure
  ) into v_definition;

  v_definition := replace(
    v_definition,
    'select d.id into v_debt_id from public.debts d where d.obligation_id=v_obligation_id and d.household_id=p_household_id;',
    'perform 1 from public.obligations o where o.id=v_obligation_id and o.household_id=p_household_id and o.obligation_kind=''debt'';'
  );
  v_definition := replace(
    v_definition,
    'if not exists(select 1 from public.receivables r where r.obligation_id=v_obligation_id and r.household_id=p_household_id and r.receivable_kind=''income'') then raise exception ''Settlement does not belong to an income receivable''; end if;',
    'if not exists(select 1 from public.obligations o where o.id=v_obligation_id and o.household_id=p_household_id and o.obligation_kind=''receivable'' and o.receivable_kind=''income'') then raise exception ''Settlement does not belong to an income receivable''; end if;'
  );
  v_definition := replace(
    v_definition,
    'elsif not exists(select 1 from public.receivables r where r.obligation_id=v_obligation_id and r.household_id=p_household_id and r.receivable_kind=''recovery'') then raise exception ''Settlement does not belong to a recovery receivable''; end if;',
    'elsif not exists(select 1 from public.obligations o where o.id=v_obligation_id and o.household_id=p_household_id and o.obligation_kind=''receivable'' and o.receivable_kind=''recovery'') then raise exception ''Settlement does not belong to a recovery receivable''; end if;'
  );

  if position('public.debts' in v_definition) > 0
     or position('public.receivables' in v_definition) > 0 then
    raise exception 'Unable to patch obsolete settlement reversal obligation references';
  end if;

  execute v_definition;
end;
$$;

commit;
