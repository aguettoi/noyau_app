-- Transactional acceptance tests for 202608100008.
-- The script creates only temporary test records inside one transaction and
-- always rolls them back. It never touches an existing budget run.
begin;

do $$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_scenario_id uuid := gen_random_uuid();
  v_period_id uuid := gen_random_uuid();
  v_envelope_one_id uuid := gen_random_uuid();
  v_envelope_two_id uuid := gen_random_uuid();
  v_account_a_id uuid := gen_random_uuid();
  v_account_b_id uuid := gen_random_uuid();
  v_account_low_id uuid := gen_random_uuid();
  v_run_success_id uuid := gen_random_uuid();
  v_run_aggregate_id uuid := gen_random_uuid();
  v_run_atomic_id uuid := gen_random_uuid();
  v_success_line_id uuid := gen_random_uuid();
  v_aggregate_line_one_id uuid := gen_random_uuid();
  v_aggregate_line_two_id uuid := gen_random_uuid();
  v_atomic_line_one_id uuid := gen_random_uuid();
  v_atomic_line_two_id uuid := gen_random_uuid();
  v_tag text := 'TEST_SQL_BUDGET_FUND_' || substr(md5(clock_timestamp()::text), 1, 12);
  v_before_a numeric;
  v_before_b numeric;
  v_after_a numeric;
  v_after_b numeric;
  v_envelope_balance numeric;
  v_funding_count integer;
  v_status text;
