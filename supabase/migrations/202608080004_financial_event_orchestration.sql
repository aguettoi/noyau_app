-- FinancialEvent-native atomic write boundary. Apply after 202608080003.
-- Every public RPC creates (or deterministically retrieves) its event before
-- writing dependent records; no immutable ledger row is backfilled afterwards.
-- financial_transaction_lines deliberately has no event_id: its immutable
-- transaction_id already determines financial_transactions.event_id, so a
-- second physical foreign key would only duplicate the same relationship.
begin;

alter table public.financial_transactions
  drop constraint if exists financial_transactions_type_check;
alter table public.financial_transactions
  add constraint financial_transactions_type_check check (type in (
    'allocation', 'expense', 'transfer', 'adjustment', 'recovery', 'income',
    'opening_balance', 'correction', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement', 'recovery_receivable',
    'recovery_settlement'
  ));

create index if not exists financial_transactions_event_idx
  on public.financial_transactions(event_id) where event_id is not null;
create index if not exists envelope_movements_event_idx
  on public.envelope_movements(event_id) where event_id is not null;
create index if not exists obligations_household_open_idx
  on public.obligations(household_id, created_at desc);
create index if not exists obligation_settlements_obligation_idx
  on public.obligation_settlements(obligation_id, occurred_at);
create index if not exists budget_funding_links_event_idx
  on public.budget_funding_links(event_id);

create or replace function public.create_or_get_financial_event(
  p_household_id uuid,
  p_event_type text,
  p_occurred_at timestamptz,
  p_description text,
  p_notes text,
  p_idempotency_key uuid
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_event_id uuid;
  v_existing_type text;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required';
  end if;
  if char_length(trim(coalesce(p_description, ''))) not between 1 and 280 then
    raise exception 'A description between 1 and 280 characters is required';
  end if;
  insert into public.financial_events(
    household_id, event_type, occurred_at, description, notes, idempotency_key, created_by
  ) values (
    p_household_id, p_event_type, coalesce(p_occurred_at, now()), trim(p_description),
    nullif(trim(coalesce(p_notes, '')), ''), p_idempotency_key, auth.uid()
  ) on conflict (household_id, idempotency_key) do nothing
  returning id into v_event_id;
  if v_event_id is null then
    select id, event_type into v_event_id, v_existing_type
    from public.financial_events
    where household_id = p_household_id and idempotency_key = p_idempotency_key;
    if v_existing_type <> p_event_type then
      raise exception 'Idempotency key was already used for a different event type';
    end if;
  end if;
  return v_event_id;
end;
$$;

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

create or replace function public.assert_financial_event_ordinary_account(
  p_household_id uuid, p_account_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_account_id is null or not exists (
    select 1 from public.accounts
    where id = p_account_id and household_id = p_household_id and not is_system
  ) then raise exception 'An ordinary account of the household is required'; end if;
end;
$$;

create or replace function public.insert_financial_event_ledger_transaction(
  p_household_id uuid, p_event_id uuid, p_type text, p_occurred_at timestamptz,
  p_description text, p_amount numeric, p_source_account_id uuid,
  p_destination_account_id uuid, p_debit_account_id uuid, p_credit_account_id uuid,
  p_notes text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_transaction_id uuid; v_occurred_at timestamptz := coalesce(p_occurred_at, now());
begin
  if p_amount is null or p_amount <= 0 then raise exception 'A positive amount is required'; end if;
  insert into public.financial_transactions(
    household_id, event_id, type, occurred_at, reason, description, amount,
    currency_code, source_account_id, destination_account_id, notes, created_by, validated_at
  ) values (
    p_household_id, p_event_id, p_type, v_occurred_at, trim(p_description), trim(p_description),
    p_amount, 'MAD', p_source_account_id, p_destination_account_id,
    nullif(trim(coalesce(p_notes, '')), ''), auth.uid(), now()
  ) returning id into v_transaction_id;
  insert into public.financial_transaction_lines(
    transaction_id, account_id, amount, debit, credit, occurred_at
  ) values
    (v_transaction_id, p_debit_account_id, p_amount, p_amount, 0, v_occurred_at),
    (v_transaction_id, p_credit_account_id, -p_amount, 0, p_amount, v_occurred_at);
  insert into public.financial_audit_events(household_id, transaction_id, action, reason, actor_id)
  values (p_household_id, v_transaction_id, 'created', trim(p_description), auth.uid());
  return v_transaction_id;
end;
$$;

create or replace function public.insert_financial_event_consumptions(
  p_household_id uuid, p_event_id uuid, p_transaction_id uuid, p_occurred_at timestamptz,
  p_description text, p_amount numeric, p_allocations jsonb
) returns void
language plpgsql security definer set search_path = public as $$
declare v_item jsonb; v_envelope_id uuid; v_amount numeric; v_total numeric := 0; v_seen uuid[] := '{}'; v_group_id uuid := gen_random_uuid();
begin
  if jsonb_typeof(p_allocations) <> 'array' or jsonb_array_length(p_allocations) = 0 then
    raise exception 'At least one envelope allocation is required';
  end if;
  for v_item in select value from jsonb_array_elements(p_allocations) loop
    v_envelope_id := nullif(v_item ->> 'envelope_id', '')::uuid;
    v_amount := nullif(v_item ->> 'amount', '')::numeric;
    if v_envelope_id is null or v_amount is null or v_amount <= 0 then
      raise exception 'Each envelope allocation requires a positive amount and envelope';
    end if;
    if v_envelope_id = any(v_seen) then raise exception 'An envelope can appear only once in a split'; end if;
    if not exists (
      select 1 from public.envelopes
      where id = v_envelope_id and household_id = p_household_id
        and archived_at is null and not is_system
    ) then raise exception 'Allocation envelope is not an active ordinary household envelope'; end if;
    v_seen := array_append(v_seen, v_envelope_id); v_total := v_total + v_amount;
  end loop;
  if v_total <> p_amount then raise exception 'Envelope allocations must equal the event amount'; end if;
  insert into public.envelope_movements(
    household_id, event_id, envelope_id, financial_transaction_id, movement_group_id,
    movement_type, direction, amount, occurred_at, description, created_by
  ) select p_household_id, p_event_id, (value ->> 'envelope_id')::uuid, p_transaction_id,
    v_group_id, 'consumption', 'outflow', (value ->> 'amount')::numeric,
    coalesce(p_occurred_at, now()), trim(p_description), auth.uid()
  from jsonb_array_elements(p_allocations);
end;
$$;

create or replace function public.create_cash_expense_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_source_account_id uuid, p_envelope_allocations jsonb, p_notes text, p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_expense_id uuid;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'cash_expense', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.financial_transactions where event_id = v_event_id) then return v_event_id; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_source_account_id);
  v_expense_id := public.ensure_financial_event_system_account(p_household_id, 'expense');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'expense', p_occurred_at, p_description, p_amount, p_source_account_id, null, v_expense_id, p_source_account_id, p_notes);
  perform public.insert_financial_event_consumptions(p_household_id, v_event_id, v_transaction_id, p_occurred_at, p_description, p_amount, p_envelope_allocations);
  return v_event_id;
