-- Canonical, account-free distribution of the system envelope À répartir.
begin;

create or replace function public.assert_envelope_movement_group(
  p_movement_group_id uuid
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_household_id uuid; v_count integer; v_type text; v_event_id uuid;
  v_event_type text; v_transaction_id uuid; v_transaction_type text;
  v_transaction_amount numeric(14,2); v_total numeric(14,2);
  v_inflow numeric(14,2); v_outflow numeric(14,2); v_all_ordinary boolean;
  v_source_id uuid;
begin
  select household_id, count(*), min(movement_type) into v_household_id,v_count,v_type
  from public.envelope_movements where movement_group_id=p_movement_group_id group by household_id;
  if not found then return; end if;
  if exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and household_id<>v_household_id) then raise exception 'An envelope movement group cannot span households'; end if;
  select event_id,financial_transaction_id into v_event_id,v_transaction_id from public.envelope_movements where movement_group_id=p_movement_group_id limit 1;
  if exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and financial_transaction_id is distinct from v_transaction_id) then raise exception 'Envelope movement group must reference one financial transaction'; end if;
  if exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and event_id is distinct from v_event_id) then raise exception 'Envelope movement group must reference one FinancialEvent'; end if;
  select event_type into v_event_type from public.financial_events where id=v_event_id and household_id=v_household_id;
  if v_type in ('consumption','allocation','refund','adjustment','reversal') and exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type<>v_type) then raise exception 'Envelope movement group contains incompatible types'; end if;
  if v_type='consumption' then
    select type,amount into v_transaction_type,v_transaction_amount from public.financial_transactions where id=v_transaction_id and household_id=v_household_id;
    select sum(amount) into v_total from public.envelope_movements where movement_group_id=p_movement_group_id;
    if v_transaction_id is null or v_transaction_type<>'expense' or v_total<>v_transaction_amount then raise exception 'Expense envelope allocations must equal the expense amount'; end if;
  elsif v_type='allocation' then
    select type,amount into v_transaction_type,v_transaction_amount from public.financial_transactions where id=v_transaction_id and household_id=v_household_id;
    select sum(m.amount),bool_and(not e.is_system) into v_total,v_all_ordinary from public.envelope_movements m join public.envelopes e on e.id=m.envelope_id where m.movement_group_id=p_movement_group_id;
    if v_event_type='cash_income' then
      if v_transaction_id is null or v_transaction_type<>'income' or v_total<>v_transaction_amount then raise exception 'Income envelope allocations must equal the income amount'; end if;
    elsif v_event_type='budget_allocation' then
      if v_count<>1 or v_transaction_id is null or v_transaction_type<>'allocation' or v_total<>v_transaction_amount or not coalesce(v_all_ordinary,false) then raise exception 'Budget allocation must fund one ordinary destination envelope directly'; end if;
    else raise exception 'Allocation movements require a supported FinancialEvent type'; end if;
  elsif v_type in ('transfer_in','transfer_out') then
    select count(*),sum(case when direction='inflow' then amount else 0 end),sum(case when direction='outflow' then amount else 0 end) into v_count,v_inflow,v_outflow from public.envelope_movements where movement_group_id=p_movement_group_id;
    select envelope_id into v_source_id from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type='transfer_out';
    if v_count<2 or v_inflow<>v_outflow
      or (select count(*) from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type='transfer_in')<>v_count-1
      or (select count(*) from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type='transfer_out')<>1
      or exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type='transfer_in' and envelope_id=v_source_id)
      or (select count(distinct envelope_id) from public.envelope_movements where movement_group_id=p_movement_group_id)<>v_count then
      raise exception 'Envelope transfer must have one source and balanced distinct destinations';
    end if;
    if v_transaction_id is not null and not exists(select 1 from public.financial_transactions where id=v_transaction_id and household_id=v_household_id and type='allocation') then raise exception 'A ledger-backed envelope transfer must be a budget allocation'; end if;
  elsif v_type='reversal' and exists(select 1 from public.envelope_movements r join public.envelope_movements o on o.id=r.reversal_of where r.movement_group_id=p_movement_group_id and (o.household_id<>r.household_id or o.amount<>r.amount or o.direction=r.direction)) then
    raise exception 'Envelope reversal must invert one original movement exactly';
  end if;
end; $$;

create or replace function public.distribute_to_allocate_envelope_event(
  p_household_id uuid,
  p_occurred_at timestamptz,
  p_description text,
  p_destination_allocations jsonb,
  p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_event_id uuid; v_source_id uuid; v_available numeric(14,2); v_total numeric(14,2):=0;
  v_group_id uuid:=gen_random_uuid(); v_item jsonb; v_destination_id uuid; v_amount numeric(14,2);
  v_seen uuid[]:='{}';
begin
  v_event_id:=public.create_or_get_financial_event(p_household_id,'envelope_transfer',p_occurred_at,p_description,p_notes,p_idempotency_key);
  if exists(select 1 from public.envelope_movements where event_id=v_event_id) then return v_event_id; end if;
  if p_destination_allocations is null or jsonb_typeof(p_destination_allocations)<>'array' or jsonb_array_length(p_destination_allocations)=0 then raise exception 'At least one destination allocation is required'; end if;
  select id into v_source_id from public.envelopes where household_id=p_household_id and system_code='to_allocate' and is_system for update;
  if not found then raise exception 'System envelope À répartir is unavailable'; end if;
  for v_item in select value from jsonb_array_elements(p_destination_allocations) loop
    begin v_destination_id:=(v_item->>'envelope_id')::uuid; v_amount:=(v_item->>'amount')::numeric; exception when others then raise exception 'Each destination allocation requires a valid envelope and amount'; end;
    if v_amount is null or v_amount<=0 then raise exception 'Each destination amount must be positive'; end if;
    if v_destination_id=any(v_seen) then raise exception 'A destination envelope may appear only once'; end if;
    if not exists(select 1 from public.envelopes where id=v_destination_id and household_id=p_household_id and archived_at is null and not is_system) then raise exception 'Destination must be an active ordinary household envelope'; end if;
    v_seen:=array_append(v_seen,v_destination_id); v_total:=v_total+v_amount;
  end loop;
  select balance into v_available from public.envelope_ledger_balances where envelope_id=v_source_id and household_id=p_household_id;
  if coalesce(v_available,0)<v_total then raise exception 'Distribution exceeds available À répartir balance'; end if;
  insert into public.envelope_movements(household_id,event_id,envelope_id,movement_group_id,movement_type,direction,amount,occurred_at,description,created_by)
  values(p_household_id,v_event_id,v_source_id,v_group_id,'transfer_out','outflow',v_total,coalesce(p_occurred_at,now()),trim(p_description),auth.uid());
  insert into public.envelope_movements(household_id,event_id,envelope_id,movement_group_id,movement_type,direction,amount,occurred_at,description,created_by)
  select p_household_id,v_event_id,(value->>'envelope_id')::uuid,v_group_id,'transfer_in','inflow',(value->>'amount')::numeric,coalesce(p_occurred_at,now()),trim(p_description),auth.uid()
  from jsonb_array_elements(p_destination_allocations);
  return v_event_id;
end; $$;

revoke all on function public.distribute_to_allocate_envelope_event(uuid,timestamptz,text,jsonb,text,uuid) from public,anon;
grant execute on function public.distribute_to_allocate_envelope_event(uuid,timestamptz,text,jsonb,text,uuid) to authenticated;

commit;
