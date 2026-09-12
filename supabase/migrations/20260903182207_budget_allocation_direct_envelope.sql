-- Direct budget funding must never consume the system envelope "À répartir".
-- It debits the ordinary funding account in the ledger and creates one
-- allocation inflow on the ordinary destination envelope. Historical rows are
-- deliberately left untouched.
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
  v_event_id uuid;
  v_event_type text;
  v_transaction_id uuid;
  v_transaction_type text;
  v_transaction_amount numeric(14, 2);
  v_total numeric(14, 2);
  v_inflow numeric(14, 2);
  v_outflow numeric(14, 2);
  v_all_ordinary boolean;
begin
  select household_id, count(*), min(movement_type)
  into v_household_id, v_count, v_type
  from public.envelope_movements
  where movement_group_id = p_movement_group_id
  group by household_id;
  if not found then return; end if;

  if exists (
    select 1
    from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and household_id <> v_household_id
  ) then
    raise exception 'An envelope movement group cannot span households';
  end if;

  select event_id, financial_transaction_id
  into v_event_id, v_transaction_id
  from public.envelope_movements
  where movement_group_id = p_movement_group_id
  limit 1;

  if exists (
    select 1
    from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and financial_transaction_id is distinct from v_transaction_id
  ) then
    raise exception 'Envelope movement group must reference one financial transaction';
  end if;
  if exists (
    select 1
    from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and event_id is distinct from v_event_id
  ) then
    raise exception 'Envelope movement group must reference one FinancialEvent';
  end if;

  select event_type into v_event_type
  from public.financial_events
  where id = v_event_id and household_id = v_household_id;

  if v_type in ('consumption', 'allocation', 'refund', 'adjustment', 'reversal') and exists (
    select 1
    from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and movement_type <> v_type
  ) then
    raise exception 'Envelope movement group contains incompatible types';
  end if;

  if v_type = 'consumption' then
    select type, amount into v_transaction_type, v_transaction_amount
    from public.financial_transactions
    where id = v_transaction_id and household_id = v_household_id;
    select sum(amount) into v_total
    from public.envelope_movements
    where movement_group_id = p_movement_group_id;
    if v_transaction_id is null or v_transaction_type <> 'expense'
       or v_total <> v_transaction_amount then
      raise exception 'Expense envelope allocations must equal the expense amount';
    end if;
  elsif v_type = 'allocation' then
    select type, amount into v_transaction_type, v_transaction_amount
    from public.financial_transactions
    where id = v_transaction_id and household_id = v_household_id;
    select
      sum(movements.amount),
      bool_and(not envelopes.is_system)
    into v_total, v_all_ordinary
    from public.envelope_movements movements
    join public.envelopes on envelopes.id = movements.envelope_id
    where movements.movement_group_id = p_movement_group_id;

    if v_event_type = 'cash_income' then
      if v_transaction_id is null or v_transaction_type <> 'income'
         or v_total <> v_transaction_amount then
        raise exception 'Income envelope allocations must equal the income amount';
      end if;
    elsif v_event_type = 'budget_allocation' then
      if v_count <> 1 or v_transaction_id is null or v_transaction_type <> 'allocation'
         or v_total <> v_transaction_amount or not coalesce(v_all_ordinary, false) then
        raise exception 'Budget allocation must fund one ordinary destination envelope directly';
      end if;
    else
      raise exception 'Allocation movements require a supported FinancialEvent type';
    end if;
  elsif v_type in ('transfer_in', 'transfer_out') then
    select count(*), sum(case when direction = 'inflow' then amount else 0 end),
      sum(case when direction = 'outflow' then amount else 0 end)
    into v_count, v_inflow, v_outflow
    from public.envelope_movements
    where movement_group_id = p_movement_group_id;
    if v_count <> 2 or v_inflow <> v_outflow
    or (select count(*) from public.envelope_movements
      where movement_group_id = p_movement_group_id
        and movement_type = 'transfer_in') <> 1
    or (select count(*) from public.envelope_movements
      where movement_group_id = p_movement_group_id
        and movement_type = 'transfer_out') <> 1
    or (select count(distinct envelope_id) from public.envelope_movements
      where movement_group_id = p_movement_group_id) <> 2 then
      raise exception 'Envelope transfer must have two balanced distinct envelopes';
    end if;
    if v_transaction_id is not null and not exists (
      select 1
      from public.financial_transactions
      where id = v_transaction_id and household_id = v_household_id
        and type = 'allocation'
    ) then
      raise exception 'A ledger-backed envelope transfer must be a budget allocation';
    end if;
  elsif v_type = 'reversal' and exists (
    select 1
    from public.envelope_movements reversals
    join public.envelope_movements originals on originals.id = reversals.reversal_of
    where reversals.movement_group_id = p_movement_group_id
      and (
        originals.household_id <> reversals.household_id
        or originals.amount <> reversals.amount
        or originals.direction = reversals.direction
      )
  ) then
    raise exception 'Envelope reversal must invert one original movement exactly';
  end if;
