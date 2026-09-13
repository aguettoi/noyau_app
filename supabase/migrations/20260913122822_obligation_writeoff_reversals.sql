begin;

-- Phase 2A: write-off reversals are immutable compensations of a specific
-- write-off.  They reopen only the obligation; they never move cash or
-- envelopes.  `reversal_of_event_id` remains the audit link to the source
-- FinancialEvent, while `reverses_adjustment_id` is the required business
-- link to the exact write-off being compensated.

alter table public.financial_events
  drop constraint if exists financial_events_event_type_check;

alter table public.financial_events
  add constraint financial_events_event_type_check check (event_type in (
    'cash_expense', 'cash_income', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement', 'recovery_receivable',
    'recovery_settlement', 'budget_allocation', 'account_transfer',
    'envelope_transfer', 'debt_writeoff', 'income_receivable_writeoff',
    'recovery_writeoff', 'recovery_reversal',
    'debt_settlement_reversal', 'receivable_settlement_reversal',
    'recovery_settlement_reversal',
    'debt_writeoff_reversal',
    'income_receivable_writeoff_reversal',
    'recovery_writeoff_reversal'
  ));

alter table public.financial_transactions
  drop constraint if exists financial_transactions_type_check;

alter table public.financial_transactions
  add constraint financial_transactions_type_check check (type in (
    'allocation', 'expense', 'transfer', 'adjustment', 'recovery', 'income',
    'opening_balance', 'correction', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement', 'recovery_receivable',
    'recovery_settlement', 'debt_writeoff', 'income_receivable_writeoff',
    'recovery_writeoff', 'recovery_reversal',
    'debt_settlement_reversal', 'receivable_settlement_reversal',
    'recovery_settlement_reversal',
    'debt_writeoff_reversal',
    'income_receivable_writeoff_reversal',
    'recovery_writeoff_reversal'
  ));

alter table public.obligation_adjustments
  add column if not exists reverses_adjustment_id uuid;

alter table public.obligation_adjustments
  drop constraint if exists obligation_adjustments_reverses_adjustment_id_fkey;

alter table public.obligation_adjustments
  add constraint obligation_adjustments_reverses_adjustment_id_fkey
  foreign key (reverses_adjustment_id)
  references public.obligation_adjustments(id)
  on delete restrict;

alter table public.obligation_adjustments
  drop constraint if exists obligation_adjustments_check;

alter table public.obligation_adjustments
  add constraint obligation_adjustments_kind_source_check check (
    (adjustment_kind = 'writeoff'
      and reversal_of_event_id is null
      and reverses_adjustment_id is null)
    or
    (adjustment_kind = 'reversal'
      and reversal_of_event_id is not null
      and reverses_adjustment_id is not null)
  );

create index if not exists obligation_adjustments_reverses_adjustment_idx
  on public.obligation_adjustments(reverses_adjustment_id, occurred_at)
  where reverses_adjustment_id is not null;

create or replace function public.assert_obligation_adjustment_reversal_source()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.obligation_adjustments%rowtype;
begin
  if new.adjustment_kind <> 'reversal' then
    return new;
  end if;

  select *
    into v_source
  from public.obligation_adjustments
  where id = new.reverses_adjustment_id
  for key share;

  if not found
     or v_source.adjustment_kind <> 'writeoff'
     or v_source.household_id <> new.household_id
     or v_source.obligation_id <> new.obligation_id
     or v_source.financial_event_id <> new.reversal_of_event_id then
    raise exception 'Write-off reversal must reference a write-off of the same obligation and household';
  end if;

  return new;
end;
$$;

drop trigger if exists obligation_adjustments_reversal_source on public.obligation_adjustments;
create trigger obligation_adjustments_reversal_source
before insert on public.obligation_adjustments
for each row execute function public.assert_obligation_adjustment_reversal_source();

