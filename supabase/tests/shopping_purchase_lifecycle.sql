-- Shopping purchase lifecycle: every fixture is rolled back.
-- The Shopping link consumes an already-created canonical expense and never
-- writes a second FinancialEvent, GL transaction, posting or envelope movement.
begin;

do $$
declare
  v_actor_id uuid;
  v_household_id uuid;
  v_other_household_id uuid;
  v_account_id uuid;
  v_envelope_id uuid;
  v_item_id uuid;
  v_second_item_id uuid;
  v_event_id uuid;
  v_events_before_link integer;
  v_transactions_before_link integer;
  v_postings_before_link integer;
  v_movements_before_link integer;
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
  values ('SQL TEST — Shopping purchase lifecycle', 'technical')
  returning id into v_household_id;
  insert into public.household_members(household_id, user_id, role)
  values (v_household_id, v_actor_id, 'owner');
  insert into public.accounts(household_id, name, kind)
  values (v_household_id, 'Compte achat test', 'bank')
  returning id into v_account_id;
  insert into public.envelopes(household_id, name)
  values (v_household_id, 'Enveloppe achat test')
  returning id into v_envelope_id;

  v_item_id := public.create_shopping_item(
    v_household_id, 'Canapé test', 1200, 'Estimation conservée',
    null, v_envelope_id, null, null
  );
  v_second_item_id := public.create_shopping_item(
    v_household_id, 'TV test', 800, null, null, v_envelope_id, null, null
  );

  -- The only financial operation in this test is created by the canonical flow.
  v_event_id := public.create_cash_expense_event(
    v_household_id, now(), 'Dépense canonique canapé', 1000, v_account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', v_envelope_id, 'amount', 1000)),
    'Depuis le flux canonique', gen_random_uuid()
  );

  select count(*) into v_events_before_link
  from public.financial_events where household_id = v_household_id;
  select count(*) into v_transactions_before_link
  from public.financial_transactions where household_id = v_household_id;
  select count(*) into v_postings_before_link
  from public.financial_transaction_lines line
  join public.financial_transactions transaction on transaction.id = line.transaction_id
  where transaction.household_id = v_household_id;
  select count(*) into v_movements_before_link
  from public.envelope_movements where household_id = v_household_id;

  perform public.purchase_shopping_item_with_expense(
    v_household_id, v_item_id, v_event_id
  );

  if (select status from public.shopping_items where id = v_item_id) <> 'purchased'
     or (select purchased_financial_event_id from public.shopping_items where id = v_item_id) <> v_event_id
     or (select estimated_amount from public.shopping_items where id = v_item_id) <> 1200 then
    raise exception 'The purchase link did not preserve the Shopping intent';
  end if;
  if (select count(*) from public.shopping_item_history
      where shopping_item_id = v_item_id and action = 'purchased') <> 1 then
    raise exception 'The purchase history entry is missing';
  end if;

  if (select count(*) from public.financial_events where household_id = v_household_id) <> v_events_before_link
     or (select count(*) from public.financial_transactions where household_id = v_household_id) <> v_transactions_before_link
     or (select count(*) from public.financial_transaction_lines line
         join public.financial_transactions transaction on transaction.id = line.transaction_id
         where transaction.household_id = v_household_id) <> v_postings_before_link
     or (select count(*) from public.envelope_movements where household_id = v_household_id) <> v_movements_before_link then
    raise exception 'Shopping linking must not create a second financial impact';
  end if;

  begin
    perform public.purchase_shopping_item_with_expense(v_household_id, v_second_item_id, v_event_id);
    raise exception 'Expected duplicate financial-event link rejection';
  exception when others then
    if position('déjà rattachée' in sqlerrm) = 0 then raise; end if;
  end;

  insert into public.households(name, classification)
  values ('SQL TEST — Shopping purchase other household', 'technical')
  returning id into v_other_household_id;
  begin
    perform public.purchase_shopping_item_with_expense(v_other_household_id, v_second_item_id, v_event_id);
    raise exception 'Expected household isolation rejection';
  exception when others then
    if position('accès non autorisé' in lower(sqlerrm)) = 0 then raise; end if;
  end;
end;
$$;

select 'shopping_purchase_lifecycle: 7/7 passed (transaction rolled back)' as result;
rollback;
