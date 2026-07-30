-- Enveloppes: derived balances, monthly nets and append-only account checks.
-- This migration is intentionally prepared locally only. It must be applied
-- manually from the Supabase Dashboard with the other reviewed migrations.

create table public.account_balance_observations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete restrict,
  observed_at timestamptz not null default now(),
  actual_balance numeric(14, 2) not null,
  reason text not null check (char_length(trim(reason)) between 1 and 280),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index account_balance_observations_latest_idx
  on public.account_balance_observations(account_id, observed_at desc, created_at desc);

alter table public.account_balance_observations enable row level security;

create policy "members read account balance observations"
  on public.account_balance_observations for select
  using (public.is_household_member(household_id));

-- The theoretical balance is always calculated from the account opening value
-- and the immutable Grand Livre. It is never edited manually.
create or replace view public.account_theoretical_balances
with (security_invoker = true)
as
select
  accounts.household_id,
  accounts.id as account_id,
  accounts.name as account_name,
  accounts.kind as account_kind,
  accounts.opening_balance + coalesce(sum(lines.amount), 0) as theoretical_balance
from public.accounts
left join public.financial_transaction_lines lines on lines.account_id = accounts.id
where accounts.archived_at is null
group by accounts.household_id, accounts.id, accounts.name, accounts.kind, accounts.opening_balance;

-- `SUMIFS(Journal...)` counterpart: a signed net movement per envelope/month.
create or replace view public.envelope_monthly_movements
with (security_invoker = true)
as
select
  transactions.household_id,
  lines.envelope_id,
  date_trunc('month', transactions.occurred_at at time zone 'Africa/Casablanca')::date as month_start,
  sum(lines.amount) as net_movement
from public.financial_transaction_lines lines
join public.financial_transactions transactions on transactions.id = lines.transaction_id
where lines.envelope_id is not null
group by transactions.household_id, lines.envelope_id,
  date_trunc('month', transactions.occurred_at at time zone 'Africa/Casablanca')::date;

-- `SUMIF(Journal...)` counterpart: current theoretical balance by envelope.
create or replace view public.envelope_balances
with (security_invoker = true)
as
select
  envelopes.household_id,
  envelopes.id as envelope_id,
  envelopes.name as envelope_name,
  coalesce(sum(lines.amount), 0) as theoretical_balance
from public.envelopes
left join public.financial_transaction_lines lines on lines.envelope_id = envelopes.id
where envelopes.archived_at is null
group by envelopes.household_id, envelopes.id, envelopes.name;

create or replace view public.account_reconciliation_status
with (security_invoker = true)
as
select
  theoretical.household_id,
  theoretical.account_id,
  theoretical.account_name,
  theoretical.account_kind,
  theoretical.theoretical_balance,
  latest.actual_balance,
  latest.observed_at,
  theoretical.theoretical_balance - latest.actual_balance as difference
from public.account_theoretical_balances theoretical
left join lateral (
  select observations.actual_balance, observations.observed_at
  from public.account_balance_observations observations
  where observations.account_id = theoretical.account_id
  order by observations.observed_at desc, observations.created_at desc
  limit 1
) latest on true;

-- Only this routine can add a real-world bank/cash observation. The ledger and
-- the observations remain append-only; a correction is a new observation with
-- its own short explanation.
create or replace function public.record_account_balance_observation(
  p_account_id uuid,
  p_observed_at timestamptz,
  p_actual_balance numeric,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
  v_observation_id uuid;
begin
  select household_id into v_household_id
  from public.accounts
  where id = p_account_id and archived_at is null;

  if auth.uid() is null
     or v_household_id is null
     or not public.is_household_member(v_household_id) then
    raise exception 'Account access denied';
  end if;

  if char_length(trim(coalesce(p_reason, ''))) not between 1 and 280 then
    raise exception 'A reason between 1 and 280 characters is required';
  end if;

  insert into public.account_balance_observations (
    household_id, account_id, observed_at, actual_balance, reason, created_by
  ) values (
    v_household_id, p_account_id, coalesce(p_observed_at, now()),
    p_actual_balance, trim(p_reason), auth.uid()
  ) returning id into v_observation_id;

  return v_observation_id;
end;
$$;

grant execute on function public.record_account_balance_observation(uuid, timestamptz, numeric, text) to authenticated;
