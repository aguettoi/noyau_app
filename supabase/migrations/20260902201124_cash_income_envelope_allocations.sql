-- Canonical cash income: one FinancialEvent, one balanced income ledger
-- transaction and one or more envelope inflows.  This is additive and leaves
-- the legacy income RPC and historical rows untouched.
begin;

alter table public.financial_events
  drop constraint if exists financial_events_event_type_check;
alter table public.financial_events
  add constraint financial_events_event_type_check check (event_type in (
    'cash_expense', 'cash_income', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement',
    'recovery_receivable', 'recovery_settlement', 'budget_allocation',
    'account_transfer', 'envelope_transfer'
  ));

-- Income allocations deliberately share an allocation group.  Legacy income
-- remains valid with its single no-event movement to À répartir, while a
-- cash_income event may distribute its whole amount across ordinary envelopes
-- and the system remainder.
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
    where movement_group_id = p_movement_group_id and movement_type <> v_type
  ) then
    raise exception 'Envelope movement group contains incompatible types';
  end if;

  if v_type = 'consumption' then
    select type, amount into v_transaction_type, v_transaction_amount
    from public.financial_transactions
    where id = v_transaction_id and household_id = v_household_id;
    select sum(amount) into v_total
    from public.envelope_movements where movement_group_id = p_movement_group_id;
    if v_transaction_id is null or v_transaction_type <> 'expense'
       or v_total <> v_transaction_amount then
      raise exception 'Expense envelope allocations must equal the expense amount';
    end if;
  elsif v_type = 'allocation' then
    select type, amount into v_transaction_type, v_transaction_amount
    from public.financial_transactions
    where id = v_transaction_id and household_id = v_household_id;
    select sum(amount) into v_total
    from public.envelope_movements where movement_group_id = p_movement_group_id;
    if v_transaction_id is null or v_transaction_type <> 'income'
       or v_total <> v_transaction_amount then
      raise exception 'Income envelope allocations must equal the income amount';
    end if;
    if v_event_id is not null and not exists (
      select 1 from public.financial_events
      where id = v_event_id and household_id = v_household_id
        and event_type = 'cash_income'
    ) then
      raise exception 'Only cash income events can have event-linked income allocations';
    end if;
  elsif v_type in ('transfer_in', 'transfer_out') then
    select count(*), sum(case when direction = 'inflow' then amount else 0 end),
      sum(case when direction = 'outflow' then amount else 0 end)
    into v_count, v_inflow, v_outflow
    from public.envelope_movements where movement_group_id = p_movement_group_id;
    if v_count <> 2 or v_inflow <> v_outflow
    or (select count(*) from public.envelope_movements
      where movement_group_id = p_movement_group_id and movement_type = 'transfer_in') <> 1
    or (select count(*) from public.envelope_movements
      where movement_group_id = p_movement_group_id and movement_type = 'transfer_out') <> 1
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
    where reversals.movement_group_id = p_movement_group_id and (
      originals.household_id <> reversals.household_id
      or originals.amount <> reversals.amount
      or originals.direction = reversals.direction
    )
  ) then
    raise exception 'Envelope reversal must invert one original movement exactly';
  end if;
end;
$$;