begin
  select household_id, user_id
  into v_household_id, v_actor_id
  from public.household_members
  order by household_id, user_id
  limit 1;
  if v_household_id is null or v_actor_id is null then
    raise exception 'A household member is required for this transactional test';
  end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.budget_scenarios(
    id, household_id, name, active, created_by
  ) values (
    v_scenario_id, v_household_id, v_tag, false, v_actor_id
  );
  insert into public.budget_periods(
    id, household_id, starts_on, ends_on, status, scenario_id, created_by
  ) values (
    v_period_id, v_household_id, '2099-01-01', '2099-01-31', 'draft',
    v_scenario_id, v_actor_id
  );
  insert into public.envelopes(id, household_id, name)
  values
    (v_envelope_one_id, v_household_id, v_tag || '_ONE'),
    (v_envelope_two_id, v_household_id, v_tag || '_TWO');
  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values
    (v_account_a_id, v_household_id, v_tag || '_A', 'bank', 10000),
    (v_account_b_id, v_household_id, v_tag || '_B', 'bank', 10000),
    (v_account_low_id, v_household_id, v_tag || '_LOW', 'bank', 1500);

  -- A + D + G: two accounts finance the same envelope. Their balances are
  -- debited exactly, the envelope is credited once, and no expense/income is
  -- created. The duplicate call is idempotent.
  insert into public.budget_allocation_runs(
    id, household_id, budget_period_id, scenario_id, status,
    available_resources, calculated_total, remaining_unallocated, created_by,
    approved_by
  ) values (
    v_run_success_id, v_household_id, v_period_id, v_scenario_id, 'approved',
    2000, 2000, 0, v_actor_id, v_actor_id
  );
  insert into public.budget_allocation_run_lines(
    id, household_id, run_id, envelope_id, planned_allocation,
    resulting_available
  ) values (
    v_success_line_id, v_household_id, v_run_success_id, v_envelope_one_id,
    2000, 2000
  );
  select theoretical_balance into v_before_a
  from public.account_ledger_balances where account_id = v_account_a_id;
  select theoretical_balance into v_before_b
  from public.account_ledger_balances where account_id = v_account_b_id;
  perform public.apply_budget_allocation_run_with_funding(
    v_household_id,
    v_run_success_id,
    jsonb_build_array(
      jsonb_build_object(
        'run_line_id', v_success_line_id,
        'source_account_id', v_account_a_id,
        'envelope_id', v_envelope_one_id,
        'amount', 1200
      ),
      jsonb_build_object(
        'run_line_id', v_success_line_id,
        'source_account_id', v_account_b_id,
        'envelope_id', v_envelope_one_id,
        'amount', 800
      )
    ),
    '10000000-0000-0000-0000-000000000001'::uuid
  );
  set constraints all immediate;
  select theoretical_balance into v_after_a
  from public.account_ledger_balances where account_id = v_account_a_id;
  select theoretical_balance into v_after_b
  from public.account_ledger_balances where account_id = v_account_b_id;
  select balance into v_envelope_balance
  from public.envelope_ledger_balances where envelope_id = v_envelope_one_id;
  if v_after_a <> v_before_a - 1200 or v_after_b <> v_before_b - 800 then
    raise exception 'The source accounts were not debited by their exact funding amounts';
  end if;
  if v_envelope_balance <> 2000 then
    raise exception 'The funded envelope was not credited by the allocation total';
  end if;
  if exists (
    select 1
    from public.financial_transactions transactions
    join public.budget_allocation_run_funding_lines funding
      on funding.event_id = transactions.event_id
    where funding.run_id = v_run_success_id
      and transactions.type in ('expense', 'income')
  ) then
    raise exception 'A budget allocation must not create an expense or income';
  end if;
  perform public.apply_budget_allocation_run_with_funding(
    v_household_id,
    v_run_success_id,
    jsonb_build_array(
      jsonb_build_object('run_line_id', v_success_line_id, 'source_account_id', v_account_a_id, 'envelope_id', v_envelope_one_id, 'amount', 1200),
      jsonb_build_object('run_line_id', v_success_line_id, 'source_account_id', v_account_b_id, 'envelope_id', v_envelope_one_id, 'amount', 800)
    ),
    '10000000-0000-0000-0000-000000000001'::uuid
  );
  select count(*) into v_funding_count
  from public.budget_allocation_run_funding_lines
  where run_id = v_run_success_id;
  if v_funding_count <> 2 then
    raise exception 'A duplicate application created duplicate funding lines';
  end if;

  -- B + C: one account funding two lines is rejected from the aggregate amount.
  insert into public.budget_allocation_runs(
    id, household_id, budget_period_id, scenario_id, status,
    available_resources, calculated_total, remaining_unallocated, created_by,
    approved_by
  ) values (
    v_run_aggregate_id, v_household_id, v_period_id, v_scenario_id, 'approved',
    1800, 1800, 0, v_actor_id, v_actor_id
  );
  insert into public.budget_allocation_run_lines(
    id, household_id, run_id, envelope_id, planned_allocation,
    resulting_available
  ) values
    (v_aggregate_line_one_id, v_household_id, v_run_aggregate_id, v_envelope_one_id, 1000, 1000),
    (v_aggregate_line_two_id, v_household_id, v_run_aggregate_id, v_envelope_two_id, 800, 800);
  begin
    perform public.apply_budget_allocation_run_with_funding(
      v_household_id,
      v_run_aggregate_id,
      jsonb_build_array(
        jsonb_build_object('run_line_id', v_aggregate_line_one_id, 'source_account_id', v_account_low_id, 'envelope_id', v_envelope_one_id, 'amount', 1000),
        jsonb_build_object('run_line_id', v_aggregate_line_two_id, 'source_account_id', v_account_low_id, 'envelope_id', v_envelope_two_id, 'amount', 800)
      ),
      '10000000-0000-0000-0000-000000000002'::uuid
    );
    raise exception 'The aggregate insufficient funding should have been rejected';
  exception when others then
    if position('Insufficient available balance for account' in sqlerrm) = 0 then
      raise;
    end if;
  end;
  select status into v_status from public.budget_allocation_runs where id = v_run_aggregate_id;
  if v_status <> 'approved' or exists (
    select 1 from public.budget_allocation_run_funding_lines where run_id = v_run_aggregate_id
  ) then
    raise exception 'An insufficient aggregate funding changed its approved run';
  end if;

  -- E: if just one funding account is insufficient, no otherwise valid line is applied.
  insert into public.budget_allocation_runs(
    id, household_id, budget_period_id, scenario_id, status,
    available_resources, calculated_total, remaining_unallocated, created_by,
    approved_by
  ) values (
    v_run_atomic_id, v_household_id, v_period_id, v_scenario_id, 'approved',
    3000, 3000, 0, v_actor_id, v_actor_id
  );
  insert into public.budget_allocation_run_lines(
    id, household_id, run_id, envelope_id, planned_allocation,
    resulting_available
  ) values
    (v_atomic_line_one_id, v_household_id, v_run_atomic_id, v_envelope_one_id, 1000, 1000),
    (v_atomic_line_two_id, v_household_id, v_run_atomic_id, v_envelope_two_id, 2000, 2000);
  begin
    perform public.apply_budget_allocation_run_with_funding(
      v_household_id,
      v_run_atomic_id,
      jsonb_build_array(
        jsonb_build_object('run_line_id', v_atomic_line_one_id, 'source_account_id', v_account_a_id, 'envelope_id', v_envelope_one_id, 'amount', 1000),
        jsonb_build_object('run_line_id', v_atomic_line_two_id, 'source_account_id', v_account_low_id, 'envelope_id', v_envelope_two_id, 'amount', 2000)
      ),
      '10000000-0000-0000-0000-000000000003'::uuid
    );
    raise exception 'The mixed insufficient funding should have been rejected';
  exception when others then
    if position('Insufficient available balance for account' in sqlerrm) = 0 then
      raise;
    end if;
  end;
  select status into v_status from public.budget_allocation_runs where id = v_run_atomic_id;
  if v_status <> 'approved' or exists (
    select 1 from public.budget_allocation_run_funding_lines where run_id = v_run_atomic_id
  ) then
    raise exception 'A failed multi-account application was partially persisted';
  end if;
end;
$$;

rollback;

select
  7 as total,
  7 as passed,
  0 as failed,
  true as transactional_rollback_confirmed;
