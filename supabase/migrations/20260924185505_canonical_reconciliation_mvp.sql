-- Canonical reconciliation MVP: observations remain non-financial evidence.
-- New observations receive an immutable ledger snapshot; legacy rows stay
-- untouched and are explicitly surfaced as legacy_unfrozen.

alter table public.account_balance_observations
  add column if not exists theoretical_balance_snapshot numeric(14, 2),
  add column if not exists difference_snapshot numeric(14, 2),
  add column if not exists snapshot_version smallint;

alter table public.account_balance_observations
  add constraint account_balance_observations_snapshot_check
  check (
    snapshot_version is null
    or (
      snapshot_version = 1
      and theoretical_balance_snapshot is not null
      and difference_snapshot is not null
      and difference_snapshot = actual_balance - theoretical_balance_snapshot
    )
  ) not valid;

create table if not exists public.account_reconciliation_resolutions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  observation_id uuid not null references public.account_balance_observations(id) on delete restrict,
  account_id uuid not null references public.accounts(id) on delete restrict,
  resolution_kind text not null check (resolution_kind in ('documentary', 'temporary', 'financial_event', 'follow_up', 'reversal')),
  effective_amount numeric(14, 2) not null default 0,
  comment text not null check (char_length(trim(comment)) between 1 and 280),
  financial_event_id uuid references public.financial_events(id) on delete restrict,
  follow_up_observation_id uuid references public.account_balance_observations(id) on delete restrict,
  reversal_of_resolution_id uuid references public.account_reconciliation_resolutions(id) on delete restrict,
  idempotency_key text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (household_id, idempotency_key),
  unique (observation_id, financial_event_id),
  check (
    (resolution_kind = 'financial_event' and financial_event_id is not null and follow_up_observation_id is null)
    or (resolution_kind = 'follow_up' and financial_event_id is null and follow_up_observation_id is not null)
    or (resolution_kind in ('documentary', 'temporary') and financial_event_id is null and follow_up_observation_id is null)
    or (resolution_kind = 'reversal' and reversal_of_resolution_id is not null)
  )
);

create index if not exists account_reconciliation_resolutions_observation_idx
  on public.account_reconciliation_resolutions(observation_id, created_at);

alter table public.account_reconciliation_resolutions enable row level security;

create policy "members read reconciliation resolutions"
  on public.account_reconciliation_resolutions for select
  to authenticated
  using (public.is_household_member(household_id));

-- Freeze the theoretical account value on the server while holding the account
-- row lock. The caller never supplies the theoretical balance or difference.
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
  v_theoretical numeric(14, 2);
begin
  select household_id into v_household_id
  from public.accounts
  where id = p_account_id and archived_at is null
  for update;

  if auth.uid() is null
     or v_household_id is null
     or not public.is_household_member(v_household_id) then
    raise exception 'Account access denied';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 1 and 280 then
    raise exception 'A reason between 1 and 280 characters is required';
  end if;

  select theoretical_balance into v_theoretical
  from public.account_ledger_balances
  where account_id = p_account_id and household_id = v_household_id;
  if v_theoretical is null then
    raise exception 'Theoretical account balance unavailable';
  end if;

  insert into public.account_balance_observations (
    household_id, account_id, observed_at, actual_balance, reason, created_by,
    theoretical_balance_snapshot, difference_snapshot, snapshot_version
  ) values (
    v_household_id, p_account_id, coalesce(p_observed_at, now()),
    p_actual_balance, trim(p_reason), auth.uid(), v_theoretical,
    p_actual_balance - v_theoretical, 1
  ) returning id into v_observation_id;
  return v_observation_id;
end;
$$;

create or replace view public.account_reconciliation_cases
with (security_invoker = true)
as
select
  o.id as observation_id,
  o.household_id,
  o.account_id,
  o.observed_at,
  o.actual_balance,
  o.theoretical_balance_snapshot,
  o.difference_snapshot,
  o.snapshot_version,
  coalesce(sum(r.effective_amount), 0)::numeric(14, 2) as resolved_amount,
  (o.difference_snapshot - coalesce(sum(r.effective_amount), 0))::numeric(14, 2) as remaining_difference,
  case
    when o.snapshot_version is null then 'legacy_unfrozen'
    when o.difference_snapshot = 0 then 'reconciled'
    when o.difference_snapshot - coalesce(sum(r.effective_amount), 0) = 0 then 'resolved'
    when coalesce(sum(r.effective_amount), 0) <> 0 then 'partially_resolved'
    when bool_or(r.resolution_kind = 'temporary') then 'explained_pending'
    else 'open'
  end as status
from public.account_balance_observations o
left join public.account_reconciliation_resolutions r on r.observation_id = o.id
group by o.id;

grant select on public.account_reconciliation_cases to authenticated;

