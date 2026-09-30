-- Canonical opening of pre-existing debts at cutover. This is deliberately
-- audit-only: no current-period expense, account posting, or envelope movement.
begin;

alter table public.financial_events
  drop constraint if exists financial_events_event_type_check;
alter table public.financial_events
  add constraint financial_events_event_type_check check (event_type in (
    'cash_expense', 'cash_income', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement', 'recovery_receivable',
    'recovery_settlement', 'budget_allocation', 'account_transfer',
    'envelope_transfer', 'debt_writeoff', 'income_receivable_writeoff',
    'recovery_writeoff', 'recovery_reversal', 'debt_settlement_reversal',
    'receivable_settlement_reversal', 'recovery_settlement_reversal',
    'debt_writeoff_reversal', 'income_receivable_writeoff_reversal',
    'recovery_writeoff_reversal', 'account_opening', 'envelope_opening',
    'obligation_opening'
  ));

alter table public.obligations
  alter column origin_transaction_id drop not null;

create unique index if not exists obligations_origin_event_unique_idx
  on public.obligations(origin_event_id);

create or replace function public.assert_obligation_origin_consistency()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_event_type text;
begin
  select event_type into v_event_type
  from public.financial_events
  where id = new.origin_event_id and household_id = new.household_id;

  if v_event_type is null then
    raise exception 'Obligation origin event does not belong to household';
  end if;

  if v_event_type = 'obligation_opening' then
    if new.obligation_kind <> 'debt'
       or new.receivable_kind is not null
       or new.origin_transaction_id is not null
       or new.origin_envelope_id is not null
       or new.recovery_source_event_id is not null
       or new.recovery_source_envelope_id is not null then
      raise exception 'Obligation opening must be an audit-only debt opening';
    end if;
  elsif new.origin_transaction_id is null then
    raise exception 'Only obligation openings may omit an origin transaction';
  end if;

  return new;
end;
$$;

drop trigger if exists obligations_origin_consistency on public.obligations;
create trigger obligations_origin_consistency
before insert on public.obligations
for each row execute function public.assert_obligation_origin_consistency();

create or replace function public.create_obligation_opening_event(
  p_household_id uuid,
  p_occurred_at timestamptz,
  p_description text,
  p_amount numeric,
  p_creditor_name text default null,
  p_due_at date default null,
  p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_event_id uuid;
  v_existing public.obligations%rowtype;
begin
  if p_occurred_at is null then
    raise exception 'Opening effective date is required';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Opening amount must be positive';
  end if;
  if nullif(trim(p_description), '') is null then
    raise exception 'Opening description is required';
  end if;

  v_event_id := public.create_or_get_financial_event(
    p_household_id,
    'obligation_opening',
    p_occurred_at,
    trim(p_description),
    p_notes,
    p_idempotency_key
  );

  -- Serialises concurrent replays of the same idempotency key.
  perform 1 from public.financial_events where id = v_event_id for update;

  select * into v_existing
  from public.obligations
  where household_id = p_household_id and origin_event_id = v_event_id;

  if found then
    if v_existing.obligation_kind <> 'debt'
       or v_existing.initial_amount <> p_amount
       or v_existing.description <> trim(p_description)
       or coalesce(v_existing.counterparty_name, '') <>
          coalesce(nullif(trim(p_creditor_name), ''), '')
       or v_existing.due_at is distinct from p_due_at then
      raise exception 'Obligation opening idempotency conflict';
    end if;
    return v_event_id;
  end if;

  insert into public.obligations(
    household_id,
    obligation_kind,
    receivable_kind,
    origin_event_id,
    origin_transaction_id,
    initial_amount,
    counterparty_name,
    description,
    due_at,
    created_by
  ) values (
    p_household_id,
    'debt',
    null,
    v_event_id,
    null,
    p_amount,
    nullif(trim(p_creditor_name), ''),
    trim(p_description),
    p_due_at,
    auth.uid()
  );

  return v_event_id;
end;
$$;

revoke all on function public.create_obligation_opening_event(
  uuid,timestamptz,text,numeric,text,date,text,uuid
) from public, anon, authenticated;
grant execute on function public.create_obligation_opening_event(
  uuid,timestamptz,text,numeric,text,date,text,uuid
) to authenticated;

revoke all on function public.assert_obligation_origin_consistency()
  from public, anon, authenticated;

commit;
