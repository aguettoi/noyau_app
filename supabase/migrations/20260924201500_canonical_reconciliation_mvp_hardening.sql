-- Additive hardening for canonical reconciliation MVP.  The initial schema
-- remains immutable: this migration only closes replay and duplicate-impact
-- gaps discovered after deployment.

create unique index if not exists account_reconciliation_one_event_account_idx
  on public.account_reconciliation_resolutions(financial_event_id, account_id)
  where financial_event_id is not null;

create or replace function public.add_account_reconciliation_explanation(
  p_observation_id uuid,
  p_kind text,
  p_comment text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_observation public.account_balance_observations%rowtype; v_id uuid;
begin
  select * into v_observation from public.account_balance_observations where id=p_observation_id for update;
  if auth.uid() is null or v_observation.id is null or not public.is_household_member(v_observation.household_id) then raise exception 'Observation access denied'; end if;
  select id into v_id from public.account_reconciliation_resolutions where household_id=v_observation.household_id and idempotency_key=p_idempotency_key;
  if v_id is not null then return v_id; end if;
  if v_observation.snapshot_version is null then raise exception 'Legacy observation has no frozen snapshot'; end if;
  if p_kind not in ('documentary','temporary') then raise exception 'Invalid explanation kind'; end if;
  if char_length(trim(coalesce(p_comment,''))) not between 1 and 280 then raise exception 'A comment between 1 and 280 characters is required'; end if;
  insert into public.account_reconciliation_resolutions(household_id,observation_id,account_id,resolution_kind,comment,idempotency_key,created_by)
  values(v_observation.household_id,v_observation.id,v_observation.account_id,p_kind,trim(p_comment),p_idempotency_key,auth.uid()) returning id into v_id;
  return v_id;
end; $$;
create or replace function public.link_account_reconciliation_financial_event(
  p_observation_id uuid, p_financial_event_id uuid, p_comment text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_observation public.account_balance_observations%rowtype; v_effect numeric(14,2); v_remaining numeric(14,2); v_id uuid;
begin
  select * into v_observation from public.account_balance_observations where id=p_observation_id for update;
  if auth.uid() is null or v_observation.id is null or not public.is_household_member(v_observation.household_id) then raise exception 'Observation access denied'; end if;
  select id into v_id from public.account_reconciliation_resolutions where household_id=v_observation.household_id and idempotency_key=p_idempotency_key;
  if v_id is not null then return v_id; end if;
  if v_observation.snapshot_version is null then raise exception 'Legacy observation has no frozen snapshot'; end if;
  if not exists(select 1 from public.financial_events where id=p_financial_event_id and household_id=v_observation.household_id) then raise exception 'Financial event access denied'; end if;
  if exists(select 1 from public.account_reconciliation_resolutions where financial_event_id=p_financial_event_id and account_id=v_observation.account_id) then raise exception 'Financial event impact is already linked to a reconciliation'; end if;
  select coalesce(sum(l.debit-l.credit),0)::numeric(14,2) into v_effect from public.financial_transactions t join public.financial_transaction_lines l on l.transaction_id=t.id where t.event_id=p_financial_event_id and l.account_id=v_observation.account_id;
  if v_effect = 0 then raise exception 'Financial event has no impact on this account'; end if;
  select remaining_difference into v_remaining from public.account_reconciliation_cases where observation_id=v_observation.id;
  if (v_remaining > 0 and (v_effect <= 0 or v_effect > v_remaining)) or (v_remaining < 0 and (v_effect >= 0 or v_effect < v_remaining)) then raise exception 'Financial event exceeds reconciliation remainder'; end if;
  insert into public.account_reconciliation_resolutions(household_id,observation_id,account_id,resolution_kind,effective_amount,comment,financial_event_id,idempotency_key,created_by)
  values(v_observation.household_id,v_observation.id,v_observation.account_id,'financial_event',v_effect,trim(coalesce(p_comment,'Opération canonique rattachée')),p_financial_event_id,p_idempotency_key,auth.uid()) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.resolve_account_reconciliation_by_follow_up(
  p_observation_id uuid, p_follow_up_observation_id uuid, p_comment text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_observation public.account_balance_observations%rowtype; v_follow_up public.account_balance_observations%rowtype; v_remaining numeric(14,2); v_id uuid;
begin
  select * into v_observation from public.account_balance_observations where id=p_observation_id for update;
  if auth.uid() is null or v_observation.id is null or not public.is_household_member(v_observation.household_id) then raise exception 'Observation access denied'; end if;
  select id into v_id from public.account_reconciliation_resolutions where household_id=v_observation.household_id and idempotency_key=p_idempotency_key;
  if v_id is not null then return v_id; end if;
  select * into v_follow_up from public.account_balance_observations where id=p_follow_up_observation_id for update;
  if v_follow_up.id is null or v_observation.household_id<>v_follow_up.household_id or v_observation.account_id<>v_follow_up.account_id then raise exception 'Observation access denied'; end if;
  if v_observation.snapshot_version is null or v_follow_up.snapshot_version is null or v_follow_up.difference_snapshot <> 0 or v_follow_up.observed_at < v_observation.observed_at then raise exception 'Follow-up observation is not compatible'; end if;
  if not exists(select 1 from public.account_reconciliation_resolutions where observation_id=v_observation.id and resolution_kind='temporary') then raise exception 'Follow-up only resolves a documented temporary difference'; end if;
  select remaining_difference into v_remaining from public.account_reconciliation_cases where observation_id=v_observation.id;
  insert into public.account_reconciliation_resolutions(household_id,observation_id,account_id,resolution_kind,effective_amount,comment,follow_up_observation_id,idempotency_key,created_by)
  values(v_observation.household_id,v_observation.id,v_observation.account_id,'follow_up',v_remaining,trim(p_comment),v_follow_up.id,p_idempotency_key,auth.uid()) returning id into v_id;
  return v_id;
end; $$;
