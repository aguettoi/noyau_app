-- Immutable definitive obligation write-offs. Recovery reversals are not part
-- of this phase: the table reserves the vocabulary but no reversal RPC exists.
begin;

alter table public.financial_events
  drop constraint if exists financial_events_event_type_check;
alter table public.financial_events
  add constraint financial_events_event_type_check check (event_type in (
    'cash_expense', 'cash_income', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement', 'recovery_receivable',
    'recovery_settlement', 'budget_allocation', 'account_transfer',
    'envelope_transfer', 'debt_writeoff', 'income_receivable_writeoff',
    'recovery_writeoff', 'recovery_reversal'
  ));

alter table public.financial_transactions
  drop constraint if exists financial_transactions_type_check;
alter table public.financial_transactions
  add constraint financial_transactions_type_check check (type in (
    'allocation', 'expense', 'transfer', 'adjustment', 'recovery', 'income',
    'opening_balance', 'correction', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement', 'recovery_receivable',
    'recovery_settlement', 'debt_writeoff', 'income_receivable_writeoff',
    'recovery_writeoff', 'recovery_reversal'
  ));

create table public.obligation_adjustments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  obligation_id uuid not null,
  financial_event_id uuid not null,
  financial_transaction_id uuid not null,
  adjustment_kind text not null check (adjustment_kind in ('writeoff', 'reversal')),
  amount numeric(14, 2) not null check (amount > 0),
  occurred_at timestamptz not null,
  reason text not null check (char_length(trim(reason)) between 1 and 280),
  notes text,
  reversal_of_event_id uuid,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (financial_event_id),
  foreign key (obligation_id, household_id)
    references public.obligations(id, household_id) on delete restrict,
  foreign key (financial_event_id, household_id)
    references public.financial_events(id, household_id) on delete restrict,
  foreign key (financial_transaction_id, household_id)
    references public.financial_transactions(id, household_id) on delete restrict,
  foreign key (reversal_of_event_id, household_id)
    references public.financial_events(id, household_id) on delete restrict,
  foreign key (household_id, created_by)
    references public.household_members(household_id, user_id) on delete restrict,
  check (
    (adjustment_kind = 'writeoff' and reversal_of_event_id is null)
    or (adjustment_kind = 'reversal' and reversal_of_event_id is not null)
  )
);

create index obligation_adjustments_obligation_idx
  on public.obligation_adjustments(obligation_id, occurred_at);

create or replace view public.obligation_balances
with (security_invoker = true)
as
select
  obligations.household_id,
  obligations.id as obligation_id,
  obligations.obligation_kind,
  obligations.receivable_kind,
  obligations.origin_event_id,
  obligations.origin_transaction_id,
  obligations.origin_envelope_id,
  obligations.recovery_source_event_id,
  obligations.recovery_source_envelope_id,
  obligations.initial_amount,
  coalesce(settlements.settled_amount, 0)::numeric(14, 2) as settled_amount,
  (obligations.initial_amount - coalesce(settlements.settled_amount, 0)
    - coalesce(adjustments.written_off_amount, 0)
    - coalesce(adjustments.reversed_amount, 0))::numeric(14, 2) as remaining_amount,
  case
    when obligations.initial_amount - coalesce(settlements.settled_amount, 0)
      - coalesce(adjustments.written_off_amount, 0)
      - coalesce(adjustments.reversed_amount, 0) > 0 then 'open'
    when coalesce(adjustments.reversed_amount, 0) > 0 then 'reversed'
    when coalesce(adjustments.written_off_amount, 0) > 0 then 'written_off'
    else 'settled'
  end as status,
  obligations.counterparty_name,
  obligations.description,
  obligations.due_at,
  obligations.created_at,
  (obligations.due_at is not null and obligations.due_at < current_date
    and obligations.initial_amount > coalesce(settlements.settled_amount, 0)
      + coalesce(adjustments.written_off_amount, 0)
      + coalesce(adjustments.reversed_amount, 0)) as is_overdue,
  coalesce(adjustments.written_off_amount, 0)::numeric(14, 2) as written_off_amount,
  coalesce(adjustments.reversed_amount, 0)::numeric(14, 2) as reversed_amount
from public.obligations
left join lateral (
  select coalesce(sum(amount), 0)::numeric(14, 2) as settled_amount
  from public.obligation_settlements
  where obligation_id = obligations.id
) settlements on true
left join lateral (
  select
    coalesce(sum(amount) filter (where adjustment_kind = 'writeoff'), 0)::numeric(14, 2) as written_off_amount,
    coalesce(sum(amount) filter (where adjustment_kind = 'reversal'), 0)::numeric(14, 2) as reversed_amount
  from public.obligation_adjustments
  where obligation_id = obligations.id
) adjustments on true;

