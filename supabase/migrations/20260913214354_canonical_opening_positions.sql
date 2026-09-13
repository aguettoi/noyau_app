-- Canonical cutover opening positions. No historical balances are rewritten.
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
    'recovery_writeoff_reversal', 'account_opening', 'envelope_opening'
  ));

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
    when 'debt_writeoff_gain' then 'Système — Gains d’abandon de dettes'
    when 'receivable_loss' then 'Système — Pertes sur créances'
    when 'opening_balance' then 'Système — Soldes d’ouverture'
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

create or replace function public.create_account_opening_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text,
  p_amount numeric, p_account_id uuid, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_transaction_id uuid; v_opening_id uuid;
begin
  v_event_id := public.create_or_get_financial_event(
    p_household_id, 'account_opening', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.financial_transactions where event_id = v_event_id) then return v_event_id; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Opening amount must be positive'; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_account_id);
  perform 1 from public.accounts where id = p_account_id and household_id = p_household_id for update;
  v_opening_id := public.ensure_financial_event_system_account(p_household_id, 'opening_balance');
  v_transaction_id := public.insert_financial_event_ledger_transaction(
    p_household_id, v_event_id, 'opening_balance', p_occurred_at, p_description,
    p_amount, null, p_account_id, p_account_id, v_opening_id, p_notes);
  return v_event_id;
end;
$$;

create or replace function public.create_envelope_opening_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text,
  p_openings jsonb, p_notes text default null, p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_event_id uuid; v_item jsonb; v_envelope_id uuid; v_amount numeric; v_seen uuid[] := '{}';
begin
  v_event_id := public.create_or_get_financial_event(
    p_household_id, 'envelope_opening', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.envelope_movements where event_id = v_event_id) then return v_event_id; end if;
  if jsonb_typeof(p_openings) <> 'array' or jsonb_array_length(p_openings) = 0 then
    raise exception 'At least one envelope opening is required';
  end if;
  for v_item in select value from jsonb_array_elements(p_openings) loop
    v_envelope_id := nullif(v_item->>'envelope_id','')::uuid;
    v_amount := nullif(v_item->>'amount','')::numeric;
    if v_envelope_id is null or v_amount is null or v_amount <= 0 then raise exception 'Each envelope opening requires a positive amount and envelope'; end if;
    if v_envelope_id = any(v_seen) then raise exception 'An envelope can appear only once in an opening'; end if;
    if not exists (select 1 from public.envelopes where id=v_envelope_id and household_id=p_household_id and archived_at is null) then raise exception 'Opening envelope is not an active household envelope'; end if;
    v_seen := array_append(v_seen,v_envelope_id);
  end loop;
  insert into public.envelope_movements(household_id,event_id,envelope_id,movement_type,direction,amount,occurred_at,description,created_by)
  select p_household_id,v_event_id,(value->>'envelope_id')::uuid,'opening','inflow',(value->>'amount')::numeric,
    coalesce(p_occurred_at,now()),trim(p_description),auth.uid()
  from jsonb_array_elements(p_openings);
  return v_event_id;
end;
$$;

create or replace function public.assert_envelope_opening_group_trigger()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.event_id is not null and exists (
    select 1 from public.financial_events
    where id = new.event_id and household_id = new.household_id
      and event_type = 'envelope_opening'
  ) then
    return null;
  end if;
  perform public.assert_envelope_opening_group(new.movement_group_id);
  return null;
end;
$$;

revoke all on function public.create_account_opening_event(uuid,timestamptz,text,numeric,uuid,text,uuid),
  public.create_envelope_opening_event(uuid,timestamptz,text,jsonb,text,uuid) from public, anon;
grant execute on function public.create_account_opening_event(uuid,timestamptz,text,numeric,uuid,text,uuid),
  public.create_envelope_opening_event(uuid,timestamptz,text,jsonb,text,uuid) to authenticated;

commit;
