-- Additional transactional regression checks for the budget-allocation GL
-- counterpart. All fixtures and writes are rolled back.
begin;

do $$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_other_household_id uuid := gen_random_uuid();
  v_scenario_id uuid := gen_random_uuid();
  v_period_id uuid := gen_random_uuid();
  v_account_a uuid := gen_random_uuid();
  v_account_b uuid := gen_random_uuid();
  v_other_account uuid := gen_random_uuid();
  v_envelope_one uuid := gen_random_uuid();
  v_envelope_two uuid := gen_random_uuid();
  v_envelope_three uuid := gen_random_uuid();
  v_other_envelope uuid := gen_random_uuid();
  v_run_one uuid := gen_random_uuid();
  v_run_two uuid := gen_random_uuid();
  v_run_three uuid := gen_random_uuid();
  v_other_run uuid := gen_random_uuid();
  v_line_one uuid := gen_random_uuid();
  v_line_two_a uuid := gen_random_uuid();
  v_line_two_b uuid := gen_random_uuid();
  v_line_three_a uuid := gen_random_uuid();
  v_line_three_b uuid := gen_random_uuid();
  v_other_line uuid := gen_random_uuid();
  v_tag text := 'TEST_SQL_BUDGET_COUNTERPART_' || substr(md5(clock_timestamp()::text), 1, 12);
  v_before_to_allocate numeric;
  v_after_to_allocate numeric;
  v_event_count integer;