create or replace function public.assert_obligation_adjustment_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_initial numeric(14, 2); v_total numeric(14, 2);
begin
  select initial_amount into v_initial
  from public.obligations
  where id = new.obligation_id and household_id = new.household_id;
  select coalesce(sum(amount), 0) into v_total
  from public.obligation_settlements
  where obligation_id = new.obligation_id and household_id = new.household_id;
  select v_total + coalesce(sum(amount), 0) into v_total
  from public.obligation_adjustments
  where obligation_id = new.obligation_id and household_id = new.household_id;
  if v_initial is null or v_total > v_initial then
    raise exception 'An obligation cannot exceed its initial amount through settlements and adjustments';
  end if;
  return null;
end;
$$;

create or replace function public.assert_obligation_settlement_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_initial numeric(14, 2); v_total numeric(14, 2);
begin
  select initial_amount into v_initial
  from public.obligations
  where id = new.obligation_id and household_id = new.household_id;
  select coalesce(sum(amount), 0) into v_total
  from public.obligation_settlements
  where obligation_id = new.obligation_id and household_id = new.household_id;
  select v_total + coalesce(sum(amount), 0) into v_total
  from public.obligation_adjustments
  where obligation_id = new.obligation_id and household_id = new.household_id;
  if v_initial is null or v_total > v_initial then
    raise exception 'An obligation cannot be settled above its remaining amount';
  end if;
  return null;
end;
$$;

create constraint trigger obligation_adjustments_limit
after insert on public.obligation_adjustments
deferrable initially deferred for each row
execute function public.assert_obligation_adjustment_limit();

create trigger obligation_adjustments_immutable
before update or delete on public.obligation_adjustments
for each row execute function public.prevent_financial_event_mutation();

alter table public.obligation_adjustments enable row level security;
revoke all on public.obligation_adjustments from public, anon, authenticated;
grant select on public.obligation_adjustments to authenticated;
create policy "members read obligation adjustments" on public.obligation_adjustments
for select using (public.is_household_member(household_id));

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
    when 'debt_writeoff_gain' then 'Système — Gains d’abandon de dettes'
    when 'receivable_loss' then 'Système — Pertes sur créances'
    else null
  end;
begin
  if v_name is null then raise exception 'Unsupported FinancialEvent counterpart'; end if;
  select id, is_system into v_account_id, v_is_system from public.accounts
  where household_id = p_household_id and name = v_name;
  if found then
    if not v_is_system then raise exception 'A reserved FinancialEvent account name is already used'; end if;
    return v_account_id;
  end if;
  insert into public.accounts(household_id, name, kind, is_system)
  values (p_household_id, v_name, 'ledger', true)
  returning id into v_account_id;
  return v_account_id;
end;
$$;

create or replace function public.writeoff_debt_event(
  p_household_id uuid, p_obligation_id uuid, p_occurred_at timestamptz,
  p_amount numeric, p_reason text, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_debt_id uuid; v_gain_id uuid; v_remaining numeric;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'debt_writeoff', p_occurred_at, p_reason, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligation_adjustments where financial_event_id = v_event_id) then return v_event_id; end if;
  perform 1 from public.obligations where id = p_obligation_id and household_id = p_household_id and obligation_kind = 'debt' for update;
  if not found then raise exception 'Open debt obligation does not belong to household'; end if;
  select remaining_amount into v_remaining from public.obligation_balances where obligation_id = p_obligation_id and household_id = p_household_id;
  if p_amount is null or p_amount <= 0 or p_amount > v_remaining then raise exception 'Write-off amount exceeds remaining debt'; end if;
  v_debt_id := public.ensure_financial_event_system_account(p_household_id, 'debt');
  v_gain_id := public.ensure_financial_event_system_account(p_household_id, 'debt_writeoff_gain');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'debt_writeoff', p_occurred_at, p_reason, p_amount, null, null, v_debt_id, v_gain_id, p_notes);
  insert into public.obligation_adjustments(household_id, obligation_id, financial_event_id, financial_transaction_id, adjustment_kind, amount, occurred_at, reason, notes, created_by)
  values (p_household_id, p_obligation_id, v_event_id, v_transaction_id, 'writeoff', p_amount, coalesce(p_occurred_at, now()), trim(p_reason), nullif(trim(coalesce(p_notes, '')), ''), auth.uid());
  return v_event_id;
