-- Allow the FinancialEvent debt-expense ledger type to consume envelopes.
-- The group remains deferred, atomic and fully validated at transaction commit.
begin;

create or replace function public.assert_envelope_movement_group(
  p_movement_group_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
  v_count integer;
  v_type text;
  v_transaction_id uuid;
  v_transaction_type text;
  v_transaction_amount numeric(14, 2);
  v_total numeric(14, 2);
  v_inflow numeric(14, 2);
  v_outflow numeric(14, 2);
  v_all_to_allocate boolean;
begin
  select movements.household_id, count(*), min(movements.movement_type)
  into v_household_id, v_count, v_type
  from public.envelope_movements movements
  where movements.movement_group_id = p_movement_group_id
  group by movements.household_id;
  if not found then
    return;
  end if;
  if exists (
    select 1
    from public.envelope_movements movements
    where movements.movement_group_id = p_movement_group_id
      and movements.household_id <> v_household_id
  ) then
    raise exception 'An envelope movement group cannot span households';
  end if;

  select movements.financial_transaction_id into v_transaction_id
  from public.envelope_movements movements
  where movements.movement_group_id = p_movement_group_id
  limit 1;
  if exists (
    select 1
    from public.envelope_movements movements
    where movements.movement_group_id = p_movement_group_id
      and movements.financial_transaction_id is distinct from v_transaction_id
  ) then
    raise exception 'Envelope movement group must reference one financial transaction';
  end if;
  if v_type in ('consumption', 'allocation', 'refund', 'adjustment', 'reversal') and exists (
    select 1
    from public.envelope_movements movements
    where movements.movement_group_id = p_movement_group_id
      and movements.movement_type <> v_type
  ) then
    raise exception 'Envelope movement group contains incompatible types';
  end if;

  if v_type = 'consumption' then
    select transactions.type, transactions.amount
    into v_transaction_type, v_transaction_amount
    from public.financial_transactions transactions
    where transactions.id = v_transaction_id
      and transactions.household_id = v_household_id;
    select sum(movements.amount) into v_total
    from public.envelope_movements movements
    where movements.movement_group_id = p_movement_group_id;
    if v_transaction_id is null
      or v_transaction_type not in ('expense', 'debt_expense')
      or v_total <> v_transaction_amount then
      raise exception 'Expense envelope allocations must equal the expense amount';
    end if;
  elsif v_type = 'allocation' then
    select transactions.type, transactions.amount
    into v_transaction_type, v_transaction_amount
    from public.financial_transactions transactions
    where transactions.id = v_transaction_id
      and transactions.household_id = v_household_id;
    select sum(movements.amount), bool_and(envelopes.system_code = 'to_allocate')
    into v_total, v_all_to_allocate
    from public.envelope_movements movements
    join public.envelopes envelopes on envelopes.id = movements.envelope_id
    where movements.movement_group_id = p_movement_group_id;
    if v_count <> 1 or v_transaction_id is null or v_transaction_type <> 'income'
      or v_total <> v_transaction_amount or not coalesce(v_all_to_allocate, false) then
      raise exception 'Income must allocate its full amount to À répartir';
    end if;
  elsif v_type in ('transfer_in', 'transfer_out') then
    select count(*),
      sum(case when movements.direction = 'inflow' then movements.amount else 0 end),
      sum(case when movements.direction = 'outflow' then movements.amount else 0 end)
    into v_count, v_inflow, v_outflow
    from public.envelope_movements movements
    where movements.movement_group_id = p_movement_group_id;
    if v_count <> 2 or v_inflow <> v_outflow or exists (
      select 1 from public.envelope_movements movements
      where movements.movement_group_id = p_movement_group_id
        and movements.financial_transaction_id is not null
    ) or (select count(*) from public.envelope_movements movements
      where movements.movement_group_id = p_movement_group_id
        and movements.movement_type = 'transfer_in') <> 1
    or (select count(*) from public.envelope_movements movements
      where movements.movement_group_id = p_movement_group_id
        and movements.movement_type = 'transfer_out') <> 1
    or (select count(distinct movements.envelope_id)
      from public.envelope_movements movements
      where movements.movement_group_id = p_movement_group_id) <> 2 then
      raise exception 'Envelope transfer must have two balanced distinct envelopes';
    end if;
  elsif v_type = 'reversal' and exists (
    select 1
    from public.envelope_movements reversals
    join public.envelope_movements originals on originals.id = reversals.reversal_of
    where reversals.movement_group_id = p_movement_group_id
      and (originals.household_id <> reversals.household_id
        or originals.amount <> reversals.amount
        or originals.direction = reversals.direction)
  ) then
    raise exception 'Envelope reversal must invert one original movement exactly';
  end if;
end;
$$;

commit;