end; $$;

create or replace function public.create_debt_expense_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_envelope_allocations jsonb, p_creditor_name text default null, p_due_at date default null,
  p_notes text default null, p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_expense_id uuid; v_debt_id uuid;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'debt_expense', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligations where origin_event_id = v_event_id) then return v_event_id; end if;
  v_expense_id := public.ensure_financial_event_system_account(p_household_id, 'expense');
  v_debt_id := public.ensure_financial_event_system_account(p_household_id, 'debt');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'debt_expense', p_occurred_at, p_description, p_amount, null, null, v_expense_id, v_debt_id, p_notes);
  perform public.insert_financial_event_consumptions(p_household_id, v_event_id, v_transaction_id, p_occurred_at, p_description, p_amount, p_envelope_allocations);
  insert into public.obligations(household_id, obligation_kind, origin_event_id, origin_transaction_id, initial_amount, counterparty_name, description, due_at, created_by)
  values (p_household_id, 'debt', v_event_id, v_transaction_id, p_amount, nullif(trim(coalesce(p_creditor_name, '')), ''), trim(p_description), p_due_at, auth.uid());
  return v_event_id;
end; $$;

create or replace function public.settle_debt_event(
  p_household_id uuid, p_obligation_id uuid, p_occurred_at timestamptz, p_description text,
  p_amount numeric, p_source_account_id uuid, p_notes text default null, p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_debt_id uuid; v_remaining numeric;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'debt_settlement', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligation_settlements where event_id = v_event_id) then return v_event_id; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_source_account_id);
  perform 1 from public.obligations where id = p_obligation_id and household_id = p_household_id and obligation_kind = 'debt' for update;
  if not found then raise exception 'Open debt obligation does not belong to household'; end if;
  select remaining_amount into v_remaining from public.obligation_balances
  where obligation_id = p_obligation_id and household_id = p_household_id;
  if p_amount is null or p_amount <= 0 or p_amount > v_remaining then raise exception 'Settlement amount exceeds remaining debt'; end if;
  v_debt_id := public.ensure_financial_event_system_account(p_household_id, 'debt');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'debt_settlement', p_occurred_at, p_description, p_amount, p_source_account_id, null, v_debt_id, p_source_account_id, p_notes);
  insert into public.obligation_settlements(household_id, obligation_id, event_id, financial_transaction_id, amount, occurred_at, created_by)
  values (p_household_id, p_obligation_id, v_event_id, v_transaction_id, p_amount, coalesce(p_occurred_at, now()), auth.uid());
  return v_event_id;
