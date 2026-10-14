-- R2.9 authenticated evidence, atomic snapshot and isolation checks.
-- Every fixture is rolled back.
begin;

do $$
declare
  owner_id uuid:=gen_random_uuid(); member_id uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid();
  h_id uuid; other_household_id uuid; account_a uuid; account_b uuid; envelope_a uuid; envelope_b uuid;
  replay_key uuid:=gen_random_uuid(); batch_id uuid; replay_id uuid; denied boolean;
  before_events bigint; before_transactions bigint; before_postings bigint; before_movements bigint; preview jsonb;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
    ('00000000-0000-0000-0000-000000000000',owner_id,'authenticated','authenticated','r29-owner@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',member_id,'authenticated','authenticated','r29-member@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',outsider_id,'authenticated','authenticated','r29-outsider@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('R2.9 rollback','technical') returning id into h_id;
  insert into public.households(name,classification) values('R2.9 other rollback','technical') returning id into other_household_id;
  insert into public.household_members(household_id,user_id,role) values
    (h_id,owner_id,'owner'),(h_id,member_id,'member'),(other_household_id,outsider_id,'owner');
  insert into public.accounts(household_id,name,kind,ownership_type) values(h_id,'R2.9 A','bank','household') returning id into account_a;
  insert into public.accounts(household_id,name,kind,ownership_type) values(h_id,'R2.9 B','cash','household') returning id into account_b;
  insert into public.envelopes(household_id,name) values(h_id,'R2.9 source') returning id into envelope_a;
  insert into public.envelopes(household_id,name) values(h_id,'R2.9 human') returning id into envelope_b;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  execute 'set local role authenticated';
  perform public.create_account_opening_event(h_id,now(),'R2.9 A',70,account_a,null,gen_random_uuid());
  perform public.create_account_opening_event(h_id,now(),'R2.9 B',30,account_b,null,gen_random_uuid());
  perform public.create_envelope_opening_event(h_id,now(),'R2.9 envelopes',jsonb_build_array(
    jsonb_build_object('envelope_id',envelope_a,'amount',70),
    jsonb_build_object('envelope_id',envelope_b,'amount',30)
  ),null,gen_random_uuid());
  perform public.record_account_balance_observation(account_a,now(),70,'R2.9 verified balance');
  perform public.record_account_balance_observation(account_b,now(),30,'R2.9 verified balance');
  execute 'reset role';
  insert into public.envelope_account_initial_evidence(household_id,account_id,envelope_id,amount,evidence_kind,source_fingerprint,source_reference,created_by)
  values(h_id,account_a,envelope_a,70,'source_proof','fixture','R2.9 fixture source',owner_id);
  select count(*) into before_events from public.financial_events where household_id=h_id;
  select count(*) into before_transactions from public.financial_transactions where household_id=h_id;
  select count(*) into before_postings from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id where t.household_id=h_id;
  select count(*) into before_movements from public.envelope_movements where household_id=h_id;

  perform set_config('request.jwt.claim.sub',member_id::text,true);
  execute 'set local role authenticated';
  preview:=public.envelope_account_initial_position_preview(h_id);
  if jsonb_array_length(preview->'positions')<>1 or preview->>'financial_writes'<>'0' then raise exception 'Member preview failed'; end if;
  denied:=false;
  begin perform public.set_envelope_account_position_snapshot(h_id,'[]','member',gen_random_uuid()); exception when others then denied:=true; end;
  if not denied then raise exception 'MEMBER initialised the matrix'; end if;

  perform set_config('request.jwt.claim.sub',outsider_id::text,true);
  denied:=false;
  begin perform public.envelope_account_initial_position_preview(h_id); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household preview accepted'; end if;

  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  denied:=false;
  begin perform public.set_envelope_account_position_snapshot(h_id,jsonb_build_array(
    jsonb_build_object('account_id',account_a,'envelope_id',envelope_a,'amount',70,'provenance','sourceProof','provenance_reference','invented'),
    jsonb_build_object('account_id',account_b,'envelope_id',envelope_b,'amount',30)
  ),'invalid evidence',gen_random_uuid()); exception when others then denied:=true; end;
  if not denied then raise exception 'Unverified evidence accepted'; end if;

  batch_id:=public.set_envelope_account_position_snapshot(h_id,jsonb_build_array(
    jsonb_build_object('account_id',account_a,'envelope_id',envelope_a,'amount',70,'provenance','sourceProof','provenance_reference','R2.9 fixture source'),
    jsonb_build_object('account_id',account_b,'envelope_id',envelope_b,'amount',30,'provenance','humanInput')
  ),'R2.9 balanced fixture',replay_key);
  replay_id:=public.set_envelope_account_position_snapshot(h_id,'[]','retry',replay_key);
  if replay_id<>batch_id then raise exception 'Idempotent retry did not return the original batch'; end if;
  denied:=false;
  begin perform public.set_envelope_account_position_snapshot(h_id,'[]','second initialisation',gen_random_uuid()); exception when others then denied:=true; end;
  if not denied then raise exception 'Second initialisation accepted'; end if;

  execute 'reset role';
  if (select count(*) from public.financial_events where household_id=h_id)<>before_events
    or (select count(*) from public.financial_transactions where household_id=h_id)<>before_transactions
    or (select count(*) from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id where t.household_id=h_id)<>before_postings
    or (select count(*) from public.envelope_movements where household_id=h_id)<>before_movements then
    raise exception 'Initial matrix created a financial write';
  end if;
end $$;

rollback;
