-- R2.13.1 authenticated shared draft, 1/2/N membership and isolation.
-- Every fixture is rolled back.
begin;

do $$
declare
  owner_id uuid:=gen_random_uuid(); member_id uuid:=gen_random_uuid(); member_n uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid();
  h_id uuid; other_h_id uuid; account_id uuid; other_account_id uuid; envelope_id uuid;
  denied boolean; draft jsonb;
  before_events bigint; before_transactions bigint; before_movements bigint;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
    ('00000000-0000-0000-0000-000000000000',owner_id,'authenticated','authenticated','r2131-owner@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',member_id,'authenticated','authenticated','r2131-member@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',member_n,'authenticated','authenticated','r2131-member-n@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',outsider_id,'authenticated','authenticated','r2131-outsider@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('R2.13.1 N rollback','technical') returning id into h_id;
  insert into public.households(name,classification) values('R2.13.1 other rollback','technical') returning id into other_h_id;
  insert into public.household_members(household_id,user_id,role) values
    (h_id,owner_id,'owner'),(h_id,member_id,'member'),(h_id,member_n,'member'),
    (other_h_id,outsider_id,'owner');
  insert into public.accounts(household_id,name,kind,ownership_type) values(h_id,'R2.13.1 account','bank','household') returning id into account_id;
  insert into public.accounts(household_id,name,kind,ownership_type) values(other_h_id,'R2.13.1 other account','bank','household') returning id into other_account_id;
  insert into public.envelopes(household_id,name) values(h_id,'R2.13.1 envelope') returning id into envelope_id;
  select count(*) into before_events from public.financial_events where household_id=h_id;
  select count(*) into before_transactions from public.financial_transactions where household_id=h_id;
  select count(*) into before_movements from public.envelope_movements where household_id=h_id;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',member_id::text,true);
  execute 'set local role authenticated';
  if public.save_envelope_account_initial_position_draft(h_id,jsonb_build_array(
    jsonb_build_object('account_id',account_id,'envelope_id',envelope_id,'amount',59330,
      'provenance','humanConfirmation','provenance_reference','Confirmation métier fixture')
  ))<>1 then raise exception 'Member draft was not saved'; end if;
  draft:=public.envelope_account_initial_position_draft(h_id);
  if jsonb_array_length(draft)<>1 or (draft->0->>'amount')::numeric<>59330
     or draft->0->>'provenance'<>'human_confirmation' then
    raise exception 'Member cannot reload the canonical draft';
  end if;
  if public.save_envelope_account_initial_position_draft(h_id,jsonb_build_array(
    jsonb_build_object('account_id',account_id,'envelope_id',envelope_id,'amount',59330,
      'provenance','humanConfirmation','provenance_reference','Confirmation métier fixture')
  ))<>1 or (select count(*) from public.envelope_account_initial_position_drafts where household_id=h_id)<>1 then
    raise exception 'Draft retry duplicated a position';
  end if;

  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  if jsonb_array_length(public.envelope_account_initial_position_draft(h_id))<>1 then
    raise exception 'Owner cannot read the shared member draft';
  end if;
  perform set_config('request.jwt.claim.sub',member_n::text,true);
  if jsonb_array_length(public.envelope_account_initial_position_draft(h_id))<>1 then
    raise exception 'N-member cannot read the shared draft';
  end if;

  perform set_config('request.jwt.claim.sub',outsider_id::text,true);
  denied:=false;
  begin perform public.envelope_account_initial_position_draft(h_id); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household draft read accepted'; end if;
  denied:=false;
  begin perform public.save_envelope_account_initial_position_draft(h_id,'[]'::jsonb); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household draft write accepted'; end if;

  perform set_config('request.jwt.claim.sub',member_id::text,true);
  denied:=false;
  begin perform public.save_envelope_account_initial_position_draft(h_id,jsonb_build_array(
    jsonb_build_object('account_id',other_account_id,'envelope_id',envelope_id,'amount',1,
      'provenance','openingInventoryArbitration','provenance_reference','invalid cross-household')
  )); exception when others then denied:=true; end;
  if not denied then raise exception 'Cross-household account accepted'; end if;

  execute 'reset role';
  if (select count(*) from public.financial_events where household_id=h_id)<>before_events
    or (select count(*) from public.financial_transactions where household_id=h_id)<>before_transactions
    or (select count(*) from public.envelope_movements where household_id=h_id)<>before_movements then
    raise exception 'Draft created a financial write';
  end if;
end $$;

rollback;
