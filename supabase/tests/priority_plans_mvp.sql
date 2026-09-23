-- PRIOS MVP: every fixture is rolled back. Planning cannot move financial ledgers.
begin;

do $$
declare
  v_actor_id uuid;
  v_household_id uuid;
  v_other_household_id uuid;
  v_envelope_id uuid;
  v_other_envelope_id uuid;
  v_goal_id uuid;
  v_linked_item_id uuid;
  v_item_id uuid;
  v_other_item_id uuid;
  v_plan_id uuid;
  v_goal_plan_item_id uuid;
  v_shopping_plan_item_id uuid;
  v_events_before integer;
  v_transactions_before integer;
  v_postings_before integer;
  v_movements_before integer;
  v_obligations_before integer;
begin
  select user_id into v_actor_id from public.household_members order by created_at limit 1;
  if v_actor_id is null then raise exception 'A test actor is required'; end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);

  insert into public.households(name, classification)
  values ('SQL TEST — PRIOS', 'technical') returning id into v_household_id;
  insert into public.household_members(household_id, user_id, role)
  values (v_household_id, v_actor_id, 'owner');
  insert into public.envelopes(household_id, name)
  values (v_household_id, 'Projet test') returning id into v_envelope_id;
  v_goal_id := public.create_budget_goal(
    v_household_id, 'Voiture PRIOS', 'car', 10000, null, 1,
    v_envelope_id, null, null, 'planned'
  );
  v_linked_item_id := public.create_shopping_item(
    v_household_id, 'TV liée à voiture', 2000, null, null,
    v_envelope_id, v_goal_id, null
  );
  v_item_id := public.create_shopping_item(
    v_household_id, 'Canapé PRIOS', 5000, null, null,
    null, null, null
  );
  insert into public.households(name, classification)
  values ('SQL TEST — PRIOS other household', 'technical') returning id into v_other_household_id;
  insert into public.envelopes(household_id, name)
  values (v_other_household_id, 'Autre projet') returning id into v_other_envelope_id;
  insert into public.household_members(household_id, user_id, role)
  values (v_other_household_id, v_actor_id, 'owner');
  v_other_item_id := public.create_shopping_item(
    v_other_household_id, 'Autre foyer', 100, null, null,
    v_other_envelope_id, null, null
  );

  select count(*) into v_events_before from public.financial_events where household_id = v_household_id;
  select count(*) into v_transactions_before from public.financial_transactions where household_id = v_household_id;
  select count(*) into v_postings_before from public.financial_transaction_lines line
    join public.financial_transactions transaction on transaction.id = line.transaction_id
    where transaction.household_id = v_household_id;
  select count(*) into v_movements_before from public.envelope_movements where household_id = v_household_id;
  select count(*) into v_obligations_before from public.obligations where household_id = v_household_id;

  v_plan_id := public.create_priority_plan(v_household_id, 'Plan famille', 5000, 'Projection pure');
  if (select created_by from public.priority_plans where id = v_plan_id) <> v_actor_id
     or (select monthly_capacity from public.priority_plans where id = v_plan_id) <> 5000 then
    raise exception 'Plan creation or actor failed';
  end if;

  v_goal_plan_item_id := public.add_priority_plan_item(v_household_id, v_plan_id, null, v_goal_id);
  v_shopping_plan_item_id := public.add_priority_plan_item(v_household_id, v_plan_id, v_item_id, null);
  if (select array_agg(rank order by rank) from public.priority_plan_items where plan_id = v_plan_id) <> array[1, 2] then
    raise exception 'Initial priority order failed';
  end if;

  begin
    perform public.add_priority_plan_item(v_household_id, v_plan_id, v_item_id, null);
    raise exception 'Expected duplicate source rejection';
  exception when others then
    if position('déjà présent' in sqlerrm) = 0 then raise; end if;
  end;
  begin
    perform public.add_priority_plan_item(v_household_id, v_plan_id, v_linked_item_id, null);
    raise exception 'Expected linked shopping/goal rejection';
  exception when others then
    if position('déjà relié' in sqlerrm) = 0 then raise; end if;
  end;
  begin
    perform public.add_priority_plan_item(v_household_id, v_plan_id, v_other_item_id, null);
    raise exception 'Expected cross household source rejection';
  exception when others then
    if position('valide' in sqlerrm) = 0 then raise; end if;
  end;

  perform public.reorder_priority_plan_items(
    v_household_id, v_plan_id, array[v_shopping_plan_item_id, v_goal_plan_item_id]
  );
  if (select id from public.priority_plan_items where plan_id = v_plan_id and rank = 1) <> v_shopping_plan_item_id then
    raise exception 'Reorder failed';
  end if;
  perform public.remove_priority_plan_item(v_household_id, v_plan_id, v_shopping_plan_item_id);
  if exists (select 1 from public.priority_plan_items where id = v_shopping_plan_item_id)
     or not exists (select 1 from public.shopping_items where id = v_item_id) then
    raise exception 'Removing priority must retain its source';
  end if;
  perform public.set_priority_plan_status(v_household_id, v_plan_id, 'active');
  perform public.set_priority_plan_status(v_household_id, v_plan_id, 'paused');
  perform public.set_priority_plan_status(v_household_id, v_plan_id, 'archived');
  if (select status from public.priority_plans where id = v_plan_id) <> 'archived' then
    raise exception 'Plan archive failed';
  end if;

  if (select count(*) from public.priority_plan_history where plan_id = v_plan_id) <> 8 then
    raise exception 'Expected append-only plan history';
  end if;
  if (select count(*) from public.financial_events where household_id = v_household_id) <> v_events_before
     or (select count(*) from public.financial_transactions where household_id = v_household_id) <> v_transactions_before
     or (select count(*) from public.financial_transaction_lines line join public.financial_transactions transaction on transaction.id = line.transaction_id where transaction.household_id = v_household_id) <> v_postings_before
     or (select count(*) from public.envelope_movements where household_id = v_household_id) <> v_movements_before
     or (select count(*) from public.obligations where household_id = v_household_id) <> v_obligations_before then
    raise exception 'PRIOS must never create a financial ledger entry';
  end if;
end;
$$;

select 'priority_plans_mvp: 15/15 passed (transaction rolled back)' as result;
rollback;
