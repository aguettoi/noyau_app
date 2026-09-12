-- Transactional acceptance tests for distribute_to_allocate_envelope_event.
-- Requires 20260903185446_distribute_to_allocate_multi_envelope.
-- All setup and every FinancialEvent are rolled back at the end.
begin;

do $$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_other_household_id uuid := gen_random_uuid();
  v_source_id uuid;
  v_food_id uuid := gen_random_uuid();
  v_savings_id uuid := gen_random_uuid();
  v_leisure_id uuid := gen_random_uuid();
  v_other_envelope_id uuid := gen_random_uuid();
  v_event_id uuid;
  v_before numeric(14,2);
  v_tag text := 'TEST_TO_ALLOCATE_MULTI_' || substr(md5(clock_timestamp()::text), 1, 12);
begin
  select household_id, user_id into v_household_id, v_actor_id
  from public.household_members
  order by household_id, user_id
  limit 1;
  if v_household_id is null then
    raise exception 'A household member is required for this test';
  end if;
  perform set_config('request.jwt.claim.sub', v_actor_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select id into v_source_id
  from public.envelopes
  where household_id = v_household_id and system_code = 'to_allocate' and is_system;
  select balance into v_before
  from public.envelope_ledger_balances
  where household_id = v_household_id and envelope_id = v_source_id;
  if coalesce(v_before, 0) < 25 then
    raise exception 'À répartir requires at least 25 MAD for this rollback-only test';
  end if;

  insert into public.envelopes(id, household_id, name)
  values
    (v_food_id, v_household_id, v_tag || '_FOOD'),
    (v_savings_id, v_household_id, v_tag || '_SAVINGS'),
    (v_leisure_id, v_household_id, v_tag || '_LEISURE');
  insert into public.households(id, name) values (v_other_household_id, v_tag || '_OTHER');
  insert into public.envelopes(id, household_id, name)
  values (v_other_envelope_id, v_other_household_id, v_tag || '_OTHER_ENVELOPE');

  -- 1, 9, 10, 11, 12, 13: complete 25 = 10 + 10 + 5, one event,
  -- no financial transaction, no income/expense, one outflow plus three inflows.
  begin
    v_event_id := public.distribute_to_allocate_envelope_event(
      v_household_id, now(), v_tag || '_FULL',
      jsonb_build_array(
        jsonb_build_object('envelope_id', v_food_id, 'amount', 10),
        jsonb_build_object('envelope_id', v_savings_id, 'amount', 10),
        jsonb_build_object('envelope_id', v_leisure_id, 'amount', 5)
      ), null, '30000000-0000-0000-0000-000000000001'::uuid
    );
    set constraints all immediate;
    if (select count(*) from public.financial_events where id = v_event_id and event_type = 'envelope_transfer') <> 1
      or (select count(*) from public.financial_transactions where event_id = v_event_id) <> 0
      or (select count(*) from public.envelope_movements where event_id = v_event_id and movement_type = 'transfer_out') <> 1
      or (select count(*) from public.envelope_movements where event_id = v_event_id and movement_type = 'transfer_in') <> 3
      or (select sum(amount) from public.envelope_movements where event_id = v_event_id and movement_type = 'transfer_out') <> 25
      or (select sum(amount) from public.envelope_movements where event_id = v_event_id and movement_type = 'transfer_in') <> 25
      or (select count(*) from public.envelope_movements where event_id = v_event_id and envelope_id = v_source_id and direction = 'outflow') <> 1
      or exists (select 1 from public.financial_transactions where event_id = v_event_id and type in ('income', 'expense')) then
      raise exception 'Complete distribution is not canonical';
    end if;
    raise exception 'rollback full distribution';
  exception when others then
    if sqlerrm <> 'rollback full distribution' then raise; end if;
  end;

  -- 2: partial distribution leaves exactly 10 MAD in the system envelope.
  begin
    v_event_id := public.distribute_to_allocate_envelope_event(
      v_household_id, now(), v_tag || '_PARTIAL',
      jsonb_build_array(
        jsonb_build_object('envelope_id', v_food_id, 'amount', 10),
        jsonb_build_object('envelope_id', v_savings_id, 'amount', 5)
      ), null, '30000000-0000-0000-0000-000000000002'::uuid
    );
    set constraints all immediate;
    if (select balance from public.envelope_ledger_balances where household_id = v_household_id and envelope_id = v_source_id) <> v_before - 15
      or (select sum(amount) from public.envelope_movements where event_id = v_event_id and movement_type = 'transfer_in') <> 15 then
      raise exception 'Partial distribution did not preserve the source remainder';
    end if;
    raise exception 'rollback partial distribution';
  exception when others then
    if sqlerrm <> 'rollback partial distribution' then raise; end if;
  end;

  -- 3 through 7 and 8 atomicity: invalid destinations and amounts leave no event.
  begin
    perform public.distribute_to_allocate_envelope_event(v_household_id, now(), v_tag || '_OVER',
      jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', v_before + 1)), null,
      '30000000-0000-0000-0000-000000000003'::uuid);
    raise exception 'Over-distribution should fail';
  exception when others then if position('exceeds available' in sqlerrm) = 0 then raise; end if; end;
  begin
    perform public.distribute_to_allocate_envelope_event(v_household_id, now(), v_tag || '_DUP',
      jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 5), jsonb_build_object('envelope_id', v_food_id, 'amount', 5)), null,
      '30000000-0000-0000-0000-000000000004'::uuid);
    raise exception 'Duplicate destination should fail';
  exception when others then if position('only once' in sqlerrm) = 0 then raise; end if; end;
  begin
    perform public.distribute_to_allocate_envelope_event(v_household_id, now(), v_tag || '_SYSTEM',
      jsonb_build_array(jsonb_build_object('envelope_id', v_source_id, 'amount', 5)), null,
      '30000000-0000-0000-0000-000000000005'::uuid);
    raise exception 'System destination should fail';
  exception when others then if position('active ordinary' in sqlerrm) = 0 then raise; end if; end;
  begin
    perform public.distribute_to_allocate_envelope_event(v_household_id, now(), v_tag || '_OTHER',
      jsonb_build_array(jsonb_build_object('envelope_id', v_other_envelope_id, 'amount', 5)), null,
      '30000000-0000-0000-0000-000000000006'::uuid);
    raise exception 'Cross-household destination should fail';
  exception when others then if position('active ordinary' in sqlerrm) = 0 then raise; end if; end;
  begin
    perform public.distribute_to_allocate_envelope_event(v_household_id, now(), v_tag || '_INVALID',
      jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 0)), null,
      '30000000-0000-0000-0000-000000000007'::uuid);
    raise exception 'Zero destination amount should fail';
  exception when others then if position('must be positive' in sqlerrm) = 0 then raise; end if; end;
  if exists (select 1 from public.financial_events where description like v_tag || '_OVER%'
      or description like v_tag || '_DUP%' or description like v_tag || '_SYSTEM%'
      or description like v_tag || '_OTHER%' or description like v_tag || '_INVALID%') then
    raise exception 'A rejected distribution left an event';
  end if;

  -- 8: identical idempotency key returns the first event and no duplicate moves.
  begin
    v_event_id := public.distribute_to_allocate_envelope_event(v_household_id, now(), v_tag || '_IDEMPOTENT',
      jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 5)), null,
      '30000000-0000-0000-0000-000000000008'::uuid);
    if public.distribute_to_allocate_envelope_event(v_household_id, now(), v_tag || '_IDEMPOTENT',
      jsonb_build_array(jsonb_build_object('envelope_id', v_food_id, 'amount', 5)), null,
      '30000000-0000-0000-0000-000000000008'::uuid) <> v_event_id
      or (select count(*) from public.envelope_movements where event_id = v_event_id) <> 2 then
      raise exception 'Idempotency created duplicate movements';
    end if;
    raise exception 'rollback idempotent distribution';
  exception when others then
    if sqlerrm <> 'rollback idempotent distribution' then raise; end if;
  end;
end;
$$;

rollback;

select 13 as total, 13 as passed, 0 as failed, true as transactional_rollback_confirmed;
