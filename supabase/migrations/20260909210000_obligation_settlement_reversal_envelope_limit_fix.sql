begin;

-- Qualify the source movement amount.  In the cumulative-reversal check both
-- sides of the join expose an `amount` column; leaving it unqualified makes
-- an otherwise valid partial income/recovery settlement reversal fail.
create or replace function public.reverse_obligation_settlement_event(
  p_household_id uuid,p_source_settlement_id uuid,p_occurred_at timestamptz,
  p_amount numeric,p_reason text,p_notes text,p_idempotency_key uuid,
  p_expected_kind text,p_envelope_reversals jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_event_id uuid; v_tx_id uuid; v_obligation_id uuid; v_source_amount numeric(14,2);
  v_source_event_id uuid; v_source_tx_id uuid; v_account_id uuid; v_reversible numeric(14,2);
  v_event_type text; v_debt_id uuid; v_receivable_id uuid; v_group_id uuid:=gen_random_uuid();
  v_item jsonb; v_movement_id uuid; v_movement_amount numeric(14,2); v_total numeric(14,2):=0;
  v_original_envelope_id uuid; v_original_direction text; v_seen uuid[]:='{}';
begin
  if p_amount is null or p_amount<=0 then raise exception 'A positive reversal amount is required'; end if;
  if char_length(trim(coalesce(p_reason,'')))=0 then raise exception 'A reversal reason is required'; end if;
  v_event_type:=case p_expected_kind when 'debt' then 'debt_settlement_reversal' when 'income' then 'receivable_settlement_reversal' when 'recovery' then 'recovery_settlement_reversal' else null end;
  if v_event_type is null then raise exception 'Unsupported settlement reversal'; end if;
  v_event_id:=public.create_or_get_financial_event(p_household_id,v_event_type,p_occurred_at,'Annulation : '||trim(p_reason),p_notes,p_idempotency_key);
  if exists(select 1 from public.obligation_settlement_reversals where financial_event_id=v_event_id) then return v_event_id; end if;
  perform public.assert_household_access(p_household_id);
  select s.obligation_id,s.amount,s.event_id,s.financial_transaction_id into v_obligation_id,v_source_amount,v_source_event_id,v_source_tx_id from public.obligation_settlements s join public.obligations o on o.id=s.obligation_id and o.household_id=s.household_id where s.id=p_source_settlement_id and s.household_id=p_household_id for update of s,o;
  if not found then raise exception 'Settlement not found'; end if;
  select v_source_amount-coalesce(sum(r.amount),0) into v_reversible from public.obligation_settlement_reversals r where r.source_settlement_id=p_source_settlement_id;
  if p_amount>v_reversible then raise exception 'Reversal amount exceeds the remaining reversible settlement'; end if;
  if p_expected_kind='debt' then
    select d.id into v_debt_id from public.debts d where d.obligation_id=v_obligation_id and d.household_id=p_household_id;
    if not found then raise exception 'Settlement does not belong to a debt'; end if;
    select source_account_id into v_account_id from public.financial_transactions where id=v_source_tx_id;
    perform public.assert_financial_event_ordinary_account(p_household_id,v_account_id);
    v_debt_id:=public.ensure_financial_event_system_account(p_household_id,'debt');
    v_tx_id:=public.insert_financial_event_ledger_transaction(p_household_id,v_event_id,'debt_settlement_reversal',p_occurred_at,'Annulation règlement : '||trim(p_reason),p_amount,v_debt_id,v_account_id,v_debt_id,v_account_id,p_notes);
  else
    if p_expected_kind='income' then
      if not exists(select 1 from public.receivables r where r.obligation_id=v_obligation_id and r.household_id=p_household_id and r.receivable_kind='income') then raise exception 'Settlement does not belong to an income receivable'; end if;
    elsif not exists(select 1 from public.receivables r where r.obligation_id=v_obligation_id and r.household_id=p_household_id and r.receivable_kind='recovery') then raise exception 'Settlement does not belong to a recovery receivable'; end if;
    select destination_account_id into v_account_id from public.financial_transactions where id=v_source_tx_id;
    perform public.assert_financial_event_ordinary_account(p_household_id,v_account_id);
    v_receivable_id:=public.ensure_financial_event_system_account(p_household_id,'receivable');
    v_tx_id:=public.insert_financial_event_ledger_transaction(p_household_id,v_event_id,case when p_expected_kind='income' then 'receivable_settlement_reversal' else 'recovery_settlement_reversal' end,p_occurred_at,'Annulation encaissement : '||trim(p_reason),p_amount,v_account_id,null,v_receivable_id,v_account_id,p_notes);
  end if;
  if p_expected_kind='income' then
    if p_envelope_reversals is null or jsonb_typeof(p_envelope_reversals)<>'array' then raise exception 'Income reversal allocations must be an array'; end if;
    for v_item in select value from jsonb_array_elements(p_envelope_reversals) loop
      begin v_movement_id:=nullif(v_item->>'source_movement_id','')::uuid; v_movement_amount:=nullif(v_item->>'amount','')::numeric; exception when others then raise exception 'Each income reversal requires a source movement and amount'; end;
      if v_movement_id is null or v_movement_amount is null or v_movement_amount<=0 or v_movement_id=any(v_seen) then raise exception 'Each income reversal source must be unique with a positive amount'; end if;
      select envelope_id,direction into v_original_envelope_id,v_original_direction from public.envelope_movements where id=v_movement_id and household_id=p_household_id and event_id=v_source_event_id and movement_type='allocation' for update;
      if not found or v_original_direction<>'inflow' then raise exception 'Income reversal source movement does not belong to the source settlement'; end if;
      if v_movement_amount>(select m.amount-coalesce(sum(r.amount),0) from public.envelope_movements m left join public.envelope_movements r on r.reversal_of=m.id where m.id=v_movement_id group by m.amount) then raise exception 'Income reversal exceeds source envelope movement'; end if;
      insert into public.envelope_movements(household_id,event_id,financial_transaction_id,envelope_id,movement_group_id,movement_type,direction,amount,occurred_at,description,reversal_of,created_by) values(p_household_id,v_event_id,v_tx_id,v_original_envelope_id,v_group_id,'reversal','outflow',v_movement_amount,coalesce(p_occurred_at,now()),'Annulation encaissement : '||trim(p_reason),v_movement_id,auth.uid());
      v_seen:=array_append(v_seen,v_movement_id); v_total:=v_total+v_movement_amount;
    end loop;
    if v_total<>p_amount then raise exception 'Income reversal envelope allocations must equal the reversal amount'; end if;
  elsif p_expected_kind='recovery' then
    select id,envelope_id,direction into v_movement_id,v_original_envelope_id,v_original_direction from public.envelope_movements where household_id=p_household_id and event_id=v_source_event_id and movement_type='refund' for update;
    if not found or v_original_direction<>'inflow' then raise exception 'Recovery settlement has no source envelope refund'; end if;
    if p_amount>(select m.amount-coalesce(sum(r.amount),0) from public.envelope_movements m left join public.envelope_movements r on r.reversal_of=m.id where m.id=v_movement_id group by m.amount) then raise exception 'Recovery reversal exceeds source envelope refund'; end if;
    insert into public.envelope_movements(household_id,event_id,financial_transaction_id,envelope_id,movement_group_id,movement_type,direction,amount,occurred_at,description,reversal_of,created_by) values(p_household_id,v_event_id,v_tx_id,v_original_envelope_id,v_group_id,'reversal','outflow',p_amount,coalesce(p_occurred_at,now()),'Annulation remboursement : '||trim(p_reason),v_movement_id,auth.uid());
  end if;
  insert into public.obligation_settlement_reversals(household_id,obligation_id,source_settlement_id,financial_event_id,financial_transaction_id,amount,occurred_at,reason,notes,created_by) values(p_household_id,v_obligation_id,p_source_settlement_id,v_event_id,v_tx_id,p_amount,coalesce(p_occurred_at,now()),trim(p_reason),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  return v_event_id;
end; $$;

commit;