create or replace function public.add_account_reconciliation_explanation(
  p_observation_id uuid,
  p_kind text,
  p_comment text,
  p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_observation public.account_balance_observations%rowtype; v_id uuid;
begin
  select * into v_observation from public.account_balance_observations
  where id = p_observation_id for update;
  if auth.uid() is null or v_observation.id is null or not public.is_household_member(v_observation.household_id) then raise exception 'Observation access denied'; end if;
  if v_observation.snapshot_version is null then raise exception 'Legacy observation has no frozen snapshot'; end if;
  if p_kind not in ('documentary','temporary') then raise exception 'Invalid explanation kind'; end if;
  if char_length(trim(coalesce(p_comment,''))) not between 1 and 280 then raise exception 'A comment between 1 and 280 characters is required'; end if;
  insert into public.account_reconciliation_resolutions(household_id,observation_id,account_id,resolution_kind,comment,idempotency_key,created_by)
  values(v_observation.household_id,v_observation.id,v_observation.account_id,p_kind,trim(p_comment),p_idempotency_key,auth.uid())
  on conflict(household_id,idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.account_reconciliation_resolutions
    where household_id=v_observation.household_id and idempotency_key=p_idempotency_key;
  end if;
  return v_id;
end;
$$;

create or replace function public.link_account_reconciliation_financial_event(
  p_observation_id uuid,
  p_financial_event_id uuid,
  p_comment text,
  p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_observation public.account_balance_observations%rowtype; v_effect numeric(14,2); v_remaining numeric(14,2); v_id uuid;
begin
  select * into v_observation from public.account_balance_observations where id=p_observation_id for update;
  if auth.uid() is null or v_observation.id is null or not public.is_household_member(v_observation.household_id) then raise exception 'Observation access denied'; end if;
  if v_observation.snapshot_version is null then raise exception 'Legacy observation has no frozen snapshot'; end if;
  if not exists(select 1 from public.financial_events where id=p_financial_event_id and household_id=v_observation.household_id) then raise exception 'Financial event access denied'; end if;
  select coalesce(sum(l.debit-l.credit),0)::numeric(14,2) into v_effect
  from public.financial_transactions t join public.financial_transaction_lines l on l.transaction_id=t.id
  where t.event_id=p_financial_event_id and l.account_id=v_observation.account_id;
  if v_effect = 0 then raise exception 'Financial event has no impact on this account'; end if;
  select remaining_difference into v_remaining from public.account_reconciliation_cases where observation_id=v_observation.id;
  if (v_remaining > 0 and (v_effect <= 0 or v_effect > v_remaining))
     or (v_remaining < 0 and (v_effect >= 0 or v_effect < v_remaining)) then
    raise exception 'Financial event exceeds reconciliation remainder';
  end if;
  insert into public.account_reconciliation_resolutions(household_id,observation_id,account_id,resolution_kind,effective_amount,comment,financial_event_id,idempotency_key,created_by)
  values(v_observation.household_id,v_observation.id,v_observation.account_id,'financial_event',v_effect,trim(coalesce(p_comment,'Opération canonique rattachée')),p_financial_event_id,p_idempotency_key,auth.uid())
  on conflict(household_id,idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.account_reconciliation_resolutions
    where household_id=v_observation.household_id and idempotency_key=p_idempotency_key;
  end if;
  return v_id;
end;
$$;

create or replace function public.resolve_account_reconciliation_by_follow_up(
  p_observation_id uuid,
  p_follow_up_observation_id uuid,
  p_comment text,
  p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_observation public.account_balance_observations%rowtype; v_follow_up public.account_balance_observations%rowtype; v_remaining numeric(14,2); v_id uuid;
begin
  select * into v_observation from public.account_balance_observations where id=p_observation_id for update;
  select * into v_follow_up from public.account_balance_observations where id=p_follow_up_observation_id for update;
  if auth.uid() is null or v_observation.id is null or v_follow_up.id is null or v_observation.household_id<>v_follow_up.household_id or v_observation.account_id<>v_follow_up.account_id or not public.is_household_member(v_observation.household_id) then raise exception 'Observation access denied'; end if;
  if v_observation.snapshot_version is null or v_follow_up.snapshot_version is null or v_follow_up.difference_snapshot <> 0 or v_follow_up.observed_at < v_observation.observed_at then raise exception 'Follow-up observation is not compatible'; end if;
  if not exists(select 1 from public.account_reconciliation_resolutions where observation_id=v_observation.id and resolution_kind='temporary') then raise exception 'Follow-up only resolves a documented temporary difference'; end if;
  select remaining_difference into v_remaining from public.account_reconciliation_cases where observation_id=v_observation.id;
  insert into public.account_reconciliation_resolutions(household_id,observation_id,account_id,resolution_kind,effective_amount,comment,follow_up_observation_id,idempotency_key,created_by)
  values(v_observation.household_id,v_observation.id,v_observation.account_id,'follow_up',v_remaining,trim(p_comment),v_follow_up.id,p_idempotency_key,auth.uid())
  on conflict(household_id,idempotency_key) do nothing returning id into v_id;
  if v_id is null then
    select id into v_id from public.account_reconciliation_resolutions
    where household_id=v_observation.household_id and idempotency_key=p_idempotency_key;
  end if;
  return v_id;
end;
$$;

revoke all on function public.add_account_reconciliation_explanation(uuid,text,text,text) from public, anon;
revoke all on function public.link_account_reconciliation_financial_event(uuid,uuid,text,text) from public, anon;
revoke all on function public.resolve_account_reconciliation_by_follow_up(uuid,uuid,text,text) from public, anon;
grant execute on function public.add_account_reconciliation_explanation(uuid,text,text,text) to authenticated;
grant execute on function public.link_account_reconciliation_financial_event(uuid,uuid,text,text) to authenticated;
grant execute on function public.resolve_account_reconciliation_by_follow_up(uuid,uuid,text,text) to authenticated;