end;
$$;

create or replace function public.writeoff_income_receivable_event(
  p_household_id uuid, p_obligation_id uuid, p_occurred_at timestamptz,
  p_amount numeric, p_reason text, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_loss_id uuid; v_receivable_id uuid; v_remaining numeric;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'income_receivable_writeoff', p_occurred_at, p_reason, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligation_adjustments where financial_event_id = v_event_id) then return v_event_id; end if;
  perform 1 from public.obligations where id = p_obligation_id and household_id = p_household_id and obligation_kind = 'receivable' and receivable_kind = 'income' for update;
  if not found then raise exception 'Open income receivable does not belong to household'; end if;
  select remaining_amount into v_remaining from public.obligation_balances where obligation_id = p_obligation_id and household_id = p_household_id;
  if p_amount is null or p_amount <= 0 or p_amount > v_remaining then raise exception 'Write-off amount exceeds remaining receivable'; end if;
  v_loss_id := public.ensure_financial_event_system_account(p_household_id, 'receivable_loss');
  v_receivable_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'income_receivable_writeoff', p_occurred_at, p_reason, p_amount, null, null, v_loss_id, v_receivable_id, p_notes);
  insert into public.obligation_adjustments(household_id, obligation_id, financial_event_id, financial_transaction_id, adjustment_kind, amount, occurred_at, reason, notes, created_by)
  values (p_household_id, p_obligation_id, v_event_id, v_transaction_id, 'writeoff', p_amount, coalesce(p_occurred_at, now()), trim(p_reason), nullif(trim(coalesce(p_notes, '')), ''), auth.uid());
  return v_event_id;
end;
$$;

create or replace function public.writeoff_recovery_event(
  p_household_id uuid, p_obligation_id uuid, p_occurred_at timestamptz,
  p_amount numeric, p_reason text, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_recovery_id uuid; v_receivable_id uuid; v_remaining numeric;
begin
  v_event_id := public.create_or_get_financial_event(p_household_id, 'recovery_writeoff', p_occurred_at, p_reason, p_notes, p_idempotency_key);
  if exists (select 1 from public.obligation_adjustments where financial_event_id = v_event_id) then return v_event_id; end if;
  perform 1 from public.obligations where id = p_obligation_id and household_id = p_household_id and obligation_kind = 'receivable' and receivable_kind = 'recovery' for update;
  if not found then raise exception 'Open recovery receivable does not belong to household'; end if;
  select remaining_amount into v_remaining from public.obligation_balances where obligation_id = p_obligation_id and household_id = p_household_id;
  if p_amount is null or p_amount <= 0 or p_amount > v_remaining then raise exception 'Write-off amount exceeds remaining recovery'; end if;
  v_recovery_id := public.ensure_financial_event_system_account(p_household_id, 'recovery');
  v_receivable_id := public.ensure_financial_event_system_account(p_household_id, 'receivable');
  v_transaction_id := public.insert_financial_event_ledger_transaction(p_household_id, v_event_id, 'recovery_writeoff', p_occurred_at, p_reason, p_amount, null, null, v_recovery_id, v_receivable_id, p_notes);
  insert into public.obligation_adjustments(household_id, obligation_id, financial_event_id, financial_transaction_id, adjustment_kind, amount, occurred_at, reason, notes, created_by)
  values (p_household_id, p_obligation_id, v_event_id, v_transaction_id, 'writeoff', p_amount, coalesce(p_occurred_at, now()), trim(p_reason), nullif(trim(coalesce(p_notes, '')), ''), auth.uid());
  return v_event_id;
end;
$$;

revoke all on function public.writeoff_debt_event(uuid, uuid, timestamptz, numeric, text, text, uuid) from public, anon;
revoke all on function public.writeoff_income_receivable_event(uuid, uuid, timestamptz, numeric, text, text, uuid) from public, anon;
revoke all on function public.writeoff_recovery_event(uuid, uuid, timestamptz, numeric, text, text, uuid) from public, anon;
grant execute on function public.writeoff_debt_event(uuid, uuid, timestamptz, numeric, text, text, uuid) to authenticated;
grant execute on function public.writeoff_income_receivable_event(uuid, uuid, timestamptz, numeric, text, text, uuid) to authenticated;
grant execute on function public.writeoff_recovery_event(uuid, uuid, timestamptz, numeric, text, text, uuid) to authenticated;

commit;