begin
  select household_id, user_id into v_household_id, v_actor_id
  from public.household_members order by household_id, user_id limit 1;
  if v_household_id is null then
    raise exception 'A household member is required for this transactional test';
  end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.budget_scenarios(id, household_id, name, active, created_by)
  values (v_scenario_id, v_household_id, v_tag, false, v_actor_id);
  insert into public.budget_periods(id, household_id, starts_on, ends_on, status, scenario_id, created_by)
  values (v_period_id, v_household_id, '2099-02-01', '2099-02-28', 'draft', v_scenario_id, v_actor_id);
  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values
    (v_account_a, v_household_id, v_tag || '_A', 'bank', 1000),
    (v_account_b, v_household_id, v_tag || '_B', 'bank', 1000);
  insert into public.envelopes(id, household_id, name)
  values
    (v_envelope_one, v_household_id, v_tag || '_ONE'),
    (v_envelope_two, v_household_id, v_tag || '_TWO'),
    (v_envelope_three, v_household_id, v_tag || '_THREE');

  perform public.ensure_household_system_envelope(v_household_id, 'to_allocate');
  select balance into v_before_to_allocate
  from public.envelope_ledger_balances balances
  join public.envelopes envelopes on envelopes.id = balances.envelope_id
  where balances.household_id = v_household_id and envelopes.system_code = 'to_allocate';

  -- 1: one account funds one envelope.
  insert into public.budget_allocation_runs(id, household_id, budget_period_id, scenario_id, status, available_resources, calculated_total, remaining_unallocated, created_by, approved_by)
  values (v_run_one, v_household_id, v_period_id, v_scenario_id, 'approved', 100, 100, 0, v_actor_id, v_actor_id);
  insert into public.budget_allocation_run_lines(id, household_id, run_id, envelope_id, planned_allocation, resulting_available)
  values (v_line_one, v_household_id, v_run_one, v_envelope_one, 100, 100);
  perform public.apply_budget_allocation_run_with_funding(
    v_household_id, v_run_one,
    jsonb_build_array(jsonb_build_object('run_line_id', v_line_one, 'source_account_id', v_account_a, 'envelope_id', v_envelope_one, 'amount', 100)),
    '11111111-0000-0000-0000-000000000001'::uuid
  );

  -- 3: one account funds two envelopes.
  insert into public.budget_allocation_runs(id, household_id, budget_period_id, scenario_id, status, available_resources, calculated_total, remaining_unallocated, created_by, approved_by)
  values (v_run_two, v_household_id, v_period_id, v_scenario_id, 'approved', 100, 100, 0, v_actor_id, v_actor_id);
  insert into public.budget_allocation_run_lines(id, household_id, run_id, envelope_id, planned_allocation, resulting_available)
  values
    (v_line_two_a, v_household_id, v_run_two, v_envelope_one, 60, 60),
    (v_line_two_b, v_household_id, v_run_two, v_envelope_two, 40, 40);
  perform public.apply_budget_allocation_run_with_funding(
    v_household_id, v_run_two,
    jsonb_build_array(
      jsonb_build_object('run_line_id', v_line_two_a, 'source_account_id', v_account_a, 'envelope_id', v_envelope_one, 'amount', 60),
      jsonb_build_object('run_line_id', v_line_two_b, 'source_account_id', v_account_a, 'envelope_id', v_envelope_two, 'amount', 40)
    ), '11111111-0000-0000-0000-000000000002'::uuid
  );

  -- 4: two accounts fund two envelopes.
  insert into public.budget_allocation_runs(id, household_id, budget_period_id, scenario_id, status, available_resources, calculated_total, remaining_unallocated, created_by, approved_by)
  values (v_run_three, v_household_id, v_period_id, v_scenario_id, 'approved', 100, 100, 0, v_actor_id, v_actor_id);
  insert into public.budget_allocation_run_lines(id, household_id, run_id, envelope_id, planned_allocation, resulting_available)
  values
    (v_line_three_a, v_household_id, v_run_three, v_envelope_two, 50, 50),
    (v_line_three_b, v_household_id, v_run_three, v_envelope_three, 50, 50);
  perform public.apply_budget_allocation_run_with_funding(
    v_household_id, v_run_three,
    jsonb_build_array(
      jsonb_build_object('run_line_id', v_line_three_a, 'source_account_id', v_account_a, 'envelope_id', v_envelope_two, 'amount', 30),
      jsonb_build_object('run_line_id', v_line_three_a, 'source_account_id', v_account_b, 'envelope_id', v_envelope_two, 'amount', 20),
      jsonb_build_object('run_line_id', v_line_three_b, 'source_account_id', v_account_a, 'envelope_id', v_envelope_three, 'amount', 10),
      jsonb_build_object('run_line_id', v_line_three_b, 'source_account_id', v_account_b, 'envelope_id', v_envelope_three, 'amount', 40)
    ), '11111111-0000-0000-0000-000000000003'::uuid
  );
  set constraints all immediate;

  -- 10, 11 and 12: every funding event has one balanced allocation GL
  -- transaction, one ordinary-envelope inflow, no system-envelope movement,
  -- and no expense or income transaction.
  select count(*) into v_event_count
  from public.budget_allocation_run_funding_lines funding
  join public.financial_events events on events.id = funding.event_id
  join public.financial_transactions transactions on transactions.event_id = events.id
  where funding.run_id in (v_run_one, v_run_two, v_run_three)
    and events.event_type = 'budget_allocation'
    and transactions.type = 'allocation'
    and not exists (
      select 1 from public.envelope_movements movements
      join public.envelopes envelopes on envelopes.id = movements.envelope_id
      where movements.event_id = events.id and envelopes.system_code = 'to_allocate'
    )
    and exists (
      select 1 from public.financial_transaction_lines lines
      join public.accounts accounts on accounts.id = lines.account_id
      where lines.transaction_id = transactions.id
        and accounts.name = 'Système — À répartir'
        and lines.debit = transactions.amount and lines.credit = 0
    )
    and exists (
      select 1 from public.financial_transaction_lines lines
      where lines.transaction_id = transactions.id
        and lines.account_id = transactions.source_account_id
        and lines.credit = transactions.amount and lines.debit = 0
    )
    and exists (
      select 1 from public.envelope_movements movements
      where movements.event_id = events.id and movements.movement_type = 'allocation'
        and movements.direction = 'inflow' and movements.amount = transactions.amount
    );
  if v_event_count <> 7 then
    raise exception 'Budget allocation chain is incomplete or has the wrong economic posting';
  end if;
  if exists (
    select 1 from public.financial_transactions transactions
    join public.budget_allocation_run_funding_lines funding on funding.event_id = transactions.event_id
    where funding.run_id in (v_run_one, v_run_two, v_run_three)
      and transactions.type in ('income', 'expense')
  ) then
    raise exception 'Budget allocation created an income or expense';
  end if;
  select balance into v_after_to_allocate
  from public.envelope_ledger_balances balances
  join public.envelopes envelopes on envelopes.id = balances.envelope_id
  where balances.household_id = v_household_id and envelopes.system_code = 'to_allocate';
  if v_after_to_allocate <> v_before_to_allocate then
    raise exception 'Direct budget allocation changed the system envelope À répartir';
  end if;
  set constraints all deferred;

  -- 8: caller cannot apply an approved run of another household.
  insert into public.households(id, name) values (v_other_household_id, v_tag || '_OTHER');
  insert into public.budget_scenarios(id, household_id, name, active, created_by)
  values (gen_random_uuid(), v_other_household_id, v_tag || '_OTHER_SCENARIO', false, v_actor_id);
  insert into public.budget_periods(id, household_id, starts_on, ends_on, status, created_by)
  values (gen_random_uuid(), v_other_household_id, '2099-03-01', '2099-03-31', 'draft', v_actor_id);
  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values (v_other_account, v_other_household_id, v_tag || '_OTHER_ACCOUNT', 'bank', 100);
  insert into public.envelopes(id, household_id, name)
  values (v_other_envelope, v_other_household_id, v_tag || '_OTHER_ENVELOPE');
  -- Membership guard runs before access to the run; no persistent event can be created.
  begin
    perform public.apply_budget_allocation_run_with_funding(
      v_other_household_id, v_other_run, '[]'::jsonb,
      '11111111-0000-0000-0000-000000000004'::uuid
    );
    raise exception 'Other-household application was accepted';
  exception when others then
    if sqlerrm = 'Other-household application was accepted' then raise; end if;
    if position('Household access denied' in sqlerrm) = 0 then raise; end if;
  end;
end $$;

rollback;

select 5 as total, 5 as passed, 0 as failed,
  true as transactional_rollback_confirmed;
