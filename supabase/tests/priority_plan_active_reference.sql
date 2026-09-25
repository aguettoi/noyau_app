-- PRIOS active reference: every assertion is rolled back and no financial
-- object is created by plan activation.
begin;

do $$
declare
  v_actor_id uuid;
  v_household_id uuid;
  v_other_household_id uuid;
  v_first_plan_id uuid;
  v_second_plan_id uuid;
  v_history_before integer;
  v_events_before integer;
  v_transactions_before integer;
  v_postings_before integer;
  v_movements_before integer;
begin
  select user_id into v_actor_id
  from public.household_members
  order by created_at
  limit 1;
  if v_actor_id is null then
    raise exception 'A test actor is required';
  end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);

  insert into public.households(name, classification)
  values ('SQL TEST — PRIOS active reference', 'technical')
  returning id into v_household_id;
  insert into public.household_members(household_id, user_id, role)
  values (v_household_id, v_actor_id, 'owner');

  insert into public.households(name, classification)
  values ('SQL TEST — PRIOS active reference other', 'technical')
  returning id into v_other_household_id;
  insert into public.household_members(household_id, user_id, role)
  values (v_other_household_id, v_actor_id, 'owner');

  v_first_plan_id := public.create_priority_plan(
    v_household_id, 'Reference 1', 5000, null
  );
  v_second_plan_id := public.create_priority_plan(
    v_household_id, 'Reference 2', 3000, null
  );

  select count(*) into v_events_before
  from public.financial_events where household_id = v_household_id;
  select count(*) into v_transactions_before
  from public.financial_transactions where household_id = v_household_id;
  select count(*) into v_postings_before
  from public.financial_transaction_lines line
  join public.financial_transactions transaction on transaction.id = line.transaction_id
  where transaction.household_id = v_household_id;
  select count(*) into v_movements_before
  from public.envelope_movements where household_id = v_household_id;

  perform public.activate_priority_plan(v_household_id, v_first_plan_id);
  if (select count(*) from public.priority_plans
      where household_id = v_household_id and status = 'active') <> 1
     or (select status from public.priority_plans where id = v_first_plan_id) <> 'active' then
    raise exception 'First activation did not set exactly one active reference';
  end if;

  select count(*) into v_history_before
  from public.priority_plan_history where plan_id = v_first_plan_id;
  perform public.activate_priority_plan(v_household_id, v_first_plan_id);
  if (select count(*) from public.priority_plan_history where plan_id = v_first_plan_id) <> v_history_before then
    raise exception 'Activation replay must be idempotent';
  end if;

  perform public.activate_priority_plan(v_household_id, v_second_plan_id);
  if (select status from public.priority_plans where id = v_first_plan_id) <> 'planned'
     or (select status from public.priority_plans where id = v_second_plan_id) <> 'active'
     or (select count(*) from public.priority_plans
         where household_id = v_household_id and status = 'active') <> 1 then
    raise exception 'Reference switch was not atomic';
  end if;

  perform public.set_priority_plan_status(v_household_id, v_first_plan_id, 'active');
  if (select status from public.priority_plans where id = v_first_plan_id) <> 'active'
     or (select status from public.priority_plans where id = v_second_plan_id) <> 'planned' then
    raise exception 'Legacy status entrypoint did not delegate to activation';
  end if;

  begin
    perform public.activate_priority_plan(v_other_household_id, v_first_plan_id);
    raise exception 'Expected household isolation rejection';
  exception when others then
    if position('introuvable' in sqlerrm) = 0 then raise; end if;
  end;

  begin
    update public.priority_plans set status = 'active'
    where id = v_second_plan_id;
    raise exception 'Expected partial unique index rejection';
  exception when unique_violation then
    null;
  end;

  if (select count(*) from public.financial_events where household_id = v_household_id) <> v_events_before
     or (select count(*) from public.financial_transactions where household_id = v_household_id) <> v_transactions_before
     or (select count(*) from public.financial_transaction_lines line
         join public.financial_transactions transaction on transaction.id = line.transaction_id
         where transaction.household_id = v_household_id) <> v_postings_before
     or (select count(*) from public.envelope_movements where household_id = v_household_id) <> v_movements_before then
    raise exception 'Activation must not create financial objects';
  end if;
end;
$$;

rollback;