create or replace function public.create_cash_income_event(
  p_household_id uuid,
  p_occurred_at timestamptz,
  p_description text,
  p_amount numeric,
  p_destination_account_id uuid,
  p_envelope_allocations jsonb default '[]'::jsonb,
  p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_transaction_id uuid;
  v_income_account_id uuid;
  v_to_allocate_envelope_id uuid;
  v_group_id uuid := gen_random_uuid();
  v_item jsonb;
  v_envelope_id uuid;
  v_allocation_amount numeric(14, 2);
  v_allocated_total numeric(14, 2) := 0;
  v_remainder numeric(14, 2);
  v_seen uuid[] := '{}';
begin
  -- Authorisation and event idempotence are deliberately acquired before any
  -- write.  A successful replay returns before creating another transaction.
  v_event_id := public.create_or_get_financial_event(
    p_household_id, 'cash_income', p_occurred_at, p_description,
    p_notes, p_idempotency_key
  );
  if exists (
    select 1 from public.financial_transactions
    where event_id = v_event_id and household_id = p_household_id
  ) then
    return v_event_id;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'A positive income amount is required';
  end if;
  if p_envelope_allocations is null
    or jsonb_typeof(p_envelope_allocations) <> 'array' then
    raise exception 'Income envelope allocations must be an array';
  end if;
  if not exists (
    select 1 from public.accounts
    where id = p_destination_account_id
      and household_id = p_household_id
      and archived_at is null
      and not is_system
  ) then
    raise exception 'An active ordinary household account is required';
  end if;

  for v_item in select value from jsonb_array_elements(p_envelope_allocations) loop
    v_envelope_id := nullif(v_item ->> 'envelope_id', '')::uuid;
    v_allocation_amount := nullif(v_item ->> 'amount', '')::numeric;
    if v_envelope_id is null or v_allocation_amount is null or v_allocation_amount <= 0 then
      raise exception 'Each income envelope allocation requires a positive amount and envelope';
    end if;
    if v_envelope_id = any(v_seen) then
      raise exception 'An envelope can appear only once in an income split';
    end if;
    if not exists (
      select 1 from public.envelopes
      where id = v_envelope_id and household_id = p_household_id
        and archived_at is null and not is_system
    ) then
      raise exception 'Income allocation envelope is not an active ordinary household envelope';
    end if;
    v_seen := array_append(v_seen, v_envelope_id);
    v_allocated_total := v_allocated_total + v_allocation_amount;
  end loop;
  if v_allocated_total > p_amount then
    raise exception 'Income envelope allocations cannot exceed the income amount';
  end if;

  -- Lock the received account only after every input is valid.  This also
  -- serialises a concurrent archive/update of the account during the write.
  perform 1 from public.accounts
  where id = p_destination_account_id and household_id = p_household_id
  for update;

  v_income_account_id := public.ensure_financial_event_system_account(
    p_household_id, 'income'
  );
  v_transaction_id := public.insert_financial_event_ledger_transaction(
    p_household_id, v_event_id, 'income', p_occurred_at, p_description,
    p_amount, null, p_destination_account_id, p_destination_account_id,
    v_income_account_id, p_notes
  );

  if jsonb_array_length(p_envelope_allocations) > 0 then
    insert into public.envelope_movements(
      household_id, event_id, financial_transaction_id, envelope_id,
      movement_group_id, movement_type, direction, amount, occurred_at,
      description, created_by
    )
    select p_household_id, v_event_id, v_transaction_id,
      (value ->> 'envelope_id')::uuid, v_group_id, 'allocation', 'inflow',
      (value ->> 'amount')::numeric, coalesce(p_occurred_at, now()),
      trim(p_description), auth.uid()
    from jsonb_array_elements(p_envelope_allocations);
  end if;

  v_remainder := p_amount - v_allocated_total;
  if v_remainder > 0 then
    v_to_allocate_envelope_id := public.ensure_household_system_envelope(
      p_household_id, 'to_allocate'
    );
    insert into public.envelope_movements(
      household_id, event_id, financial_transaction_id, envelope_id,
      movement_group_id, movement_type, direction, amount, occurred_at,
      description, created_by
    ) values (
      p_household_id, v_event_id, v_transaction_id, v_to_allocate_envelope_id,
      v_group_id, 'allocation', 'inflow', v_remainder,
      coalesce(p_occurred_at, now()), trim(p_description), auth.uid()
    );
  end if;
  return v_event_id;
end;
$$;

revoke all on function public.create_cash_income_event(
  uuid, timestamptz, text, numeric, uuid, jsonb, text, uuid
) from public, anon;
grant execute on function public.create_cash_income_event(
  uuid, timestamptz, text, numeric, uuid, jsonb, text, uuid
) to authenticated;

commit;
