begin;

-- The first Phase 2A migration created the write-off reversal model.  This
-- additive correction makes a completed idempotent replay win before the
-- mutable per-write-off cap is checked.  It never changes existing events.
create or replace function public.reverse_obligation_writeoff_event(
  p_household_id uuid,
  p_source_adjustment_id uuid,
  p_occurred_at timestamptz,
  p_amount numeric,
  p_reason text,
  p_notes text,
  p_idempotency_key uuid,
  p_expected_kind text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_transaction_id uuid;
  v_obligation_id uuid;
  v_source_event_id uuid;
  v_source_amount numeric(14, 2);
  v_reversed_amount numeric(14, 2);
  v_event_type text;
  v_transaction_type text;
  v_debit_account_id uuid;
  v_credit_account_id uuid;
begin
  perform public.assert_household_access(p_household_id);

  v_event_type := case p_expected_kind
    when 'debt' then 'debt_writeoff_reversal'
    when 'income' then 'income_receivable_writeoff_reversal'
    when 'recovery' then 'recovery_writeoff_reversal'
    else null
  end;
  v_transaction_type := v_event_type;
  if v_event_type is null then
    raise exception 'Unsupported write-off reversal kind';
  end if;
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required';
  end if;

  -- A completed retry is immutable: return it before inspecting the mutable
  -- source cap. A different event type on the same key remains an error.
  select id into v_event_id
  from public.financial_events
  where household_id = p_household_id
    and idempotency_key = p_idempotency_key;
  if found then
    if (select event_type from public.financial_events where id = v_event_id) <> v_event_type then
      raise exception 'Idempotency key was already used for a different event type';
    end if;
    if exists (
      select 1 from public.obligation_adjustments
      where financial_event_id = v_event_id
    ) then
      return v_event_id;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Write-off reversal amount must be positive';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 1 and 280 then
    raise exception 'A write-off reversal reason is required';
  end if;

  -- Canonical lock order: obligation, source write-off, sibling reversals.
  select o.id, a.financial_event_id, a.amount
    into v_obligation_id, v_source_event_id, v_source_amount
  from public.obligations o
  join public.obligation_adjustments a
    on a.obligation_id = o.id and a.household_id = o.household_id
  where a.id = p_source_adjustment_id
    and a.household_id = p_household_id
    and a.adjustment_kind = 'writeoff'
    and ((p_expected_kind = 'debt' and o.obligation_kind = 'debt')
      or (p_expected_kind = 'income' and o.obligation_kind = 'receivable' and o.receivable_kind = 'income')
      or (p_expected_kind = 'recovery' and o.obligation_kind = 'receivable' and o.receivable_kind = 'recovery'))
  for update of o, a;
  if not found then
    raise exception 'Source write-off does not belong to the expected household obligation';
  end if;

  perform 1
  from public.obligation_adjustments
  where reverses_adjustment_id = p_source_adjustment_id
  for update;
  select coalesce(sum(amount), 0) into v_reversed_amount
  from public.obligation_adjustments
  where reverses_adjustment_id = p_source_adjustment_id;
  if p_amount > v_source_amount - v_reversed_amount then
    raise exception 'Write-off reversal exceeds the amount still reversible';
  end if;

  v_event_id := public.create_or_get_financial_event(
    p_household_id, v_event_type, p_occurred_at,
    'Annulation abandon : ' || trim(p_reason), p_notes, p_idempotency_key
  );
  if exists (
    select 1 from public.obligation_adjustments
    where financial_event_id = v_event_id
  ) then
    return v_event_id;
  end if;

  if p_expected_kind = 'debt' then
    v_debit_account_id := public.ensure_financial_event_system_account(p_household_id, 'debt_writeoff_gain');
    v_credit_account_id := public.ensure_financial_event_system_account(p_household_id, 'debt');
  elsif p_expected_kind = 'income' then
    v_debit_account_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
    v_credit_account_id := public.ensure_financial_event_system_account(p_household_id, 'receivable_loss');
  else
    v_debit_account_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
    v_credit_account_id := public.ensure_financial_event_system_account(p_household_id, 'recovery');
  end if;

  v_transaction_id := public.insert_financial_event_ledger_transaction(
    p_household_id, v_event_id, v_transaction_type, p_occurred_at,
    'Annulation abandon : ' || trim(p_reason), p_amount,
    null, null, v_debit_account_id, v_credit_account_id, p_notes
  );
  insert into public.obligation_adjustments(
    household_id, obligation_id, financial_event_id, financial_transaction_id,
    adjustment_kind, amount, occurred_at, reason, notes, reversal_of_event_id,
    reverses_adjustment_id, created_by
  ) values (
    p_household_id, v_obligation_id, v_event_id, v_transaction_id,
    'reversal', p_amount, coalesce(p_occurred_at, now()), trim(p_reason),
    nullif(trim(coalesce(p_notes, '')), ''), v_source_event_id,
    p_source_adjustment_id, auth.uid()
  );
  return v_event_id;
end;
$$;

commit;