end; $$;

create or replace function public.create_income_receivable_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_debtor_name text default null, p_due_at date default null, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_receivable_id uuid; v_income_id uuid;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'income_receivable', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligations where origin_event_id = v_event_id) then return v_event_id; end if;
  v_receivable_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
  v_income_id := public.ensure_financial_event_system_account(p_household_id, 'income');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'income_receivable', p_occurred_at, p_description, p_amount, null, null, v_receivable_id, v_income_id, p_notes);
  insert into public.obligations(household_id, obligation_kind, receivable_kind, origin_event_id, origin_transaction_id, initial_amount, counterparty_name, description, due_at, created_by)
  values (p_household_id, 'receivable', 'income', v_event_id, v_transaction_id, p_amount, nullif(trim(coalesce(p_debtor_name, '')), ''), trim(p_description), p_due_at, auth.uid());
  return v_event_id;
end; $$;

create or replace function public.settle_receivable_event(
  p_household_id uuid, p_obligation_id uuid, p_occurred_at timestamptz, p_description text,
  p_amount numeric, p_destination_account_id uuid, p_notes text default null, p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_receivable_id uuid; v_remaining numeric; v_kind text;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'receivable_settlement', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligation_settlements where event_id = v_event_id) then return v_event_id; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_destination_account_id);
  select receivable_kind into v_kind from public.obligations
  where id = p_obligation_id and household_id = p_household_id and obligation_kind = 'receivable' for update;
  if not found or v_kind <> 'income' then raise exception 'Open income receivable does not belong to household'; end if;
  select remaining_amount into v_remaining from public.obligation_balances
  where obligation_id = p_obligation_id and household_id = p_household_id;
  if p_amount is null or p_amount <= 0 or p_amount > v_remaining then raise exception 'Settlement amount exceeds remaining receivable'; end if;
  v_receivable_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'receivable_settlement', p_occurred_at, p_description, p_amount, null, p_destination_account_id, p_destination_account_id, v_receivable_id, p_notes);
  insert into public.obligation_settlements(household_id, obligation_id, event_id, financial_transaction_id, amount, occurred_at, created_by)
  values (p_household_id, p_obligation_id, v_event_id, v_transaction_id, p_amount, coalesce(p_occurred_at, now()), auth.uid());
  return v_event_id;
end; $$;

create or replace function public.create_recovery_receivable_event(
  p_household_id uuid, p_source_event_id uuid, p_source_envelope_id uuid, p_occurred_at timestamptz,
  p_description text, p_amount numeric, p_debtor_name text default null, p_due_at date default null,
  p_notes text default null, p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_receivable_id uuid; v_recovery_id uuid;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'recovery_receivable', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligations where origin_event_id = v_event_id) then return v_event_id; end if;
  if not exists (select 1 from public.financial_events where id = p_source_event_id and household_id = p_household_id and event_type in ('cash_expense', 'debt_expense')) then raise exception 'Recovery source event must be a household expense'; end if;
  if p_source_envelope_id is not null and not exists (select 1 from public.envelope_movements where household_id = p_household_id and event_id = p_source_event_id and envelope_id = p_source_envelope_id and movement_type = 'consumption') then raise exception 'Recovery source envelope is not consumed by the source event'; end if;
  v_receivable_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
  v_recovery_id := public.ensure_financial_event_system_account(p_household_id, 'recovery');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'recovery_receivable', p_occurred_at, p_description, p_amount, null, null, v_receivable_id, v_recovery_id, p_notes);
  insert into public.obligations(household_id, obligation_kind, receivable_kind, origin_event_id, origin_transaction_id, recovery_source_event_id, recovery_source_envelope_id, initial_amount, counterparty_name, description, due_at, created_by)
  values (p_household_id, 'receivable', 'recovery', v_event_id, v_transaction_id, p_source_event_id, p_source_envelope_id, p_amount, nullif(trim(coalesce(p_debtor_name, '')), ''), trim(p_description), p_due_at, auth.uid());
  return v_event_id;
end; $$;