-- Canonical net invariant, shared by the view and both deferred guards:
-- remaining = initial - gross settlements + settlement reversals
--             - gross write-offs + write-off reversals.
create or replace view public.obligation_balances
with (security_invoker = true)
as
select
  o.household_id,
  o.id as obligation_id,
  o.obligation_kind,
  o.receivable_kind,
  o.origin_event_id,
  o.origin_transaction_id,
  o.origin_envelope_id,
  o.recovery_source_event_id,
  o.recovery_source_envelope_id,
  o.initial_amount,
  (coalesce(s.gross_settled_amount, 0) - coalesce(sr.settlement_reversed_amount, 0))::numeric(14, 2) as settled_amount,
  (o.initial_amount
    - coalesce(s.gross_settled_amount, 0)
    + coalesce(sr.settlement_reversed_amount, 0)
    - coalesce(a.written_off_amount, 0)
    + coalesce(a.writeoff_reversed_amount, 0))::numeric(14, 2) as remaining_amount,
  case
    when (o.initial_amount
      - coalesce(s.gross_settled_amount, 0)
      + coalesce(sr.settlement_reversed_amount, 0)
      - coalesce(a.written_off_amount, 0)
      + coalesce(a.writeoff_reversed_amount, 0)) > 0 then 'open'
    when coalesce(a.written_off_amount, 0) - coalesce(a.writeoff_reversed_amount, 0) > 0 then 'written_off'
    else 'settled'
  end as status,
  o.counterparty_name,
  o.description,
  o.due_at,
  o.created_at,
  (o.due_at is not null and o.due_at < current_date
    and (o.initial_amount
      - coalesce(s.gross_settled_amount, 0)
      + coalesce(sr.settlement_reversed_amount, 0)
      - coalesce(a.written_off_amount, 0)
      + coalesce(a.writeoff_reversed_amount, 0)) > 0) as is_overdue
  ,coalesce(a.written_off_amount, 0)::numeric(14, 2) as written_off_amount
  ,coalesce(a.writeoff_reversed_amount, 0)::numeric(14, 2) as reversed_amount
  ,coalesce(s.gross_settled_amount, 0)::numeric(14, 2) as gross_settled_amount
  ,coalesce(sr.settlement_reversed_amount, 0)::numeric(14, 2) as settlement_reversed_amount
  ,(coalesce(s.gross_settled_amount, 0) - coalesce(sr.settlement_reversed_amount, 0))::numeric(14, 2) as net_settled_amount
  ,coalesce(a.writeoff_reversed_amount, 0)::numeric(14, 2) as writeoff_reversed_amount
  ,(coalesce(a.written_off_amount, 0) - coalesce(a.writeoff_reversed_amount, 0))::numeric(14, 2) as net_written_off_amount
from public.obligations o
left join lateral (
  select coalesce(sum(amount), 0)::numeric(14, 2) as gross_settled_amount
  from public.obligation_settlements
  where obligation_id = o.id
) s on true
left join lateral (
  select coalesce(sum(amount), 0)::numeric(14, 2) as settlement_reversed_amount
  from public.obligation_settlement_reversals
  where obligation_id = o.id
) sr on true
left join lateral (
  select
    coalesce(sum(amount) filter (where adjustment_kind = 'writeoff'), 0)::numeric(14, 2) as written_off_amount,
    coalesce(sum(amount) filter (where adjustment_kind = 'reversal'), 0)::numeric(14, 2) as writeoff_reversed_amount
  from public.obligation_adjustments
  where obligation_id = o.id
) a on true;

create or replace function public.assert_obligation_settlement_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_initial numeric(14, 2);
  v_gross_settlements numeric(14, 2);
  v_settlement_reversals numeric(14, 2);
  v_writeoffs numeric(14, 2);
  v_writeoff_reversals numeric(14, 2);
begin
  select initial_amount into v_initial
  from public.obligations
  where id = new.obligation_id and household_id = new.household_id;

  select coalesce(sum(amount), 0) into v_gross_settlements
  from public.obligation_settlements
  where obligation_id = new.obligation_id and household_id = new.household_id;

  select coalesce(sum(amount), 0) into v_settlement_reversals
  from public.obligation_settlement_reversals
  where obligation_id = new.obligation_id and household_id = new.household_id;

  select
    coalesce(sum(amount) filter (where adjustment_kind = 'writeoff'), 0),
    coalesce(sum(amount) filter (where adjustment_kind = 'reversal'), 0)
  into v_writeoffs, v_writeoff_reversals
  from public.obligation_adjustments
  where obligation_id = new.obligation_id and household_id = new.household_id;

  if v_initial is null
     or v_gross_settlements - v_settlement_reversals
        + v_writeoffs - v_writeoff_reversals > v_initial then
    raise exception 'An obligation cannot be settled above its remaining amount';
  end if;
  return null;
end;
$$;

create or replace function public.assert_obligation_adjustment_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_initial numeric(14, 2);
  v_gross_settlements numeric(14, 2);
  v_settlement_reversals numeric(14, 2);
  v_writeoffs numeric(14, 2);
  v_writeoff_reversals numeric(14, 2);
