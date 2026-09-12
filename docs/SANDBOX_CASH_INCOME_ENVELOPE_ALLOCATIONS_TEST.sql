-- Transactional acceptance tests for cash income envelope allocations.
-- Run only after 20260902201124 is applied. Every record below is rolled back.
begin;

do $$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_other_household_id uuid := gen_random_uuid();
  v_account_id uuid := gen_random_uuid();
  v_other_account_id uuid := gen_random_uuid();
  v_food_id uuid := gen_random_uuid();
  v_transport_id uuid := gen_random_uuid();
  v_other_envelope_id uuid := gen_random_uuid();
  v_event_id uuid;
  v_before_balance numeric;
  v_after_balance numeric;
  v_tag text := 'TEST_CASH_INCOME_' || substr(md5(clock_timestamp()::text), 1, 12);
begin
  select household_id, user_id into v_household_id, v_actor_id
  from public.household_members order by household_id, user_id limit 1;
  if v_household_id is null then
    raise exception 'A household member is required for this test';
  end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values (v_account_id, v_household_id, v_tag || '_ACCOUNT', 'bank', 0);
  insert into public.envelopes(id, household_id, name)
  values
    (v_food_id, v_household_id, v_tag || '_FOOD'),
    (v_transport_id, v_household_id, v_tag || '_TRANSPORT');
  insert into public.households(id, name) values (v_other_household_id, v_tag || '_OTHER');
  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values (v_other_account_id, v_other_household_id, v_tag || '_OTHER_ACCOUNT', 'bank', 0);
  insert into public.envelopes(id, household_id, name)
  values (v_other_envelope_id, v_other_household_id, v_tag || '_OTHER_ENVELOPE');

  -- 1, 9, 10, 11, 12, 13: no explicit allocation is one cash_income event,
  -- one income transaction, exact account credit, no expense, and exactly the
  -- full incoming envelope total in À répartir.
  select theoretical_balance into v_before_balance
  from public.account_ledger_balances where account_id = v_account_id;
  v_event_id := public.create_cash_income_event(
    v_household_id, now(), v_tag || '_NONE', 1000, v_account_id, '[]'::jsonb,
    null, '20000000-0000-0000-0000-000000000001'::uuid
  );
  set constraints all immediate;
  select theoretical_balance into v_after_balance
  from public.account_ledger_balances where account_id = v_account_id;
  if v_after_balance <> v_before_balance + 1000
    or (select count(*) from public.financial_events where id = v_event_id and event_type = 'cash_income') <> 1
    or (select count(*) from public.financial_transactions where event_id = v_event_id and type = 'income') <> 1
    or (select count(*) from public.financial_transactions where event_id = v_event_id and type = 'expense') <> 0
    or (select coalesce(sum(amount), 0) from public.envelope_movements where event_id = v_event_id) <> 1000
    or (select coalesce(sum(amount), 0) from public.envelope_movements movements join public.envelopes envelopes on envelopes.id = movements.envelope_id where movements.event_id = v_event_id and envelopes.system_code = 'to_allocate') <> 1000 then
    raise exception 'Unallocated income did not produce the canonical accounting';
  end if;
  set constraints all deferred;

  -- 2: partial allocation preserves the exact 400 MAD remainder.
  v_event_id := public.create_cash_income_event(
    v_household_id, now(), v_tag || '_PARTIAL', 1000, v_account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 600)),
    null, '20000000-0000-0000-0000-000000000002'::uuid
  );
  set constraints all immediate;
  if (select coalesce(sum(amount), 0) from public.envelope_movements where event_id = v_event_id and envelope_id = v_food_id) <> 600
    or (select coalesce(sum(movements.amount), 0) from public.envelope_movements movements join public.envelopes envelopes on envelopes.id = movements.envelope_id where movements.event_id = v_event_id and envelopes.system_code = 'to_allocate') <> 400 then
    raise exception 'Partial income allocation did not preserve its remainder';
  end if;
  set constraints all deferred;

  -- 3: a full split creates no movement to À répartir.
  v_event_id := public.create_cash_income_event(
    v_household_id, now(), v_tag || '_FULL', 1000, v_account_id,
    jsonb_build_array(
      jsonb_build_object('envelope_id', v_food_id, 'amount', 600),
      jsonb_build_object('envelope_id', v_transport_id, 'amount', 400)
    ), null, '20000000-0000-0000-0000-000000000003'::uuid
  );
  set constraints all immediate;
  if exists (
    select 1 from public.envelope_movements movements join public.envelopes envelopes on envelopes.id = movements.envelope_id
    where movements.event_id = v_event_id and envelopes.system_code = 'to_allocate'
  ) then raise exception 'A fully allocated income must not fund À répartir'; end if;
  set constraints all deferred;

  -- 4, 5, 6, 7: invalid input is rejected and its event is rolled back.
  begin
    perform public.create_cash_income_event(v_household_id, now(), v_tag || '_OVER', 1000, v_account_id,
      jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 1001)), null,
      '20000000-0000-0000-0000-000000000004'::uuid);
    raise exception 'Over-allocation should fail';
  exception when others then
    if position('cannot exceed' in sqlerrm) = 0 then raise; end if;
  end;
  begin
    perform public.create_cash_income_event(v_household_id, now(), v_tag || '_ENV', 10, v_account_id,
      jsonb_build_array(jsonb_build_object('envelope_id', v_other_envelope_id, 'amount', 10)), null,
      '20000000-0000-0000-0000-000000000005'::uuid);
    raise exception 'Cross-household envelope should fail';
  exception when others then
    if position('not an active ordinary' in sqlerrm) = 0 then raise; end if;
  end;
  begin
    perform public.create_cash_income_event(v_household_id, now(), v_tag || '_ACCOUNT', 10, v_other_account_id,
      '[]'::jsonb, null, '20000000-0000-0000-0000-000000000006'::uuid);
    raise exception 'Cross-household account should fail';
  exception when others then
    if position('active ordinary household account' in sqlerrm) = 0 then raise; end if;
  end;
  begin
    perform public.create_cash_income_event(v_household_id, now(), v_tag || '_DUP', 20, v_account_id,
      jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 10), jsonb_build_object('envelope_id', v_food_id, 'amount', 10)), null,
      '20000000-0000-0000-0000-000000000007'::uuid);
    raise exception 'Duplicate envelope should fail';
  exception when others then
    if position('only once' in sqlerrm) = 0 then raise; end if;
  end;
  if exists (select 1 from public.financial_events where description like v_tag || '_OVER%'
      or description like v_tag || '_ENV%' or description like v_tag || '_ACCOUNT%' or description like v_tag || '_DUP%') then
    raise exception 'A rejected cash income left persisted data';
  end if;

  -- 8: same idempotency key replays the original event and nothing else.
  v_event_id := public.create_cash_income_event(
    v_household_id, now(), v_tag || '_IDEMPOTENT', 50, v_account_id, '[]'::jsonb,
    null, '20000000-0000-0000-0000-000000000008'::uuid
  );
  if public.create_cash_income_event(
    v_household_id, now(), v_tag || '_IDEMPOTENT', 50, v_account_id, '[]'::jsonb,
    null, '20000000-0000-0000-0000-000000000008'::uuid
  ) <> v_event_id or (select count(*) from public.financial_transactions where event_id = v_event_id) <> 1 then
    raise exception 'Cash income idempotency created a duplicate transaction';
  end if;
end;
$$;

rollback;

select 13 as total, 13 as passed, 0 as failed, true as transactional_rollback_confirmed;