create or replace function public.settle_recovery_event(
  p_household_id uuid, p_obligation_id uuid, p_occurred_at timestamptz, p_description text,
  p_amount numeric, p_destination_account_id uuid, p_refund_source_envelope boolean default false,
  p_notes text default null, p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_receivable_id uuid; v_remaining numeric; v_source_event_id uuid; v_source_envelope_id uuid; v_available_refund numeric; v_group_id uuid;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'recovery_settlement', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligation_settlements where event_id = v_event_id) then return v_event_id; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_destination_account_id);
  select recovery_source_event_id, recovery_source_envelope_id into v_source_event_id, v_source_envelope_id
  from public.obligations where id = p_obligation_id and household_id = p_household_id
    and obligation_kind = 'receivable' and receivable_kind = 'recovery' for update;
  if not found then raise exception 'Open recovery receivable does not belong to household'; end if;
  select remaining_amount into v_remaining from public.obligation_balances
  where obligation_id = p_obligation_id and household_id = p_household_id;
  if p_amount is null or p_amount <= 0 or p_amount > v_remaining then raise exception 'Settlement amount exceeds remaining recovery'; end if;
  if p_refund_source_envelope and v_source_envelope_id is null then raise exception 'This recovery has no linked source envelope'; end if;
  if p_refund_source_envelope then
    select coalesce(sum(movements.amount) filter (where movements.movement_type = 'consumption'), 0)
         - coalesce(sum(movements.amount) filter (where movements.movement_type = 'refund'), 0)
    into v_available_refund
    from public.envelope_movements movements
    left join public.obligation_settlements settlements on settlements.event_id = movements.event_id
    left join public.obligations recovery_obligations on recovery_obligations.id = settlements.obligation_id
    where movements.household_id = p_household_id and movements.envelope_id = v_source_envelope_id
      and (movements.event_id = v_source_event_id or (
        recovery_obligations.recovery_source_event_id = v_source_event_id
        and recovery_obligations.recovery_source_envelope_id = v_source_envelope_id
      ));
    if p_amount > v_available_refund then raise exception 'Recovery refund exceeds unreimbursed source envelope consumption'; end if;
  end if;
  v_receivable_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'recovery_settlement', p_occurred_at, p_description, p_amount, null, p_destination_account_id, p_destination_account_id, v_receivable_id, p_notes);
  insert into public.obligation_settlements(household_id, obligation_id, event_id, financial_transaction_id, amount, occurred_at, created_by)
  values (p_household_id, p_obligation_id, v_event_id, v_transaction_id, p_amount, coalesce(p_occurred_at, now()), auth.uid());
  if p_refund_source_envelope then
    v_group_id := gen_random_uuid();
    insert into public.envelope_movements(household_id, event_id, envelope_id, financial_transaction_id, movement_group_id, movement_type, direction, amount, occurred_at, description, created_by)
    values (p_household_id, v_event_id, v_source_envelope_id, v_transaction_id, v_group_id, 'refund', 'inflow', p_amount, coalesce(p_occurred_at, now()), trim(p_description), auth.uid());
  end if;
  return v_event_id;
end; $$;

create or replace function public.allocate_budget_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_source_account_id uuid, p_destination_envelope_id uuid, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_to_allocate_id uuid; v_group_id uuid := gen_random_uuid();
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'budget_allocation', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.budget_funding_links where event_id = v_event_id) then return v_event_id; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_source_account_id);
  if p_amount is null or p_amount <= 0 then raise exception 'A positive amount is required'; end if;
  if not exists (select 1 from public.envelopes where id = p_destination_envelope_id and household_id = p_household_id and archived_at is null and not is_system) then raise exception 'Destination must be an active ordinary household envelope'; end if;
  v_to_allocate_id := public.ensure_household_system_envelope(p_household_id, 'to_allocate');
  insert into public.envelope_movements(household_id, event_id, envelope_id, movement_group_id, movement_type, direction, amount, occurred_at, description, created_by)
  values
    (p_household_id, v_event_id, v_to_allocate_id, v_group_id, 'transfer_out', 'outflow', p_amount, coalesce(p_occurred_at, now()), trim(p_description), auth.uid()),
    (p_household_id, v_event_id, p_destination_envelope_id, v_group_id, 'transfer_in', 'inflow', p_amount, coalesce(p_occurred_at, now()), trim(p_description), auth.uid());
  insert into public.budget_funding_links(household_id, event_id, source_account_id, envelope_id, amount, occurred_at, notes, created_by)
  values (p_household_id, v_event_id, p_source_account_id, p_destination_envelope_id, p_amount, coalesce(p_occurred_at, now()), nullif(trim(coalesce(p_notes, '')), ''), auth.uid());
  return v_event_id;
