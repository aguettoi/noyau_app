-- Transactional MVP recipe. It deliberately rolls back every fixture.
begin;

do $$
declare
  v_actor_id uuid;
  v_household_id uuid;
  v_other_household_id uuid;
  v_envelope_id uuid;
  v_second_envelope_id uuid;
  v_archived_envelope_id uuid;
  v_system_envelope_id uuid;
  v_other_envelope_id uuid;
  v_goal_id uuid;
  v_second_goal_id uuid;
  v_before_events integer;
  v_before_movements integer;
  v_history_count integer;
begin
  select user_id into v_actor_id
  from public.household_members
  order by created_at
  limit 1;
  if v_actor_id is null then
    raise exception 'No authenticated fixture actor is available';
  end if;

  insert into public.households(name, classification)
  values ('SQL TEST — Budget goals MVP', 'technical')
  returning id into v_household_id;
  insert into public.household_members(household_id, user_id, role)
  values (v_household_id, v_actor_id, 'owner');
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);

  insert into public.envelopes(household_id, name)
  values (v_household_id, 'Objectif voiture')
  returning id into v_envelope_id;
  insert into public.envelopes(household_id, name)
  values (v_household_id, 'Objectif voyage')
  returning id into v_second_envelope_id;
  insert into public.envelopes(household_id, name, archived_at)
  values (v_household_id, 'Ancienne enveloppe', now())
  returning id into v_archived_envelope_id;
  insert into public.envelopes(household_id, name, is_system, system_code)
  values (v_household_id, 'À répartir', true, 'to_allocate')
  returning id into v_system_envelope_id;

  insert into public.households(name, classification)
  values ('SQL TEST — Other household', 'technical')
  returning id into v_other_household_id;
  insert into public.envelopes(household_id, name)
  values (v_other_household_id, 'Enveloppe étrangère')
  returning id into v_other_envelope_id;

  select count(*) into v_before_events from public.financial_events where household_id = v_household_id;
  select count(*) into v_before_movements from public.envelope_movements where household_id = v_household_id;

  v_goal_id := public.create_budget_goal(
    v_household_id, 'Voiture familiale', 'car', 100000, date '2027-10-01',
    1, v_envelope_id, 7500, 'Objectif de test', 'active'
  );
  if (select status from public.budget_goals where id = v_goal_id) <> 'active'
    or (select created_by from public.budget_goals where id = v_goal_id) <> v_actor_id
    or (select updated_by from public.budget_goals where id = v_goal_id) <> v_actor_id then
    raise exception 'Goal creation did not preserve server actor and active status';
  end if;
  select count(*) into v_history_count from public.budget_goal_history where goal_id = v_goal_id;
  if v_history_count <> 1 then raise exception 'Goal creation history is missing'; end if;

  -- Same active envelope must be rejected and leave no second goal.
  begin
    perform public.create_budget_goal(
      v_household_id, 'Doublon', 'custom', 10, null, 0, v_envelope_id, null, null, 'planned'
    );
    raise exception 'Expected duplicate envelope rejection';
  exception when others then
    if position('finance déjà un objectif' in sqlerrm) = 0
      and position('duplicate key' in sqlerrm) = 0 then raise; end if;
  end;

  begin
    perform public.create_budget_goal(
      v_household_id, 'Système', 'custom', 10, null, 0, v_system_envelope_id, null, null, 'planned'
    );
    raise exception 'Expected system envelope rejection';
  exception when others then
    if position('enveloppe système' in lower(sqlerrm)) = 0 then raise; end if;
  end;

  begin
    perform public.create_budget_goal(
      v_household_id, 'Archivé', 'custom', 10, null, 0, v_archived_envelope_id, null, null, 'planned'
    );
    raise exception 'Expected archived envelope rejection';
  exception when others then
    if position('enveloppe archivée' in lower(sqlerrm)) = 0 then raise; end if;
  end;

  begin
    perform public.create_budget_goal(
      v_household_id, 'Autre foyer', 'custom', 10, null, 0, v_other_envelope_id, null, null, 'planned'
    );
    raise exception 'Expected cross-household envelope rejection';
  exception when others then
    if position('n''est pas valide' in sqlerrm) = 0 then raise; end if;
  end;

  perform public.update_budget_goal(
    v_household_id, v_goal_id, 'Voiture familiale', 'car', 110000,
    date '2027-12-01', 2, v_envelope_id, 8000, 'Cible révisée'
  );
  if (select target_amount from public.budget_goals where id = v_goal_id) <> 110000
    or (select updated_by from public.budget_goals where id = v_goal_id) <> v_actor_id then
    raise exception 'Goal update did not persist target and server actor';
  end if;

  perform public.set_budget_goal_status(v_household_id, v_goal_id, 'paused');
  perform public.set_budget_goal_status(v_household_id, v_goal_id, 'active');
  if (select status from public.budget_goals where id = v_goal_id) <> 'active' then
    raise exception 'Pause/resume did not restore active status';
  end if;

  perform public.set_budget_goal_status(v_household_id, v_goal_id, 'completed', 'Validation utilisateur');
  if (select status from public.budget_goals where id = v_goal_id) <> 'completed'
    or (select closed_by from public.budget_goals where id = v_goal_id) <> v_actor_id then
    raise exception 'Explicit completion did not record closure actor';
  end if;

  -- A closed goal releases its envelope; this verifies the non-closed scope.
  v_second_goal_id := public.create_budget_goal(
    v_household_id, 'Nouveau projet', 'travel', 15000, null,
    1, v_envelope_id, null, null, 'planned'
  );
  perform public.set_budget_goal_status(v_household_id, v_second_goal_id, 'cancelled', 'Projet abandonné');

  if (select count(*) from public.financial_events where household_id = v_household_id) <> v_before_events
    or (select count(*) from public.envelope_movements where household_id = v_household_id) <> v_before_movements then
    raise exception 'Goal management must not create financial or envelope ledger entries';
  end if;
end;
$$;

select 'budget_goals_mvp: 11/11 passed (transaction rolled back)' as result;
rollback;
