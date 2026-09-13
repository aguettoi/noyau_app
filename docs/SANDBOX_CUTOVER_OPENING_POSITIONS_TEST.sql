-- Cutover A acceptance tests for canonical opening positions.
-- Run only after 20260913214354. Every object below is rolled back.
begin;

do $$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_other_household_id uuid := gen_random_uuid();
  v_account_id uuid := gen_random_uuid();
  v_second_account_id uuid := gen_random_uuid();
  v_other_account_id uuid := gen_random_uuid();
  v_food_id uuid := gen_random_uuid();
  v_travel_id uuid := gen_random_uuid();
  v_other_envelope_id uuid := gen_random_uuid();
  v_to_allocate_id uuid;
  v_account_event uuid;
  v_envelope_event uuid;
  v_opening_account_id uuid;
  v_before_account numeric;
  v_after_account numeric;
  v_tag text := 'TEST_CUTOVER_OPENING_' || substr(md5(clock_timestamp()::text), 1, 12);
begin
  select household_id, user_id into v_household_id, v_actor_id
  from public.household_members order by household_id, user_id limit 1;
  if v_household_id is null then raise exception 'A household member is required for this test'; end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values (v_account_id, v_household_id, v_tag || '_ACCOUNT', 'bank', 0);
  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values (v_second_account_id, v_household_id, v_tag || '_ACCOUNT_2', 'cash', 0);
  insert into public.envelopes(id, household_id, name)
  values (v_food_id, v_household_id, v_tag || '_FOOD'),
         (v_travel_id, v_household_id, v_tag || '_TRAVEL');
  select id into v_to_allocate_id from public.envelopes
  where household_id = v_household_id and system_code = 'to_allocate';
  if v_to_allocate_id is null then raise exception 'The system envelope À répartir is required'; end if;
  insert into public.households(id, name) values (v_other_household_id, v_tag || '_OTHER');
  insert into public.accounts(id, household_id, name, kind, opening_balance)
  values (v_other_account_id, v_other_household_id, v_tag || '_OTHER_ACCOUNT', 'bank', 0);
  insert into public.envelopes(id, household_id, name)
  values (v_other_envelope_id, v_other_household_id, v_tag || '_OTHER_ENVELOPE');

  -- 1-5: one account opening creates only the canonical event and balanced GL.
  select theoretical_balance into v_before_account from public.account_ledger_balances where account_id = v_account_id;
  v_account_event := public.create_account_opening_event(
    v_household_id, now(), v_tag || '_ACCOUNT_OPENING', 100, v_account_id,
    'opening test', '90000000-0000-0000-0000-000000000001'::uuid);
  set constraints all immediate;
  select theoretical_balance into v_after_account from public.account_ledger_balances where account_id = v_account_id;
  select id into v_opening_account_id from public.accounts
  where household_id = v_household_id and name = 'Système — Soldes d’ouverture' and is_system;
  if v_after_account <> v_before_account + 100
    or (select count(*) from public.financial_events where id=v_account_event and event_type='account_opening') <> 1
    or (select count(*) from public.financial_transactions where event_id=v_account_event and type='opening_balance') <> 1
    or (select coalesce(sum(debit),0) = 100 and coalesce(sum(credit),0) = 100
        from public.financial_transaction_lines p join public.financial_transactions t on t.id=p.transaction_id where t.event_id=v_account_event) is not true
    or not exists (select 1 from public.financial_transaction_lines p join public.financial_transactions t on t.id=p.transaction_id
                   where t.event_id=v_account_event and p.account_id=v_account_id and p.debit=100)
    or not exists (select 1 from public.financial_transaction_lines p join public.financial_transactions t on t.id=p.transaction_id
                   where t.event_id=v_account_event and p.account_id=v_opening_account_id and p.credit=100)
    or exists (select 1 from public.envelope_movements where event_id=v_account_event)
  then raise exception 'Account opening is not canonical'; end if;
  set constraints all deferred;

  -- 6: idempotency returns the existing event and creates no second transaction.
  if public.create_account_opening_event(v_household_id, now(), v_tag || '_ACCOUNT_OPENING', 100, v_account_id,
      'opening test', '90000000-0000-0000-0000-000000000001'::uuid) <> v_account_event
    or (select count(*) from public.financial_transactions where event_id=v_account_event) <> 1
  then raise exception 'Account opening idempotency failed'; end if;

  -- 7: several accounts remain independent canonical openings.
  perform public.create_account_opening_event(v_household_id, now(), v_tag || '_ACCOUNT_2_OPENING', 25, v_second_account_id, null,
    '90000000-0000-0000-0000-000000000008'::uuid);
  if (select count(*) from public.financial_transactions t join public.financial_events e on e.id=t.event_id
      where e.description=v_tag || '_ACCOUNT_2_OPENING' and t.type='opening_balance') <> 1
  then raise exception 'Second account opening was not recorded'; end if;

  -- 8-12: invalid values, target and actor are rejected without persistent event.
  begin
    perform public.create_account_opening_event(v_household_id, now(), v_tag || '_ZERO_ACCOUNT', 0, v_account_id, null,
      '90000000-0000-0000-0000-000000000009'::uuid);
    raise exception 'Zero account opening should fail';
  exception when others then if position('must be positive' in sqlerrm)=0 then raise; end if; end;
  begin
    perform public.create_account_opening_event(v_household_id, now(), v_tag || '_NEGATIVE', -1, v_account_id, null,
      '90000000-0000-0000-0000-000000000002'::uuid);
    raise exception 'Negative account opening should fail';
  exception when others then if position('must be positive' in sqlerrm)=0 then raise; end if; end;
  begin
    perform public.create_account_opening_event(v_household_id, now(), v_tag || '_OTHER', 1, v_other_account_id, null,
      '90000000-0000-0000-0000-000000000003'::uuid);
    raise exception 'Cross-household account opening should fail';
  exception when others then if position('ordinary account of the household' in sqlerrm)=0 then raise; end if; end;
  begin
    perform public.create_account_opening_event(v_household_id, now(), v_tag || '_MISSING', 1, gen_random_uuid(), null,
      '90000000-0000-0000-0000-000000000010'::uuid);
    raise exception 'Missing account opening should fail';
  exception when others then if position('ordinary account of the household' in sqlerrm)=0 then raise; end if; end;
  begin
    perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    perform public.create_account_opening_event(v_household_id, now(), v_tag || '_NON_MEMBER', 1, v_account_id, null,
      '90000000-0000-0000-0000-000000000011'::uuid);
    raise exception 'Non-member account opening should fail';
  exception when others then
    if position('Household access denied' in sqlerrm)=0 then raise; end if;
    perform set_config('request.jwt.claim.sub', v_actor_id::text, true);
  end;
  if exists (select 1 from public.financial_events where description like v_tag || '_ZERO_ACCOUNT%' or description like v_tag || '_NEGATIVE%'
      or description like v_tag || '_OTHER%' or description like v_tag || '_MISSING%' or description like v_tag || '_NON_MEMBER%')
  then raise exception 'Rejected account opening persisted data'; end if;

  -- 9-13: envelope openings are direct inflows only: no GL or bank impact, and À répartir is untouched by default.
  v_envelope_event := public.create_envelope_opening_event(
    v_household_id, now(), v_tag || '_ENVELOPE_OPENING',
    jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',60),jsonb_build_object('envelope_id',v_travel_id,'amount',40)),
    'envelope opening test', '90000000-0000-0000-0000-000000000004'::uuid);
  set constraints all immediate;
  if (select count(*) from public.financial_events where id=v_envelope_event and event_type='envelope_opening') <> 1
    or (select count(*) from public.envelope_movements where event_id=v_envelope_event and movement_type='opening' and direction='inflow') <> 2
    or (select coalesce(sum(amount),0) from public.envelope_movements where event_id=v_envelope_event) <> 100
    or exists (select 1 from public.financial_transactions where event_id=v_envelope_event)
    or exists (select 1 from public.envelope_movements where event_id=v_envelope_event and envelope_id=v_to_allocate_id)
  then raise exception 'Envelope opening is not a direct non-GL opening'; end if;
  set constraints all deferred;
  if public.create_envelope_opening_event(v_household_id, now(), v_tag || '_ENVELOPE_OPENING',
      jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',60),jsonb_build_object('envelope_id',v_travel_id,'amount',40)),
      'envelope opening test', '90000000-0000-0000-0000-000000000004'::uuid) <> v_envelope_event
    or (select count(*) from public.envelope_movements where event_id=v_envelope_event) <> 2
  then raise exception 'Envelope opening idempotency failed'; end if;

  -- 14: À répartir is a normal opening target only when explicitly requested.
  perform public.create_envelope_opening_event(v_household_id, now(), v_tag || '_TO_ALLOCATE_EXPLICIT',
    jsonb_build_array(jsonb_build_object('envelope_id',v_to_allocate_id,'amount',5)), null,
    '90000000-0000-0000-0000-000000000012'::uuid);
  if not exists (select 1 from public.envelope_movements m join public.financial_events e on e.id=m.event_id
    where e.description=v_tag || '_TO_ALLOCATE_EXPLICIT' and m.envelope_id=v_to_allocate_id and m.amount=5 and m.direction='inflow')
  then raise exception 'Explicit À répartir opening should be allowed'; end if;

  -- 15-18: invalid, duplicate and cross-household envelope input rolls back completely.
  begin
    perform public.create_envelope_opening_event(v_household_id, now(), v_tag || '_DUP',
      jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',1),jsonb_build_object('envelope_id',v_food_id,'amount',1)), null,
      '90000000-0000-0000-0000-000000000005'::uuid);
    raise exception 'Duplicate envelope opening should fail';
  exception when others then if position('only once' in sqlerrm)=0 then raise; end if; end;
  begin
    perform public.create_envelope_opening_event(v_household_id, now(), v_tag || '_ZERO',
      jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',0)), null,
      '90000000-0000-0000-0000-000000000006'::uuid);
    raise exception 'Zero envelope opening should fail';
  exception when others then if position('positive amount' in sqlerrm)=0 then raise; end if; end;
  begin
    perform public.create_envelope_opening_event(v_household_id, now(), v_tag || '_OTHER_ENV',
      jsonb_build_array(jsonb_build_object('envelope_id',v_other_envelope_id,'amount',1)), null,
      '90000000-0000-0000-0000-000000000007'::uuid);
    raise exception 'Cross-household envelope opening should fail';
  exception when others then if position('active household envelope' in sqlerrm)=0 then raise; end if; end;
  if exists (select 1 from public.financial_events where description like v_tag || '_DUP%' or description like v_tag || '_ZERO%' or description like v_tag || '_OTHER_ENV%')
  then raise exception 'Rejected envelope opening persisted data'; end if;
end;
$$;

rollback;

select 25 as total, 25 as passed, 0 as failed, true as transactional_rollback_confirmed;
