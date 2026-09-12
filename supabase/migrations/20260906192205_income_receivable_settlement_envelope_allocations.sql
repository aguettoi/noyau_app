-- Canonical budget allocation for an income receivable settlement.
-- The income is recognised when the receivable is created.  This migration
-- only routes newly received liquidity to envelopes without recognising it
-- a second time.
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
    if v_transaction_id is null or v_transaction_type not in ('expense','debt_expense') or v_total<>v_transaction_amount then raise exception 'Expense envelope allocations must equal the expense amount'; end if;
  elsif v_type='allocation' then
    select type,amount into v_transaction_type,v_transaction_amount from public.financial_transactions where id=v_transaction_id and household_id=v_household_id;
    select sum(m.amount),bool_and(not e.is_system) into v_total,v_all_ordinary from public.envelope_movements m join public.envelopes e on e.id=m.envelope_id where m.movement_group_id=p_movement_group_id;
    if v_event_type='cash_income' then
      if v_transaction_id is null or v_transaction_type<>'income' or v_total<>v_transaction_amount then raise exception 'Income envelope allocations must equal the income amount'; end if;
    elsif v_event_type='receivable_settlement' then
      if v_transaction_id is null or v_transaction_type<>'receivable_settlement' or v_total<>v_transaction_amount then raise exception 'Receivable settlement envelope allocations must equal the settlement amount'; end if;
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

-- The allocation parameter is appended so older positional callers retain
-- their exact signature semantics and default to the system envelope.
drop function if exists public.settle_receivable_event(
  uuid, uuid, timestamptz, text, numeric, uuid, text, uuid
);

create function public.settle_receivable_event(
  p_household_id uuid,
  p_obligation_id uuid,
  p_occurred_at timestamptz,
  p_description text,
  p_amount numeric,
  p_destination_account_id uuid,
  p_notes text default null,
  p_idempotency_key uuid default null,
  p_envelope_allocations jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_event_id uuid; v_transaction_id uuid; v_receivable_id uuid;
  v_remaining numeric; v_kind text; v_group_id uuid := gen_random_uuid();
  v_item jsonb; v_envelope_id uuid; v_allocation_amount numeric(14,2);
  v_allocated_total numeric(14,2) := 0; v_remainder numeric(14,2);
  v_to_allocate_envelope_id uuid; v_seen uuid[] := '{}';
begin
  v_event_id := public.create_or_get_financial_event(
    p_household_id, 'receivable_settlement', p_occurred_at,
    p_description, p_notes, p_idempotency_key
  );
  if exists (select 1 from public.obligation_settlements where event_id = v_event_id) then return v_event_id; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_destination_account_id);
  select receivable_kind into v_kind from public.obligations
  where id = p_obligation_id and household_id = p_household_id and obligation_kind = 'receivable' for update;
  if not found or v_kind <> 'income' then raise exception 'Open income receivable does not belong to household'; end if;
  select remaining_amount into v_remaining from public.obligation_balances
  where obligation_id = p_obligation_id and household_id = p_household_id;
  if p_amount is null or p_amount <= 0 or p_amount > v_remaining then raise exception 'Settlement amount exceeds remaining receivable'; end if;
  if p_envelope_allocations is null or jsonb_typeof(p_envelope_allocations) <> 'array' then raise exception 'Receivable envelope allocations must be an array'; end if;
  for v_item in select value from jsonb_array_elements(p_envelope_allocations) loop
    begin
      v_envelope_id := nullif(v_item ->> 'envelope_id', '')::uuid;
      v_allocation_amount := nullif(v_item ->> 'amount', '')::numeric;
    exception when others then
      raise exception 'Each receivable envelope allocation requires a valid envelope and amount';
    end;
    if v_envelope_id is null or v_allocation_amount is null or v_allocation_amount <= 0 then raise exception 'Each receivable envelope allocation requires a positive amount and envelope'; end if;
    if v_envelope_id = any(v_seen) then raise exception 'An envelope can appear only once in a receivable split'; end if;
    if not exists (
      select 1 from public.envelopes
      where id=v_envelope_id and household_id=p_household_id
        and archived_at is null and not is_system
    ) then raise exception 'Receivable allocation envelope is not an active ordinary household envelope'; end if;
    v_seen := array_append(v_seen, v_envelope_id);
    v_allocated_total := v_allocated_total + v_allocation_amount;
  end loop;
  if v_allocated_total > p_amount then raise exception 'Receivable envelope allocations cannot exceed the settlement amount'; end if;
  v_receivable_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
  v_transaction_id := public.insert_financial_event_ledger_transaction(
    p_household_id, v_event_id, 'receivable_settlement', p_occurred_at,
    p_description, p_amount, null, p_destination_account_id,
    p_destination_account_id, v_receivable_id, p_notes
  );
  insert into public.obligation_settlements(
    household_id, obligation_id, event_id, financial_transaction_id, amount,
    occurred_at, created_by
  ) values (
    p_household_id, p_obligation_id, v_event_id, v_transaction_id, p_amount,
    coalesce(p_occurred_at, now()), auth.uid()
  );
  if jsonb_array_length(p_envelope_allocations) > 0 then
    insert into public.envelope_movements(
      household_id,event_id,financial_transaction_id,envelope_id,
      movement_group_id,movement_type,direction,amount,occurred_at,
      description,created_by
    )
    select p_household_id,v_event_id,v_transaction_id,
      (value ->> 'envelope_id')::uuid,v_group_id,'allocation','inflow',
      (value ->> 'amount')::numeric,coalesce(p_occurred_at,now()),
      trim(p_description),auth.uid()
    from jsonb_array_elements(p_envelope_allocations);
  end if;
  v_remainder := p_amount - v_allocated_total;
  if v_remainder > 0 then
    v_to_allocate_envelope_id := public.ensure_household_system_envelope(
      p_household_id, 'to_allocate'
    );
    insert into public.envelope_movements(
      household_id,event_id,financial_transaction_id,envelope_id,
      movement_group_id,movement_type,direction,amount,occurred_at,
      description,created_by
    ) values (
      p_household_id,v_event_id,v_transaction_id,v_to_allocate_envelope_id,
      v_group_id,'allocation','inflow',v_remainder,coalesce(p_occurred_at,now()),
      trim(p_description),auth.uid()
    );
  end if;
  return v_event_id;
end; $$;

revoke all on function public.settle_receivable_event(
  uuid,uuid,timestamptz,text,numeric,uuid,text,uuid,jsonb
) from public, anon;
grant execute on function public.settle_receivable_event(
  uuid,uuid,timestamptz,text,numeric,uuid,text,uuid,jsonb
) to authenticated;

commit;
