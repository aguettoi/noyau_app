-- Enforce a source-expense-level cumulative ceiling for recovery receivables.
-- The source transaction row is locked so concurrent recovery creations for the
-- same expense serialize before the committed-recovery total is calculated.
create or replace function public.create_recovery_receivable_event(
  p_household_id uuid, p_source_event_id uuid, p_source_envelope_id uuid,
  p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_debtor_name text default null, p_due_at date default null,
  p_notes text default null, p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_event_id uuid;
  v_transaction_id uuid;
  v_receivable_id uuid;
  v_recovery_id uuid;
  v_source_amount numeric(14, 2);
  v_committed_recoveries numeric(14, 2);
  v_remaining_recoverable numeric(14, 2);
begin
  v_event_id := public.create_or_get_financial_event(
    p_household_id,
    'recovery_receivable',
    p_occurred_at,
    p_description,
    p_notes,
    p_idempotency_key
  );

  if exists (
    select 1 from public.obligations where origin_event_id = v_event_id
  ) then
    return v_event_id;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'A positive amount is required';
  end if;

  -- Locks the single canonical expense transaction. A concurrent recovery for
  -- this source waits here and then observes the first committed reservation.
  select transactions.amount
    into v_source_amount
  from public.financial_transactions transactions
  join public.financial_events source_event
    on source_event.id = transactions.event_id
   and source_event.household_id = transactions.household_id
  where source_event.id = p_source_event_id
    and source_event.household_id = p_household_id
    and source_event.event_type in ('cash_expense', 'debt_expense')
    and transactions.type in ('expense', 'debt_expense')
    and transactions.archived_at is null
  for update of transactions;

  if not found then
    raise exception 'Recovery source event must be a household expense';
  end if;

  if p_source_envelope_id is not null and not exists (
    select 1
    from public.envelope_movements movements
    where movements.household_id = p_household_id
      and movements.event_id = p_source_event_id
      and movements.envelope_id = p_source_envelope_id
      and movements.movement_type = 'consumption'
  ) then
    raise exception 'Recovery source envelope is not consumed by the source event';
  end if;

  -- Obligations are immutable in the current model: every persisted recovery
  -- remains a commitment until a dedicated reversal model exists.
  select coalesce(sum(obligations.initial_amount), 0)::numeric(14, 2)
    into v_committed_recoveries
  from public.obligations obligations
  where obligations.household_id = p_household_id
    and obligations.obligation_kind = 'receivable'
    and obligations.receivable_kind = 'recovery'
    and obligations.recovery_source_event_id = p_source_event_id;

  v_remaining_recoverable := v_source_amount - v_committed_recoveries;
  if v_remaining_recoverable <= 0 or p_amount > v_remaining_recoverable then
    raise exception 'Recovery amount exceeds remaining recoverable amount';
  end if;

  v_receivable_id := public.ensure_financial_event_system_account(
    p_household_id,
    'receivable'
  );
  v_recovery_id := public.ensure_financial_event_system_account(
    p_household_id,
    'recovery'
  );
  v_transaction_id := public.insert_financial_event_ledger_transaction(
    p_household_id,
    v_event_id,
    'recovery_receivable',
    p_occurred_at,
    p_description,
    p_amount,
    null,
    null,
    v_receivable_id,
    v_recovery_id,
    p_notes
  );
  insert into public.obligations(
    household_id,
    obligation_kind,
    receivable_kind,
    origin_event_id,
    origin_transaction_id,
    recovery_source_event_id,
    recovery_source_envelope_id,
    initial_amount,
    counterparty_name,
    description,
    due_at,
    created_by
  ) values (
    p_household_id,
    'receivable',
    'recovery',
    v_event_id,
    v_transaction_id,
    p_source_event_id,
    p_source_envelope_id,
    p_amount,
    nullif(trim(coalesce(p_debtor_name, '')), ''),
    trim(p_description),
    p_due_at,
    auth.uid()
  );
  return v_event_id;
end;
$$;

revoke all on function public.create_recovery_receivable_event(
  uuid, uuid, uuid, timestamptz, text, numeric, text, date, text, uuid
) from public, anon;
grant execute on function public.create_recovery_receivable_event(
  uuid, uuid, uuid, timestamptz, text, numeric, text, date, text, uuid
) to authenticated;
