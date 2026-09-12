-- Transactional acceptance tests for debt-expense envelope consumption.
-- Requires 20260903200055_debt_expense_envelope_consumption_compatibility.
-- Every write is rolled back.
begin;

do $$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_other_household_id uuid := gen_random_uuid();
  v_account_id uuid := gen_random_uuid();
  v_food_id uuid := gen_random_uuid();
  v_other_envelope_id uuid := gen_random_uuid();
  v_debt_event_id uuid;
  v_cash_event_id uuid;
  v_income_event_id uuid;
  v_income_transaction_id uuid;
  v_tag text := 'TEST_DEBT_ENVELOPE_' || substr(md5(clock_timestamp()::text), 1, 12);
begin
  select household_id, user_id into v_household_id, v_actor_id
  from public.household_members order by household_id, user_id limit 1;
  if v_household_id is null then
    raise exception 'A household member is required for this test';
  end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values (v_account_id, v_household_id, v_tag || '_ACCOUNT', 'bank', 1000);
  insert into public.envelopes(id, household_id, name)
  values (v_food_id, v_household_id, v_tag || '_FOOD');
  insert into public.households(id, name) values (v_other_household_id, v_tag || '_OTHER');
  insert into public.envelopes(id, household_id, name)
  values (v_other_envelope_id, v_other_household_id, v_tag || '_OTHER_ENVELOPE');

  -- 1, 4, 6: one debt event creates its obligation, balanced debt ledger
  -- transaction and one 120 MAD consumption with no ordinary account or
  -- À répartir movement. Replaying its key does not duplicate anything.
  v_debt_event_id := public.create_debt_expense_event(
    v_household_id, now(), v_tag || '_DEBT', 120,
    jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 120)),
    'Créancier test', null, null,
    '40000000-0000-0000-0000-000000000001'::uuid
  );
  set constraints all immediate;
  if (select count(*) from public.financial_events where id = v_debt_event_id and event_type = 'debt_expense') <> 1
    or (select count(*) from public.obligations where origin_event_id = v_debt_event_id and initial_amount = 120) <> 1
    or (select count(*) from public.financial_transactions where event_id = v_debt_event_id and type = 'debt_expense') <> 1
    or (select coalesce(sum(debit), 0) from public.financial_transaction_lines lines join public.financial_transactions transactions on transactions.id = lines.transaction_id where transactions.event_id = v_debt_event_id) <> 120
    or (select coalesce(sum(credit), 0) from public.financial_transaction_lines lines join public.financial_transactions transactions on transactions.id = lines.transaction_id where transactions.event_id = v_debt_event_id) <> 120
    or (select count(*) from public.envelope_movements where event_id = v_debt_event_id and envelope_id = v_food_id and movement_type = 'consumption' and direction = 'outflow' and amount = 120) <> 1
    or exists (select 1 from public.financial_transaction_lines lines join public.financial_transactions transactions on transactions.id = lines.transaction_id join public.accounts accounts on accounts.id = lines.account_id where transactions.event_id = v_debt_event_id and not accounts.is_system)
    or exists (select 1 from public.envelope_movements movements join public.envelopes envelopes on envelopes.id = movements.envelope_id where movements.event_id = v_debt_event_id and envelopes.system_code = 'to_allocate') then
    raise exception 'Debt expense did not create its canonical accounting';
  end if;
  if public.create_debt_expense_event(
    v_household_id, now(), v_tag || '_DEBT', 120,
    jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 120)),
    'Créancier test', null, null,
    '40000000-0000-0000-0000-000000000001'::uuid
  ) <> v_debt_event_id
    or (select count(*) from public.obligations where origin_event_id = v_debt_event_id) <> 1 then
    raise exception 'Debt expense idempotency created a duplicate';
  end if;
  set constraints all deferred;

  -- 2: cash expense consumption remains valid.
  v_cash_event_id := public.create_cash_expense_event(
    v_household_id, now(), v_tag || '_CASH', 10, v_account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 10)),
    null, '40000000-0000-0000-0000-000000000002'::uuid
  );
  set constraints all immediate;
  if (select count(*) from public.envelope_movements where event_id = v_cash_event_id and movement_type = 'consumption') <> 1 then
    raise exception 'Cash expense consumption regressed';
  end if;
  set constraints all deferred;

  -- 3: a consumption linked to an income transaction remains rejected.
  v_income_event_id := public.create_cash_income_event(
    v_household_id, now(), v_tag || '_INCOME', 1, v_account_id, '[]'::jsonb,
    null, '40000000-0000-0000-0000-000000000003'::uuid
  );
  select id into v_income_transaction_id from public.financial_transactions where event_id = v_income_event_id;
  begin
    insert into public.envelope_movements(
      household_id, event_id, envelope_id, financial_transaction_id,
      movement_group_id, movement_type, direction, amount, occurred_at, description, created_by
    ) values (
      v_household_id, v_income_event_id, v_food_id, v_income_transaction_id,
      gen_random_uuid(), 'consumption', 'outflow', 1, now(), v_tag || '_INVALID_CONSUMPTION', v_actor_id
    );
    set constraints all immediate;
    raise exception 'Income consumption should fail';
  exception when others then
    if position('Expense envelope allocations must equal' in sqlerrm) = 0 then raise; end if;
  end;
  set constraints all deferred;

  -- 5: an invalid debt target rolls back every partial write.
  begin
    perform public.create_debt_expense_event(
      v_household_id, now(), v_tag || '_INVALID', 1,
      jsonb_build_array(jsonb_build_object('envelope_id', v_other_envelope_id, 'amount', 1)),
      'Créancier test', null, null,
      '40000000-0000-0000-0000-000000000004'::uuid
    );
    raise exception 'Cross-household envelope should fail';
  exception when others then
    if position('active ordinary household envelope' in sqlerrm) = 0 then raise; end if;
  end;
  if exists (select 1 from public.financial_events where description = v_tag || '_INVALID') then
    raise exception 'Failed debt expense left a FinancialEvent';
  end if;
end;
$$;

rollback;

select 6 as total, 6 as passed, 0 as failed, true as transactional_rollback_confirmed;
