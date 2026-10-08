-- F5A authenticated RLS and invariants matrix. Every fixture is rolled back.
begin;
do $$
declare
  member_a uuid:=gen_random_uuid(); member_b uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  household_a uuid; household_b uuid; asset_a uuid; investment_a uuid; event_a uuid; transaction_a uuid; obligation_a uuid;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
   ('00000000-0000-0000-0000-000000000000',member_a,'authenticated','authenticated','f5a-a@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',member_b,'authenticated','authenticated','f5a-b@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f5a-out@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('F5A rollback A','technical') returning id into household_a;
  insert into public.households(name,classification) values('F5A rollback B','technical') returning id into household_b;
  insert into public.household_members(household_id,user_id,role) values(household_a,member_a,'owner'),(household_a,member_b,'member'),(household_b,outsider,'owner');
  insert into public.financial_events(household_id,event_type,description,occurred_at,created_by) values(household_a,'cash_expense','F5A source',now(),member_a) returning id into event_a;
  insert into public.financial_transactions(household_id,type,occurred_at,reason,created_by,description,amount,validated_at,event_id)
    values(household_a,'expense',now(),'F5A source',member_a,'F5A source',100,now(),event_a) returning id into transaction_a;
  insert into public.obligations(household_id,obligation_kind,origin_event_id,origin_transaction_id,initial_amount,description,created_by)
    values(household_a,'debt',event_a,transaction_a,1000,'F5A debt',member_a) returning id into obligation_a;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',member_a::text,true);
  execute 'set local role authenticated';
  insert into public.wealth_assets(household_id,asset_type,label,ownership_type,acquisition_value,created_by,updated_by)
    values(household_a,'other','F5A asset','shared',5000,member_a,member_a) returning id into asset_a;
  insert into public.wealth_asset_owners(household_id,asset_id,user_id,ownership_share) values(household_a,asset_a,member_a,.5),(household_a,asset_a,member_b,.5);
  insert into public.wealth_asset_valuations(household_id,asset_id,estimated_value,valued_on,created_by) values(household_a,asset_a,5500,current_date,member_a);
  insert into public.investment_products(household_id,label,product_type,created_by) values(household_a,'F5A investment','fund',member_a) returning id into investment_a;
  insert into public.investment_valuations(household_id,investment_id,estimated_value,valued_on,created_by) values(household_a,investment_a,100,current_date,member_a);
  insert into public.investment_operations(household_id,investment_id,operation_type,gross_amount,tax_amount,occurred_on,financial_event_id,idempotency_key,created_by)
    values(household_a,investment_a,'contribution',100,0,current_date,event_a,gen_random_uuid(),member_a);
  insert into public.financing_profiles(household_id,label,structure_type,obligation_id,asset_id,principal_initial,start_date,duration_months,created_by)
    values(household_a,'F5A financing','fixed_cost',obligation_a,asset_a,1000,current_date,12,member_a);
  if (select current_estimated_value from public.wealth_asset_current_values where id=asset_a)<>5500 then raise exception 'Latest valuation unavailable'; end if;
  if (select remaining_amount from public.financing_overview where obligation_id=obligation_a)<>1000 then raise exception 'Liability not derived from obligation'; end if;

  perform set_config('request.jwt.claim.sub',member_b::text,true);
  if (select count(*) from public.wealth_assets where household_id=household_a)<>1 then raise exception 'Household member cannot read'; end if;
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  if (select count(*) from public.wealth_assets where household_id=household_a)<>0 then raise exception 'Cross-household read allowed'; end if;
  begin
    insert into public.wealth_asset_valuations(household_id,asset_id,estimated_value,valued_on,created_by) values(household_a,asset_a,1,current_date,outsider);
    raise exception 'Cross-household write allowed';
  exception when others then if sqlerrm='Cross-household write allowed' then raise; end if; end;
  execute 'reset role';

  begin update public.wealth_asset_valuations set estimated_value=1 where asset_id=asset_a; raise exception 'Valuation rewrite allowed';
  exception when others then if sqlerrm='Valuation rewrite allowed' then raise; end if; end;
  begin
    insert into public.financing_profiles(household_id,label,structure_type,obligation_id,principal_initial,start_date,duration_months,created_by)
      values(household_b,'Cross link','fixed_cost',obligation_a,1000,current_date,12,outsider);
    raise exception 'Cross-household obligation link allowed';
  exception when others then if sqlerrm='Cross-household obligation link allowed' then raise; end if; end;
  begin
    insert into public.investment_operations(household_id,investment_id,operation_type,gross_amount,occurred_on,financial_event_id,idempotency_key,created_by)
      select household_id,investment_id,'withdrawal',10,current_date,financial_event_id,idempotency_key,created_by from public.investment_operations where investment_id=investment_a;
    raise exception 'Duplicate operation accepted';
  exception when unique_violation then null; end;
  if (select count(*) from public.financial_events where household_id=household_a)<>1 then raise exception 'F5A created a financial event'; end if;
end $$;
rollback;
