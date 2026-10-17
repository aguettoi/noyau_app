-- R2.14 authenticated deferred-position state and household isolation.
-- Every fixture is rolled back.
begin;

do $$
declare
  owner_id uuid:=gen_random_uuid(); member_id uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid();
  h_id uuid; other_h_id uuid; envelope_id uuid; other_envelope_id uuid;
  denied boolean; before_events bigint; before_transactions bigint; before_movements bigint;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
    ('00000000-0000-0000-0000-000000000000',owner_id,'authenticated','authenticated','r214-owner@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',member_id,'authenticated','authenticated','r214-member@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',outsider_id,'authenticated','authenticated','r214-outsider@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('R2.14 rollback','technical') returning id into h_id;
  insert into public.households(name,classification) values('R2.14 other rollback','technical') returning id into other_h_id;
  insert into public.household_members(household_id,user_id,role) values
    (h_id,owner_id,'owner'),(h_id,member_id,'member'),(other_h_id,outsider_id,'owner');
  insert into public.envelopes(household_id,name) values(h_id,'R2.14 envelope') returning id into envelope_id;
  insert into public.envelopes(household_id,name) values(other_h_id,'R2.14 other envelope') returning id into other_envelope_id;
  select count(*) into before_events from public.financial_events where household_id=h_id;
  select count(*) into before_transactions from public.financial_transactions where household_id=h_id;
  select count(*) into before_movements from public.envelope_movements where household_id=h_id;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',member_id::text,true);
  execute 'set local role authenticated';
  if public.save_envelope_account_initial_position_unknowns(h_id,jsonb_build_array(envelope_id))<>1 then
    raise exception 'Member could not defer the envelope';
  end if;
  if public.envelope_account_initial_position_unknowns(h_id)<>jsonb_build_array(envelope_id) then
    raise exception 'Deferred envelope was not shared';
  end if;
  if public.save_envelope_account_initial_position_unknowns(h_id,jsonb_build_array(envelope_id))<>1
     or (select count(*) from public.envelope_account_initial_position_unknowns where household_id=h_id)<>1 then
    raise exception 'Retry duplicated deferred state';
  end if;

  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  if jsonb_array_length(public.envelope_account_initial_position_unknowns(h_id))<>1 then
    raise exception 'Owner cannot read shared deferred state';
  end if;
  perform set_config('request.jwt.claim.sub',outsider_id::text,true);
  denied:=false;
  begin perform public.envelope_account_initial_position_unknowns(h_id); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household read accepted'; end if;
  denied:=false;
  begin perform public.save_envelope_account_initial_position_unknowns(h_id,jsonb_build_array(envelope_id)); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household write accepted'; end if;

  perform set_config('request.jwt.claim.sub',member_id::text,true);
  denied:=false;
  begin perform public.save_envelope_account_initial_position_unknowns(h_id,jsonb_build_array(other_envelope_id)); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household envelope accepted'; end if;

  execute 'reset role';
  if (select count(*) from public.financial_events where household_id=h_id)<>before_events
    or (select count(*) from public.financial_transactions where household_id=h_id)<>before_transactions
    or (select count(*) from public.envelope_movements where household_id=h_id)<>before_movements then
    raise exception 'Deferred state created a financial write';
  end if;
end $$;

rollback;
