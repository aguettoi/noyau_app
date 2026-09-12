-- Budget allocations are liquidity assignments: debit the funding account,
-- credit the dedicated system counterpart, and fund the target envelope.
-- The migration is additive and leaves historical runs/events untouched.
begin;

create or replace function public.ensure_financial_event_system_account(
  p_household_id uuid, p_code text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_account_id uuid;
  v_is_system boolean;
  v_name text := case p_code
    when 'expense' then 'Système — Dépenses'
    when 'income' then 'Système — Revenus'
    when 'debt' then 'Système — Dettes'
    when 'receivable' then 'Système — Créances'
    when 'recovery' then 'Système — Recouvrements'
    when 'to_allocate' then 'Système — À répartir'
    else null
  end;
begin
  if v_name is null then raise exception 'Unsupported FinancialEvent counterpart'; end if;
  select id, is_system into v_account_id, v_is_system from public.accounts
  where household_id = p_household_id and name = v_name;
  if found then
    if not v_is_system then
      raise exception 'A reserved FinancialEvent account name is already used';
    end if;
    return v_account_id;
  end if;
  insert into public.accounts(household_id, name, kind, is_system)
  values (p_household_id, v_name, 'ledger', true)
  returning id into v_account_id;
  return v_account_id;
end;
$$;

-- A funded budget allocation is a ledger-backed envelope transfer: ordinary
-- envelope transfers still have no ledger transaction, while allocations use
-- one balanced `allocation` transaction for their two movements.
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
  v_transaction_id uuid;
  v_transaction_type text;
  v_transaction_amount numeric(14, 2);
  v_total numeric(14, 2);
  v_inflow numeric(14, 2);
  v_outflow numeric(14, 2);
  v_all_to_allocate boolean;
begin
  select household_id, count(*), min(movement_type)
  into v_household_id, v_count, v_type
  from public.envelope_movements
  where movement_group_id = p_movement_group_id
  group by household_id;
  if not found then return; end if;
  if exists (
    select 1 from public.envelope_movements
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
    select 1 from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and financial_transaction_id is distinct from v_transaction_id
  ) then
    raise exception 'Envelope movement group must reference one financial transaction';
  end if;
  if exists (
    select 1 from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and event_id is distinct from v_event_id
  ) then
    raise exception 'Envelope movement group must reference one FinancialEvent';
  end if;

  if v_type in ('consumption', 'allocation', 'refund', 'adjustment', 'reversal') and exists (
    select 1 from public.envelope_movements
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
    select sum(movements.amount), bool_and(envelopes.system_code = 'to_allocate')
    into v_total, v_all_to_allocate
    from public.envelope_movements movements
    join public.envelopes on envelopes.id = movements.envelope_id
    where movements.movement_group_id = p_movement_group_id;
    if v_count <> 1 or v_transaction_id is null or v_transaction_type <> 'income'
       or v_total <> v_transaction_amount or not coalesce(v_all_to_allocate, false) then
      raise exception 'Income must allocate its full amount to À répartir';
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
      select 1 from public.financial_transactions
      where id = v_transaction_id and household_id = v_household_id
        and type = 'allocation'
    ) then
      raise exception 'A ledger-backed envelope transfer must be a budget allocation';
    end if;
  elsif v_type = 'reversal' and exists (
    select 1 from public.envelope_movements reversals
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
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_event_id uuid;
  v_to_allocate_envelope_id uuid;
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

  v_to_allocate_envelope_id := public.ensure_household_system_envelope(
    p_household_id, 'to_allocate'
  );
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
  ) values
    (
      p_household_id, v_event_id, v_transaction_id, v_to_allocate_envelope_id,
      v_group_id, 'transfer_out', 'outflow', p_amount,
      coalesce(p_occurred_at, now()), trim(p_description), auth.uid()
    ),
    (
      p_household_id, v_event_id, v_transaction_id, p_destination_envelope_id,
      v_group_id, 'transfer_in', 'inflow', p_amount,
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

create or replace function public.apply_budget_allocation_run_with_funding(
  p_household_id uuid,
  p_run_id uuid,
  p_funding_lines jsonb,
  p_idempotency_key uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_remaining numeric;
  v_apply_key uuid;
  v_expected_total numeric;
  v_actual_total numeric;
  v_run_line record;
  v_funding record;
  v_account_funding record;
  v_line_total numeric;
  v_event_id uuid;
  v_available_balance numeric;
  v_account_name text;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_funding_lines is null or jsonb_typeof(p_funding_lines) <> 'array' then
    raise exception 'Funding lines must be an array';
  end if;

  select status, remaining_unallocated, application_idempotency_key, calculated_total
    into v_status, v_remaining, v_apply_key, v_expected_total
  from public.budget_allocation_runs
  where id = p_run_id and household_id = p_household_id
  for update;
  if not found then raise exception 'Budget run does not belong to household'; end if;
  if v_status = 'applied' then
    if v_apply_key = p_idempotency_key then return p_run_id; end if;
    raise exception 'Budget run is already applied';
  end if;
  if v_status <> 'approved' then raise exception 'Only an approved budget run can be applied'; end if;
  if v_remaining < 0 then raise exception 'An over-allocated budget run cannot be applied'; end if;

  select coalesce(sum((item.value ->> 'amount')::numeric), 0)
    into v_actual_total
  from jsonb_array_elements(p_funding_lines) item(value);
  if v_actual_total <> v_expected_total then
    raise exception 'Funding total must equal the budget run total';
  end if;

  for v_funding in
    select item.value, item.ordinality
    from jsonb_array_elements(p_funding_lines) with ordinality as item(value, ordinality)
  loop
    if nullif(v_funding.value ->> 'amount', '') is null
      or (v_funding.value ->> 'amount')::numeric <= 0 then
      raise exception 'Each funding amount must be positive';
    end if;
    perform public.assert_financial_event_ordinary_account(
      p_household_id,
      (v_funding.value ->> 'source_account_id')::uuid
    );
    if not exists (
      select 1 from public.budget_allocation_run_lines run_line
      where run_line.id = (v_funding.value ->> 'run_line_id')::uuid
        and run_line.run_id = p_run_id
        and run_line.household_id = p_household_id
        and run_line.envelope_id = (v_funding.value ->> 'envelope_id')::uuid
    ) then
      raise exception 'Funding must target an envelope allocation from this budget run';
    end if;
  end loop;

  -- Lock in stable account order and check the aggregate requested from each
  -- account before the first FinancialEvent or envelope movement is written.
  for v_account_funding in
    select
      (item.value ->> 'source_account_id')::uuid as account_id,
      sum((item.value ->> 'amount')::numeric) as requested_amount
    from jsonb_array_elements(p_funding_lines) item(value)
    group by (item.value ->> 'source_account_id')::uuid
    order by (item.value ->> 'source_account_id')::uuid
  loop
    select accounts.name, balances.theoretical_balance
      into v_account_name, v_available_balance
    from public.accounts accounts
    join public.account_ledger_balances balances
      on balances.account_id = accounts.id
    where accounts.id = v_account_funding.account_id
      and accounts.household_id = p_household_id
    for update of accounts;
    if not found or coalesce(v_available_balance, 0) < v_account_funding.requested_amount then
      raise exception 'Insufficient available balance for account %: available %, required %',
        coalesce(v_account_name, v_account_funding.account_id::text),
        coalesce(v_available_balance, 0), v_account_funding.requested_amount;
    end if;
  end loop;

  for v_run_line in
    select run_line.id, run_line.envelope_id, run_line.planned_allocation
    from public.budget_allocation_run_lines run_line
    where run_line.run_id = p_run_id
      and run_line.household_id = p_household_id
      and run_line.planned_allocation > 0
  loop
    select coalesce(sum((item.value ->> 'amount')::numeric), 0)
      into v_line_total
    from jsonb_array_elements(p_funding_lines) item(value)
    where (item.value ->> 'run_line_id')::uuid = v_run_line.id;
    if v_line_total <> v_run_line.planned_allocation then
      raise exception 'Funding must equal the planned amount for every envelope';
    end if;
  end loop;

  for v_funding in
    select item.value, item.ordinality
    from jsonb_array_elements(p_funding_lines) with ordinality as item(value, ordinality)
    order by item.ordinality
  loop
    v_event_id := public.allocate_budget_event(
      p_household_id,
      now(),
      'Allocation budgétaire',
      (v_funding.value ->> 'amount')::numeric,
      (v_funding.value ->> 'source_account_id')::uuid,
      (v_funding.value ->> 'envelope_id')::uuid,
      'Budget run ' || p_run_id::text,
      md5(p_run_id::text || ':funding:' || v_funding.ordinality::text)::uuid
    );
    insert into public.budget_allocation_run_funding_lines(
      household_id, run_id, run_line_id, source_account_id, envelope_id,
      amount, funding_index, event_id, applied_at
    ) values (
      p_household_id, p_run_id,
      (v_funding.value ->> 'run_line_id')::uuid,
      (v_funding.value ->> 'source_account_id')::uuid,
      (v_funding.value ->> 'envelope_id')::uuid,
      (v_funding.value ->> 'amount')::numeric,
      v_funding.ordinality::integer, v_event_id, now()
    );
  end loop;

  update public.budget_allocation_runs
  set status = 'applied', applied_at = now(), application_idempotency_key = p_idempotency_key
  where id = p_run_id and household_id = p_household_id;
  return p_run_id;
end;
$$;

revoke all on function public.allocate_budget_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid)
  from public, anon;
grant execute on function public.allocate_budget_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid)
  to authenticated;

commit;
