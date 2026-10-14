-- R2.10 authenticated global netting. Every fixture is rolled back.
begin;

do $$
declare
  v_owner uuid:=gen_random_uuid(); v_outsider uuid:=gen_random_uuid();
  v_household uuid; v_other uuid; v_a uuid; v_b uuid; v_e1 uuid; v_e2 uuid;
  v_month date:=date '2026-10-01'; v_key uuid:=gen_random_uuid();
  v_snapshot jsonb; v_result jsonb; v_denied boolean;
  v_events bigint; v_transactions bigint; v_postings bigint; v_movements bigint;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
    ('00000000-0000-0000-0000-000000000000',v_owner,'authenticated','authenticated','r210-owner@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',v_outsider,'authenticated','authenticated','r210-outsider@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('R2.10 rollback','technical') returning id into v_household;
  insert into public.households(name,classification) values('R2.10 other rollback','technical') returning id into v_other;
  insert into public.household_members(household_id,user_id,role) values
    (v_household,v_owner,'owner'),(v_other,v_outsider,'owner');
  insert into public.accounts(household_id,name,kind,ownership_type) values
    (v_household,'R2.10 bank','bank','household') returning id into v_a;
  insert into public.accounts(household_id,name,kind,ownership_type) values
    (v_household,'R2.10 cash','cash','household') returning id into v_b;
  insert into public.envelopes(household_id,name) values(v_household,'R2.10 first') returning id into v_e1;
  insert into public.envelopes(household_id,name) values(v_household,'R2.10 second') returning id into v_e2;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  execute 'set local role authenticated';
  perform public.create_account_opening_event(v_household,now(),'R2.10 account A',100,v_a,null,gen_random_uuid());
  perform public.create_account_opening_event(v_household,now(),'R2.10 account B',100,v_b,null,gen_random_uuid());
  perform public.create_envelope_opening_event(v_household,now(),'R2.10 envelopes',jsonb_build_array(
    jsonb_build_object('envelope_id',v_e1,'amount',100),
    jsonb_build_object('envelope_id',v_e2,'amount',100)),null,gen_random_uuid());
  perform public.record_account_balance_observation(v_a,now(),100,'R2.10 verified');
  perform public.record_account_balance_observation(v_b,now(),100,'R2.10 verified');
  perform public.set_envelope_account_position_snapshot(v_household,jsonb_build_array(
    jsonb_build_object('account_id',v_a,'envelope_id',v_e1,'amount',100),
    jsonb_build_object('account_id',v_b,'envelope_id',v_e2,'amount',100)),
    'R2.10 initial matrix',gen_random_uuid());
  execute 'reset role';

  insert into public.monthly_envelope_account_targets(household_id,month_start,envelope_id,account_id,target_amount,created_by) values
    (v_household,v_month,v_e1,v_b,100,v_owner),
    (v_household,v_month,v_e2,v_a,60,v_owner),
    (v_household,v_month,v_e2,v_b,40,v_owner);
  select public.envelope_account_position_snapshot(v_household) into v_snapshot;
  select count(*) into v_events from public.financial_events where household_id=v_household;
  select count(*) into v_transactions from public.financial_transactions where household_id=v_household;
  select count(*) into v_postings from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id where t.household_id=v_household;
  select count(*) into v_movements from public.envelope_movements where household_id=v_household;

  execute 'set local role authenticated';
  v_result:=public.execute_monthly_account_reallocation_v2(v_household,v_month,v_snapshot->>'fingerprint',date '2026-10-31',
    jsonb_build_array(jsonb_build_object('from_account_id',v_a,'to_account_id',v_b,'amount',40)),
    jsonb_build_array(
      jsonb_build_object('from_account_id',v_a,'to_account_id',v_b,'envelope_id',v_e1,'amount',100),
      jsonb_build_object('from_account_id',v_b,'to_account_id',v_a,'envelope_id',v_e2,'amount',60)),v_key);
  if (v_result->>'replayed')::boolean then raise exception 'First execution replayed'; end if;
  execute 'reset role';

  if (select count(*) from public.financial_events where household_id=v_household)<>v_events+1
    or (select count(*) from public.financial_transactions where household_id=v_household)<>v_transactions+1
    or (select count(*) from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id where t.household_id=v_household)<>v_postings+2
    or (select count(*) from public.envelope_movements where household_id=v_household)<>v_movements then
    raise exception 'Canonical transfer financial invariants failed';
  end if;
  if (select count(*) from public.envelope_account_physical_transfers where household_id=v_household)<>1
    or (select count(*) from public.envelope_account_reallocation_justifications where household_id=v_household)<>2 then
    raise exception 'Physical/analytical audit mismatch';
  end if;
  if exists(select 1 from public.envelope_account_current_positions p full join public.monthly_envelope_account_targets t
    on t.household_id=p.household_id and t.account_id=p.account_id and t.envelope_id=p.envelope_id and t.month_start=v_month
    where coalesce(p.household_id,t.household_id)=v_household and coalesce(p.amount,0)<>coalesce(t.target_amount,0)) then
    raise exception 'Final matrix does not equal target';
  end if;

  execute 'set local role authenticated';
  v_result:=public.execute_monthly_account_reallocation_v2(v_household,v_month,'ignored on replay',date '2026-10-31','[]','[]',v_key);
  if not (v_result->>'replayed')::boolean then raise exception 'Idempotent replay failed'; end if;
  v_denied:=false;
  begin
    perform public.execute_monthly_account_reallocation_v2(v_household,v_month,'stale',date '2026-10-31','[]','[]',gen_random_uuid());
  exception when others then v_denied:=true; end;
  if not v_denied then raise exception 'Stale proposal accepted'; end if;
  perform set_config('request.jwt.claim.sub',v_outsider::text,true);
  v_denied:=false;
  begin
    perform public.execute_monthly_account_reallocation_v2(v_household,v_month,'x',date '2026-10-31','[]','[]',gen_random_uuid());
  exception when others then v_denied:=true; end;
  if not v_denied then raise exception 'Cross-household execution accepted'; end if;
  execute 'reset role';
end $$;

rollback;