end; $$;

create or replace function public.create_account_transfer_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_source_account_id uuid, p_destination_account_id uuid, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'account_transfer', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.financial_transactions where event_id = v_event_id) then return v_event_id; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_source_account_id);
  perform public.assert_financial_event_ordinary_account(p_household_id, p_destination_account_id);
  if p_source_account_id = p_destination_account_id then raise exception 'Account transfer requires two different accounts'; end if;
  perform public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'transfer', p_occurred_at, p_description, p_amount, p_source_account_id, p_destination_account_id, p_destination_account_id, p_source_account_id, p_notes);
  return v_event_id;
end; $$;

create or replace function public.create_envelope_transfer_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_source_envelope_id uuid, p_destination_envelope_id uuid, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_group_id uuid := gen_random_uuid();
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'envelope_transfer', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.envelope_movements where event_id = v_event_id) then return v_event_id; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'A positive amount is required'; end if;
  if p_source_envelope_id is null or p_destination_envelope_id is null or p_source_envelope_id = p_destination_envelope_id then raise exception 'Envelope transfer requires two different envelopes'; end if;
  if not exists (select 1 from public.envelopes where id = p_source_envelope_id and household_id = p_household_id and archived_at is null and not is_system)
     or not exists (select 1 from public.envelopes where id = p_destination_envelope_id and household_id = p_household_id and archived_at is null and not is_system) then raise exception 'Envelope does not belong to household or is protected'; end if;
  insert into public.envelope_movements(household_id, event_id, envelope_id, movement_group_id, movement_type, direction, amount, occurred_at, description, created_by)
  values
    (p_household_id, v_event_id, p_source_envelope_id, v_group_id, 'transfer_out', 'outflow', p_amount, coalesce(p_occurred_at, now()), trim(p_description), auth.uid()),
    (p_household_id, v_event_id, p_destination_envelope_id, v_group_id, 'transfer_in', 'inflow', p_amount, coalesce(p_occurred_at, now()), trim(p_description), auth.uid());
  return v_event_id;
end; $$;

revoke all on function public.create_or_get_financial_event(uuid, text, timestamptz, text, text, uuid),
  public.ensure_financial_event_system_account(uuid, text), public.assert_financial_event_ordinary_account(uuid, uuid),
  public.insert_financial_event_ledger_transaction(uuid, uuid, text, timestamptz, text, numeric, uuid, uuid, uuid, uuid, text),
  public.insert_financial_event_consumptions(uuid, uuid, uuid, timestamptz, text, numeric, jsonb) from public, anon, authenticated;
revoke all on function public.create_cash_expense_event(uuid, timestamptz, text, numeric, uuid, jsonb, text, uuid),
  public.create_debt_expense_event(uuid, timestamptz, text, numeric, jsonb, text, date, text, uuid),
  public.settle_debt_event(uuid, uuid, timestamptz, text, numeric, uuid, text, uuid),
  public.create_income_receivable_event(uuid, timestamptz, text, numeric, text, date, text, uuid),
  public.settle_receivable_event(uuid, uuid, timestamptz, text, numeric, uuid, text, uuid),
  public.create_recovery_receivable_event(uuid, uuid, uuid, timestamptz, text, numeric, text, date, text, uuid),
  public.settle_recovery_event(uuid, uuid, timestamptz, text, numeric, uuid, boolean, text, uuid),
  public.allocate_budget_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid),
  public.create_account_transfer_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid),
  public.create_envelope_transfer_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid) from public, anon;
grant execute on function public.create_cash_expense_event(uuid, timestamptz, text, numeric, uuid, jsonb, text, uuid),
  public.create_debt_expense_event(uuid, timestamptz, text, numeric, jsonb, text, date, text, uuid),
  public.settle_debt_event(uuid, uuid, timestamptz, text, numeric, uuid, text, uuid),
  public.create_income_receivable_event(uuid, timestamptz, text, numeric, text, date, text, uuid),
  public.settle_receivable_event(uuid, uuid, timestamptz, text, numeric, uuid, text, uuid),
  public.create_recovery_receivable_event(uuid, uuid, uuid, timestamptz, text, numeric, text, date, text, uuid),
  public.settle_recovery_event(uuid, uuid, timestamptz, text, numeric, uuid, boolean, text, uuid),
  public.allocate_budget_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid),
  public.create_account_transfer_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid),
  public.create_envelope_transfer_event(uuid, timestamptz, text, numeric, uuid, uuid, text, uuid) to authenticated;

commit;
