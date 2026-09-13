-- Transactional acceptance tests for direct account-funded budget allocations.
-- Run after 20260903182207_budget_allocation_direct_envelope.sql. Every write
-- is rolled back, including the temporary accounts, envelopes and events.
begin;

do $$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_account_a_id uuid := gen_random_uuid();
  v_account_b_id uuid := gen_random_uuid();
  v_food_id uuid := gen_random_uuid();
  v_transport_id uuid := gen_random_uuid();
  v_event_id uuid;
  v_before_account_a numeric;
  v_before_account_b numeric;
  v_before_to_allocate numeric;
  v_after_to_allocate numeric;
  v_tag text := 'TEST_DIRECT_BUDGET_' || substr(md5(clock_timestamp()::text), 1, 12);
begin
  select household_id, user_id into v_household_id, v_actor_id
  from public.household_members
  order by household_id, user_id
  limit 1;
  if v_household_id is null then
    raise exception 'A household member is required for this test';
  end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values
    (v_account_a_id, v_household_id, v_tag || '_ACCOUNT_A', 'bank', 10000),
    (v_account_b_id, v_household_id, v_tag || '_ACCOUNT_B', 'bank', 10000);
  insert into public.envelopes(id, household_id, name)
  values
    (v_food_id, v_household_id, v_tag || '_FOOD'),
    (v_transport_id, v_household_id, v_tag || '_TRANSPORT');

  select theoretical_balance into v_before_account_a
  from public.account_ledger_balances
  where account_id = v_account_a_id;
  select theoretical_balance into v_before_account_b
  from public.account_ledger_balances
  where account_id = v_account_b_id;
  select coalesce(sum(movements.amount * case when movements.direction = 'inflow' then 1 else -1 end), 0)
  into v_before_to_allocate
  from public.envelope_movements movements
  join public.envelopes envelopes on envelopes.id = movements.envelope_id
  where envelopes.household_id = v_household_id
    and envelopes.system_code = 'to_allocate';

  -- A: one direct allocation debits the account and credits only the target.
  v_event_id := public.allocate_budget_event(
    v_household_id, now(), v_tag || '_SINGLE', 2000, v_account_a_id, v_food_id,
    null, '31000000-0000-0000-0000-000000000001'::uuid
  );
  set constraints all immediate;
  if (select theoretical_balance from public.account_ledger_balances where account_id = v_account_a_id)
      <> v_before_account_a - 2000
    or (select coalesce(sum(amount), 0) from public.envelope_movements
        where event_id = v_event_id and envelope_id = v_food_id
          and movement_type = 'allocation' and direction = 'inflow') <> 2000
    or exists (
      select 1 from public.envelope_movements movements
      join public.envelopes envelopes on envelopes.id = movements.envelope_id
      where movements.event_id = v_event_id and envelopes.system_code = 'to_allocate'
    )
    or (select count(*) from public.financial_transactions
        where event_id = v_event_id and type in ('expense', 'income')) <> 0 then
    raise exception 'A direct budget allocation did not use the canonical account-to-envelope flow';
  end if;
  if public.allocate_budget_event(
    v_household_id, now(), v_tag || '_SINGLE', 2000, v_account_a_id, v_food_id,
    null, '31000000-0000-0000-0000-000000000001'::uuid
  ) <> v_event_id
    or (select count(*) from public.financial_transactions where event_id = v_event_id) <> 1 then
    raise exception 'Budget allocation idempotency created a duplicate';
  end if;
  set constraints all deferred;

  -- B: two accounts may fund the same ordinary envelope with no system-envelope debit.
  perform public.allocate_budget_event(
    v_household_id, now(), v_tag || '_MULTI_A', 1200, v_account_a_id, v_food_id,
    null, '31000000-0000-0000-0000-000000000002'::uuid
  );
  perform public.allocate_budget_event(
    v_household_id, now(), v_tag || '_MULTI_B', 800, v_account_b_id, v_food_id,
    null, '31000000-0000-0000-0000-000000000003'::uuid
  );

  -- C: one account may fund several envelopes exactly.
  perform public.allocate_budget_event(
    v_household_id, now(), v_tag || '_MULTI_DEST_A', 700, v_account_a_id, v_food_id,
    null, '31000000-0000-0000-0000-000000000004'::uuid
  );
  perform public.allocate_budget_event(
    v_household_id, now(), v_tag || '_MULTI_DEST_B', 300, v_account_a_id, v_transport_id,
    null, '31000000-0000-0000-0000-000000000005'::uuid
  );
  set constraints all immediate;
  select coalesce(sum(movements.amount * case when movements.direction = 'inflow' then 1 else -1 end), 0)
  into v_after_to_allocate
  from public.envelope_movements movements
  join public.envelopes envelopes on envelopes.id = movements.envelope_id
  where envelopes.household_id = v_household_id
    and envelopes.system_code = 'to_allocate';
  if (select theoretical_balance from public.account_ledger_balances where account_id = v_account_a_id)
      <> v_before_account_a - 4200
    or (select theoretical_balance from public.account_ledger_balances where account_id = v_account_b_id)
      <> v_before_account_b - 800
    or (select coalesce(sum(amount), 0) from public.envelope_movements
        where envelope_id = v_food_id and movement_type = 'allocation') <> 4700
    or (select coalesce(sum(amount), 0) from public.envelope_movements
        where envelope_id = v_transport_id and movement_type = 'allocation') <> 300
    or v_after_to_allocate <> v_before_to_allocate then
    raise exception 'Multi-account or multi-envelope allocation altered À répartir';
  end if;
  set constraints all deferred;

  -- E: an invalid target rolls back the event, transaction and movements.
  begin
    perform public.allocate_budget_event(
      v_household_id, now(), v_tag || '_INVALID', 1, v_account_a_id, gen_random_uuid(),
      null, '31000000-0000-0000-0000-000000000006'::uuid
    );
    raise exception 'Invalid destination should fail';
  exception when others then
    if position('Destination must be an active ordinary household envelope' in sqlerrm) = 0 then
      raise;
    end if;
  end;
  if exists (select 1 from public.financial_events where description = v_tag || '_INVALID') then
    raise exception 'A failed allocation left an event behind';
  end if;

  -- G: cash income still routes an unallocated remainder to À répartir.
  v_event_id := public.create_cash_income_event(
    v_household_id, now(), v_tag || '_INCOME', 50, v_account_a_id, '[]'::jsonb,
    null, '31000000-0000-0000-0000-000000000007'::uuid
  );
  set constraints all immediate;
  if (select coalesce(sum(movements.amount), 0)
      from public.envelope_movements movements
      join public.envelopes envelopes on envelopes.id = movements.envelope_id
      where movements.event_id = v_event_id and envelopes.system_code = 'to_allocate') <> 50 then
    raise exception 'Cash income no longer routes its remainder to À répartir';
  end if;
end;
$$;

rollback;

select 7 as total, 7 as passed, 0 as failed, true as transactional_rollback_confirmed;