begin
  select initial_amount into v_initial
  from public.obligations
  where id = new.obligation_id and household_id = new.household_id;

  select coalesce(sum(amount), 0) into v_gross_settlements
  from public.obligation_settlements
  where obligation_id = new.obligation_id and household_id = new.household_id;

  select coalesce(sum(amount), 0) into v_settlement_reversals
  from public.obligation_settlement_reversals
  where obligation_id = new.obligation_id and household_id = new.household_id;

  select
    coalesce(sum(amount) filter (where adjustment_kind = 'writeoff'), 0),
    coalesce(sum(amount) filter (where adjustment_kind = 'reversal'), 0)
  into v_writeoffs, v_writeoff_reversals
  from public.obligation_adjustments
  where obligation_id = new.obligation_id and household_id = new.household_id;

  if v_initial is null
     or v_gross_settlements - v_settlement_reversals
        + v_writeoffs - v_writeoff_reversals > v_initial then
    raise exception 'An obligation cannot exceed its initial amount through settlements and adjustments';
  end if;
  return null;
end;
$$;

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

  if p_amount is null or p_amount <= 0 then
    raise exception 'Write-off reversal amount must be positive';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 1 and 280 then
    raise exception 'A write-off reversal reason is required';
  end if;

  -- Lock order: obligation first, then source write-off, then its reversals.
  -- Every obligation mutation locks the same parent row, serialising its cap.
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

  -- Lock all existing compensations before calculating the per-write-off cap.
  perform 1
  from public.obligation_adjustments
  where reverses_adjustment_id = p_source_adjustment_id
  for update;

  select coalesce(sum(amount), 0)
    into v_reversed_amount
  from public.obligation_adjustments
  where reverses_adjustment_id = p_source_adjustment_id;

  if p_amount > v_source_amount - v_reversed_amount then
    raise exception 'Write-off reversal exceeds the amount still reversible';
  end if;

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

  v_event_id := public.create_or_get_financial_event(
    p_household_id,
    v_event_type,
    p_occurred_at,
    'Annulation abandon : ' || trim(p_reason),
    p_notes,
    p_idempotency_key
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

create or replace function public.reverse_debt_writeoff_event(
  p_household_id uuid, p_source_adjustment_id uuid, p_occurred_at timestamptz,
  p_amount numeric, p_reason text, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language sql
security definer
set search_path = public
as $$
  select public.reverse_obligation_writeoff_event(
    p_household_id, p_source_adjustment_id, p_occurred_at, p_amount,
    p_reason, p_notes, p_idempotency_key, 'debt'
  );
$$;

create or replace function public.reverse_income_receivable_writeoff_event(
  p_household_id uuid, p_source_adjustment_id uuid, p_occurred_at timestamptz,
  p_amount numeric, p_reason text, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language sql
security definer
set search_path = public
as $$
  select public.reverse_obligation_writeoff_event(
    p_household_id, p_source_adjustment_id, p_occurred_at, p_amount,
    p_reason, p_notes, p_idempotency_key, 'income'
  );
$$;

create or replace function public.reverse_recovery_writeoff_event(
  p_household_id uuid, p_source_adjustment_id uuid, p_occurred_at timestamptz,
  p_amount numeric, p_reason text, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language sql
security definer
set search_path = public
as $$
  select public.reverse_obligation_writeoff_event(
    p_household_id, p_source_adjustment_id, p_occurred_at, p_amount,
    p_reason, p_notes, p_idempotency_key, 'recovery'
  );
$$;

revoke all on function public.reverse_obligation_writeoff_event(uuid, uuid, timestamptz, numeric, text, text, uuid, text) from public, anon, authenticated;
revoke all on function public.reverse_debt_writeoff_event(uuid, uuid, timestamptz, numeric, text, text, uuid) from public, anon;
revoke all on function public.reverse_income_receivable_writeoff_event(uuid, uuid, timestamptz, numeric, text, text, uuid) from public, anon;
revoke all on function public.reverse_recovery_writeoff_event(uuid, uuid, timestamptz, numeric, text, text, uuid) from public, anon;
grant execute on function public.reverse_debt_writeoff_event(uuid, uuid, timestamptz, numeric, text, text, uuid) to authenticated;
grant execute on function public.reverse_income_receivable_writeoff_event(uuid, uuid, timestamptz, numeric, text, text, uuid) to authenticated;
grant execute on function public.reverse_recovery_writeoff_event(uuid, uuid, timestamptz, numeric, text, text, uuid) to authenticated;

commit;
