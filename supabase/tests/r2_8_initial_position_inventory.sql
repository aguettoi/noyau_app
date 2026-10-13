-- R2.8 initial account x envelope inventory. Every fixture is rolled back.
begin;

do $$
declare
  owner_one uuid:=gen_random_uuid(); owner_two uuid:=gen_random_uuid(); member_two uuid:=gen_random_uuid();
  owner_n uuid:=gen_random_uuid(); member_n1 uuid:=gen_random_uuid(); member_n2 uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  h_one uuid; h_two uuid; h_n uuid; h_other uuid;
  a1 uuid; a2 uuid; e1 uuid; e2 uuid; e0 uuid;
  key_one uuid:=gen_random_uuid(); batch_one uuid; batch_replay uuid;
  denied boolean; before_events bigint; before_transactions bigint; before_postings bigint; before_movements bigint;
  snapshot jsonb;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
   ('00000000-0000-0000-0000-000000000000',owner_one,'authenticated','authenticated','r28-one@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',owner_two,'authenticated','authenticated','r28-two@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',member_two,'authenticated','authenticated','r28-two-member@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',owner_n,'authenticated','authenticated','r28-n@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',member_n1,'authenticated','authenticated','r28-n1@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',member_n2,'authenticated','authenticated','r28-n2@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','r28-out@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('R2.8 one rollback','technical') returning id into h_one;
  insert into public.households(name,classification) values('R2.8 two rollback','technical') returning id into h_two;
  insert into public.households(name,classification) values('R2.8 N rollback','technical') returning id into h_n;
  insert into public.households(name,classification) values('R2.8 other rollback','technical') returning id into h_other;
  insert into public.household_members(household_id,user_id,role) values
    (h_one,owner_one,'owner'),
    (h_two,owner_two,'owner'),(h_two,member_two,'member'),
    (h_n,owner_n,'owner'),(h_n,member_n1,'member'),(h_n,member_n2,'member'),
    (h_other,outsider,'owner');
  if (select count(*) from public.household_members where household_id=h_one and inactive_at is null)<>1
    or (select count(*) from public.household_members where household_id=h_two and inactive_at is null)<>2
    or (select count(*) from public.household_members where household_id=h_n and inactive_at is null)<>3 then
    raise exception '1/2/N member fixtures are invalid';
  end if;

  insert into public.accounts(household_id,name,kind,ownership_type) values(h_n,'R2.8 bank A','bank','household') returning id into a1;
  insert into public.accounts(household_id,name,kind,ownership_type) values(h_n,'R2.8 cash B','cash','household') returning id into a2;
  insert into public.envelopes(household_id,name) values(h_n,'R2.8 mono') returning id into e1;
  insert into public.envelopes(household_id,name) values(h_n,'R2.8 multi') returning id into e2;
  insert into public.envelopes(household_id,name,is_system,system_code) values(h_n,'À répartir',true,'to_allocate') returning id into e0;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_n::text,true);
  execute 'set local role authenticated';
  perform public.create_account_opening_event(h_n,now(),'R2.8 account A',70,a1,null,gen_random_uuid());
  perform public.create_account_opening_event(h_n,now(),'R2.8 account B',30,a2,null,gen_random_uuid());
  perform public.create_envelope_opening_event(h_n,now(),'R2.8 envelopes',jsonb_build_array(
    jsonb_build_object('envelope_id',e1,'amount',60),jsonb_build_object('envelope_id',e2,'amount',40)
  ),null,gen_random_uuid());
  perform public.record_account_balance_observation(a1,now(),70,'R2.8 verified balance');
  perform public.record_account_balance_observation(a2,now(),30,'R2.8 verified balance');
  select count(*) into before_events from public.financial_events where household_id=h_n;
  select count(*) into before_transactions from public.financial_transactions where household_id=h_n;
  select count(*) into before_postings from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id where t.household_id=h_n;
  select count(*) into before_movements from public.envelope_movements where household_id=h_n;

  denied:=false;
  begin
    perform public.set_envelope_account_position_snapshot(h_n,jsonb_build_array(
      jsonb_build_object('account_id',a1,'envelope_id',e1,'amount',50),
      jsonb_build_object('account_id',a2,'envelope_id',e1,'amount',5),
      jsonb_build_object('account_id',a1,'envelope_id',e2,'amount',20),
      jsonb_build_object('account_id',a2,'envelope_id',e2,'amount',20)
    ),'Insufficient envelope',gen_random_uuid());
  exception when others then denied:=true; end;
  if not denied then raise exception 'Insufficient envelope total accepted'; end if;

  denied:=false;
  begin
    perform public.set_envelope_account_position_snapshot(h_n,jsonb_build_array(
      jsonb_build_object('account_id',a1,'envelope_id',e1,'amount',60),
      jsonb_build_object('account_id',a2,'envelope_id',e2,'amount',40)
    ),'Account over/under allocation',gen_random_uuid());
  exception when others then denied:=true; end;
  if not denied then raise exception 'Account imbalance accepted'; end if;

  batch_one:=public.set_envelope_account_position_snapshot(h_n,jsonb_build_array(
    jsonb_build_object('account_id',a1,'envelope_id',e1,'amount',50),
    jsonb_build_object('account_id',a2,'envelope_id',e1,'amount',10),
    jsonb_build_object('account_id',a1,'envelope_id',e2,'amount',20),
    jsonb_build_object('account_id',a2,'envelope_id',e2,'amount',20)
  ),'Balanced explicit inventory',key_one);
  batch_replay:=public.set_envelope_account_position_snapshot(h_n,'[]'::jsonb,'Ignored replay payload',key_one);
  if batch_replay<>batch_one or (select count(*) from public.envelope_account_position_batches where household_id=h_n)<>1 then
    raise exception 'Idempotent retry duplicated the inventory';
  end if;
  snapshot:=public.envelope_account_position_snapshot(h_n);
  if not (snapshot->>'reliable')::boolean or (snapshot->>'account_gap')::numeric<>0 or (snapshot->>'envelope_gap')::numeric<>0 then
    raise exception 'Balanced matrix is not reliable';
  end if;
  if exists(select 1 from public.envelope_account_current_positions where household_id=h_n and envelope_id=e0) then
    raise exception 'Zero system envelope created a useless position';
  end if;

  perform set_config('request.jwt.claim.sub',member_n1::text,true);
  if not (public.envelope_account_position_snapshot(h_n)->>'reliable')::boolean then raise exception 'Member cannot read own matrix'; end if;
  denied:=false;
  begin perform public.set_envelope_account_position_snapshot(h_n,'[]'::jsonb,'Member write',gen_random_uuid()); exception when others then denied:=true; end;
  if not denied then raise exception 'MEMBER initialized a matrix'; end if;

  perform set_config('request.jwt.claim.sub',outsider::text,true);
  denied:=false;
  begin perform public.envelope_account_position_snapshot(h_n); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household read accepted'; end if;
  denied:=false;
  begin perform public.set_envelope_account_position_snapshot(h_n,'[]'::jsonb,'Cross household',gen_random_uuid()); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household write accepted'; end if;

  execute 'reset role';
  if (select count(*) from public.financial_events where household_id=h_n)<>before_events
    or (select count(*) from public.financial_transactions where household_id=h_n)<>before_transactions
    or (select count(*) from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id where t.household_id=h_n)<>before_postings
    or (select count(*) from public.envelope_movements where household_id=h_n)<>before_movements then
    raise exception 'Inventory created a financial mutation';
  end if;
end $$;

rollback;
