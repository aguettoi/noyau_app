-- A member without access to a private account cannot create an observation
-- or cause its theoretical balance to be computed through this RPC.
create or replace function public.record_account_balance_observation(
  p_account_id uuid, p_observed_at timestamptz,
  p_actual_balance numeric, p_reason text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_household_id uuid;
  v_observation_id uuid;
  v_theoretical numeric(14,2);
begin
  select household_id into v_household_id
  from public.accounts
  where id=p_account_id and archived_at is null
  for update;

  if (select auth.uid()) is null
     or v_household_id is null
     or not public.is_household_member(v_household_id)
     or not private.can_discover_account(p_account_id,(select auth.uid())) then
    raise exception 'Account access denied';
  end if;
  if char_length(trim(coalesce(p_reason,''))) not between 1 and 280 then
    raise exception 'A reason between 1 and 280 characters is required';
  end if;

  select theoretical_balance into v_theoretical
  from public.account_ledger_balances
  where account_id=p_account_id and household_id=v_household_id;
  if v_theoretical is null then
    raise exception 'Theoretical account balance unavailable';
  end if;

  insert into public.account_balance_observations(
    household_id,account_id,observed_at,actual_balance,reason,created_by,
    theoretical_balance_snapshot,difference_snapshot,snapshot_version
  ) values (
    v_household_id,p_account_id,coalesce(p_observed_at,now()),
    p_actual_balance,trim(p_reason),auth.uid(),v_theoretical,
    p_actual_balance-v_theoretical,1
  ) returning id into v_observation_id;
  return v_observation_id;
end;
$$;
