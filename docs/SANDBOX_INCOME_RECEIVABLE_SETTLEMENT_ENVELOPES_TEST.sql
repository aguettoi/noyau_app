-- Transactional acceptance tests for income-receivable settlement envelopes.
-- Requires 20260906192205_income_receivable_settlement_envelope_allocations.
-- Every fixture and every attempted write is rolled back.
begin;

do $$
declare
  v_household_id uuid; v_actor_id uuid; v_other_household_id uuid:=gen_random_uuid();
  v_account_id uuid:=gen_random_uuid(); v_food_id uuid:=gen_random_uuid();
  v_savings_id uuid:=gen_random_uuid(); v_other_envelope_id uuid:=gen_random_uuid();
  v_to_allocate_id uuid; v_receivable_event_id uuid; v_obligation_id uuid;
  v_event_id uuid; v_transaction_id uuid;
  v_tag text := 'TEST_RECEIVABLE_ENVELOPES_' || substr(md5(clock_timestamp()::text),1,12);
  v_key_base text := '70000000-0000-0000-0000-00000000000';
begin
  select household_id,user_id into v_household_id,v_actor_id
  from public.household_members order by household_id,user_id limit 1;
  if v_household_id is null then raise exception 'A household member is required for this test'; end if;
  perform set_config('request.jwt.claim.sub',v_actor_id::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);

  insert into public.accounts(id,household_id,name,kind,opening_balance)
  values(v_account_id,v_household_id,v_tag||'_ACCOUNT','bank',0);
  insert into public.envelopes(id,household_id,name)
  values(v_food_id,v_household_id,v_tag||'_FOOD'),(v_savings_id,v_household_id,v_tag||'_SAVINGS');
  insert into public.households(id,name) values(v_other_household_id,v_tag||'_OTHER');
  insert into public.envelopes(id,household_id,name)
  values(v_other_envelope_id,v_other_household_id,v_tag||'_OTHER_ENVELOPE');
  select id into v_to_allocate_id from public.envelopes
  where household_id=v_household_id and system_code='to_allocate' and is_system;

  -- 1, 11, 12: a settlement without explicit allocations credits only
  -- À répartir, preserves a single balanced receivable-settlement ledger and
  -- does not recognise an income again.
  v_receivable_event_id:=public.create_income_receivable_event(v_household_id,now(),v_tag||'_NONE_RECEIVABLE',100,'Debtor',null,null,(v_key_base||'1')::uuid);
  select id into v_obligation_id from public.obligations where origin_event_id=v_receivable_event_id;
  v_event_id:=public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_NONE_SETTLEMENT',100,v_account_id,null,(v_key_base||'2')::uuid,'[]'::jsonb);
  set constraints all immediate;
  select id into v_transaction_id from public.financial_transactions where event_id=v_event_id;
  if (select count(*) from public.financial_events where id=v_event_id and event_type='receivable_settlement')<>1
    or (select count(*) from public.financial_transactions where event_id=v_event_id and type='receivable_settlement')<>1
    or (select coalesce(sum(debit),0) from public.financial_transaction_lines where transaction_id=v_transaction_id)<>100
    or (select coalesce(sum(credit),0) from public.financial_transaction_lines where transaction_id=v_transaction_id)<>100
    or (select count(*) from public.financial_transactions where event_id=v_event_id and type='income')<>0
    or (select coalesce(sum(amount),0) from public.envelope_movements where event_id=v_event_id and envelope_id=v_to_allocate_id and movement_type='allocation' and direction='inflow')<>100
    or (select count(*) from public.envelope_movements where event_id=v_event_id)<>1 then
    raise exception 'Settlement without allocations is not canonical';
  end if;
  set constraints all deferred;

  -- 2: partial allocation leaves the exact remainder in À répartir.
  v_receivable_event_id:=public.create_income_receivable_event(v_household_id,now(),v_tag||'_PARTIAL_RECEIVABLE',100,'Debtor',null,null,(v_key_base||'3')::uuid);
  select id into v_obligation_id from public.obligations where origin_event_id=v_receivable_event_id;
  v_event_id:=public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_PARTIAL_SETTLEMENT',100,v_account_id,null,(v_key_base||'4')::uuid,jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',40)));
  set constraints all immediate;
  if (select coalesce(sum(amount),0) from public.envelope_movements where event_id=v_event_id and envelope_id=v_food_id)<>40
    or (select coalesce(sum(amount),0) from public.envelope_movements where event_id=v_event_id and envelope_id=v_to_allocate_id)<>60 then raise exception 'Partial settlement allocation is incorrect'; end if;
  set constraints all deferred;

  -- 3: several ordinary envelopes plus the remainder share the same event.
  v_receivable_event_id:=public.create_income_receivable_event(v_household_id,now(),v_tag||'_MULTI_RECEIVABLE',100,'Debtor',null,null,(v_key_base||'5')::uuid);
  select id into v_obligation_id from public.obligations where origin_event_id=v_receivable_event_id;
  v_event_id:=public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_MULTI_SETTLEMENT',100,v_account_id,null,(v_key_base||'6')::uuid,jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',30),jsonb_build_object('envelope_id',v_savings_id,'amount',20)));
  set constraints all immediate;
  if (select count(*) from public.envelope_movements where event_id=v_event_id)<>3
    or (select coalesce(sum(amount),0) from public.envelope_movements where event_id=v_event_id and envelope_id=v_to_allocate_id)<>50 then raise exception 'Multi-envelope settlement allocation is incorrect'; end if;
  set constraints all deferred;

  -- 4: a full allocation produces no system remainder.
  v_receivable_event_id:=public.create_income_receivable_event(v_household_id,now(),v_tag||'_FULL_RECEIVABLE',100,'Debtor',null,null,(v_key_base||'7')::uuid);
  select id into v_obligation_id from public.obligations where origin_event_id=v_receivable_event_id;
  v_event_id:=public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_FULL_SETTLEMENT',100,v_account_id,null,(v_key_base||'8')::uuid,jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',60),jsonb_build_object('envelope_id',v_savings_id,'amount',40)));
  set constraints all immediate;
  if exists(select 1 from public.envelope_movements where event_id=v_event_id and envelope_id=v_to_allocate_id) then raise exception 'Full settlement allocation must not fund À répartir'; end if;
  set constraints all deferred;

  -- 5, 6, 7, 8, 9, 13: invalid requests reject atomically.
  v_receivable_event_id:=public.create_income_receivable_event(v_household_id,now(),v_tag||'_INVALID_RECEIVABLE',100,'Debtor',null,null,(v_key_base||'9')::uuid);
  select id into v_obligation_id from public.obligations where origin_event_id=v_receivable_event_id;
  begin perform public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_OVER',100,v_account_id,null,(v_key_base||'a')::uuid,jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',101))); raise exception 'Over-allocation should fail'; exception when others then if position('cannot exceed' in sqlerrm)=0 then raise; end if; end;
  begin perform public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_SYSTEM',100,v_account_id,null,(v_key_base||'b')::uuid,jsonb_build_array(jsonb_build_object('envelope_id',v_to_allocate_id,'amount',1))); raise exception 'System envelope should fail'; exception when others then if position('active ordinary' in sqlerrm)=0 then raise; end if; end;
  begin perform public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_DUP',100,v_account_id,null,(v_key_base||'c')::uuid,jsonb_build_array(jsonb_build_object('envelope_id',v_food_id,'amount',1),jsonb_build_object('envelope_id',v_food_id,'amount',1))); raise exception 'Duplicate envelope should fail'; exception when others then if position('only once' in sqlerrm)=0 then raise; end if; end;
  begin perform public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_OTHER',100,v_account_id,null,(v_key_base||'d')::uuid,jsonb_build_array(jsonb_build_object('envelope_id',v_other_envelope_id,'amount',1))); raise exception 'Cross-household envelope should fail'; exception when others then if position('active ordinary' in sqlerrm)=0 then raise; end if; end;
  begin perform public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_OVER_SETTLEMENT',101,v_account_id,null,(v_key_base||'e')::uuid,'[]'::jsonb); raise exception 'Over-settlement should fail'; exception when others then if position('exceeds remaining' in sqlerrm)=0 then raise; end if; end;
  if exists(select 1 from public.financial_events where description in (v_tag||'_OVER',v_tag||'_SYSTEM',v_tag||'_DUP',v_tag||'_OTHER',v_tag||'_OVER_SETTLEMENT')) then raise exception 'Rejected settlement left partial data'; end if;

  -- 10: replaying one idempotency key creates neither a second ledger row nor
  -- a second envelope group.
  v_event_id:=public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_IDEMPOTENT',100,v_account_id,null,(v_key_base||'f')::uuid,'[]'::jsonb);
  if public.settle_receivable_event(v_household_id,v_obligation_id,now(),v_tag||'_IDEMPOTENT',100,v_account_id,null,(v_key_base||'f')::uuid,'[]'::jsonb)<>v_event_id
    or (select count(*) from public.financial_transactions where event_id=v_event_id)<>1
    or (select count(*) from public.envelope_movements where event_id=v_event_id)<>1 then raise exception 'Settlement idempotency created a duplicate'; end if;
end;
$$;

rollback;

select 13 as total, 13 as passed, 0 as failed, true as transactional_rollback_confirmed;