end;
$$;

create or replace function public.allocate_budget_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_source_account_id uuid, p_destination_envelope_id uuid, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_to_allocate_account_id uuid;
  v_transaction_id uuid;
  v_group_id uuid := gen_random_uuid();
  v_available_balance numeric;
begin
  v_event_id := public.create_or_get_financial_event(
    p_household_id, 'budget_allocation', p_occurred_at, p_description,
    p_notes, p_idempotency_key
  );
  if exists (
    select 1 from public.budget_funding_links where event_id = v_event_id
  ) then
    return v_event_id;
  end if;

  perform public.assert_financial_event_ordinary_account(
    p_household_id, p_source_account_id
  );
  if p_amount is null or p_amount <= 0 then
    raise exception 'A positive amount is required';
  end if;
  perform 1 from public.accounts
  where id = p_source_account_id and household_id = p_household_id
  for update;
  select theoretical_balance into v_available_balance
  from public.account_ledger_balances
  where account_id = p_source_account_id and household_id = p_household_id;
  if coalesce(v_available_balance, 0) < p_amount then
    raise exception 'Insufficient available balance for budget allocation';
  end if;
  if not exists (
    select 1 from public.envelopes
    where id = p_destination_envelope_id and household_id = p_household_id
      and archived_at is null and not is_system
  ) then
    raise exception 'Destination must be an active ordinary household envelope';
  end if;

  -- The system ledger account is the balanced accounting counterpart only.
  -- The system *envelope* À répartir is intentionally not touched here.
  v_to_allocate_account_id := public.ensure_financial_event_system_account(
    p_household_id, 'to_allocate'
  );
  v_transaction_id := public.insert_financial_event_ledger_transaction(
    p_household_id, v_event_id, 'allocation', p_occurred_at, p_description,
    p_amount, p_source_account_id, v_to_allocate_account_id,
    v_to_allocate_account_id, p_source_account_id, p_notes
  );
  insert into public.envelope_movements(
    household_id, event_id, financial_transaction_id, envelope_id,
    movement_group_id, movement_type, direction, amount, occurred_at,
    description, created_by
  ) values (
    p_household_id, v_event_id, v_transaction_id, p_destination_envelope_id,
    v_group_id, 'allocation', 'inflow', p_amount,
    coalesce(p_occurred_at, now()), trim(p_description), auth.uid()
  );
  insert into public.budget_funding_links(
    household_id, event_id, source_account_id, envelope_id, amount,
    occurred_at, notes, created_by
  ) values (
    p_household_id, v_event_id, p_source_account_id,
    p_destination_envelope_id, p_amount, coalesce(p_occurred_at, now()),
    nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  );
  return v_event_id;
end;
$$;

revoke all on function public.allocate_budget_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid)
  from public, anon;
grant execute on function public.allocate_budget_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid)
  to authenticated;

commit;
