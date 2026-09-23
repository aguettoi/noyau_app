-- Shopping List MVP: every fixture is rolled back. No financial ledger may move.
begin;

do $$
declare
  v_actor_id uuid;
  v_other_actor_id uuid;
  v_household_id uuid;
  v_other_household_id uuid;
  v_envelope_id uuid;
  v_other_envelope_id uuid;
  v_goal_id uuid;
  v_item_id uuid;
  v_events_before integer;
  v_transactions_before integer;
  v_postings_before integer;
  v_movements_before integer;
  v_obligations_before integer;
begin
  select user_id into v_actor_id from public.household_members order by created_at limit 1;
  select user_id into v_other_actor_id from public.household_members where user_id <> v_actor_id order by created_at limit 1;
  if v_actor_id is null then raise exception 'No test actor is available'; end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);

  insert into public.households(name, classification) values ('SQL TEST — Shopping List', 'technical') returning id into v_household_id;
  insert into public.household_members(household_id, user_id, role) values (v_household_id, v_actor_id, 'owner');
  insert into public.envelopes(household_id, name) values (v_household_id, 'Achat voiture') returning id into v_envelope_id;
  v_goal_id := public.create_budget_goal(v_household_id, 'Voiture test', 'car', 10000, null, 1, v_envelope_id, null, null, 'planned');

  insert into public.households(name, classification) values ('SQL TEST — Shopping other household', 'technical') returning id into v_other_household_id;
  insert into public.envelopes(household_id, name) values (v_other_household_id, 'Étrangère') returning id into v_other_envelope_id;

  select count(*) into v_events_before from public.financial_events where household_id = v_household_id;
  select count(*) into v_transactions_before from public.financial_transactions where household_id = v_household_id;
  select count(*) into v_postings_before
  from public.financial_transaction_lines line
  join public.financial_transactions transaction on transaction.id = line.transaction_id
  where transaction.household_id = v_household_id;
  select count(*) into v_movements_before from public.envelope_movements where household_id = v_household_id;
  select count(*) into v_obligations_before from public.obligations where household_id = v_household_id;

  v_item_id := public.create_shopping_item(v_household_id, 'Poussette', 1500, 'Comparatif à faire', date '2026-12-01', v_envelope_id, v_goal_id, 1);
  if (select status from public.shopping_items where id = v_item_id) <> 'planned'
     or (select created_by from public.shopping_items where id = v_item_id) <> v_actor_id
     or (select final_priority from public.shopping_items where id = v_item_id) <> 1 then
    raise exception 'Shopping item creation or actor failed';
  end if;

  perform public.update_shopping_item(v_household_id, v_item_id, 'Poussette évolutive', 1600, 'Comparatif final', date '2026-12-15', v_envelope_id, v_goal_id, 0);
  if (select label from public.shopping_items where id = v_item_id) <> 'Poussette évolutive'
     or (select final_priority from public.shopping_items where id = v_item_id) <> 0 then
    raise exception 'Shopping item update failed';
  end if;

  perform public.set_shopping_item_member_priority(v_household_id, v_item_id, v_actor_id, 2);
  if (select priority from public.shopping_item_member_priorities where shopping_item_id = v_item_id and member_user_id = v_actor_id) <> 2 then
    raise exception 'Member priority was not persisted';
  end if;

  begin
    perform public.set_shopping_item_member_priority(v_household_id, v_item_id, coalesce(v_other_actor_id, gen_random_uuid()), 1);
    raise exception 'Expected rejection when writing another member priority';
  exception when others then
    if position('propre priorité' in sqlerrm) = 0 then raise; end if;
  end;

  begin
    perform public.create_shopping_item(v_household_id, 'Mismatch', 100, null, null, v_other_envelope_id, v_goal_id, null);
    raise exception 'Expected envelope/goal cross household rejection';
  exception when others then
    if position('enveloppe' in lower(sqlerrm)) = 0 then raise; end if;
  end;
  begin
    perform public.create_shopping_item(v_other_household_id, 'Autre foyer', 100, null, null, null, null, null);
    raise exception 'Expected household isolation rejection';
  exception when others then
    if position('accès non autorisé' in lower(sqlerrm)) = 0 then raise; end if;
  end;

  perform public.cancel_shopping_item(v_household_id, v_item_id, 'Report du projet');
  if (select status from public.shopping_items where id = v_item_id) <> 'cancelled' then raise exception 'Cancellation failed'; end if;
  perform public.archive_shopping_item(v_household_id, v_item_id, 'Classé');
  if (select status from public.shopping_items where id = v_item_id) <> 'archived' then raise exception 'Archive failed'; end if;
  if (select count(*) from public.shopping_item_history where shopping_item_id = v_item_id) <> 5 then
    raise exception 'Expected append-only history entries';
  end if;

  if (select count(*) from public.financial_events where household_id = v_household_id) <> v_events_before
     or (select count(*) from public.financial_transactions where household_id = v_household_id) <> v_transactions_before
     or (select count(*) from public.financial_transaction_lines line
         join public.financial_transactions transaction on transaction.id = line.transaction_id
         where transaction.household_id = v_household_id) <> v_postings_before
     or (select count(*) from public.envelope_movements where household_id = v_household_id) <> v_movements_before
     or (select count(*) from public.obligations where household_id = v_household_id) <> v_obligations_before then
    raise exception 'Shopping List must never create a financial ledger entry';
  end if;
end;
$$;

select 'shopping_list_mvp: 12/12 passed (transaction rolled back)' as result;
rollback;
