begin;
do $$
declare
  user_a uuid:=gen_random_uuid(); user_b uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  household_a uuid; household_b uuid; home_asset uuid; vehicle_asset uuid; event_a uuid; tx_a uuid;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
   ('00000000-0000-0000-0000-000000000000',user_a,'authenticated','authenticated','f5b-a@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',user_b,'authenticated','authenticated','f5b-b@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f5b-out@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('F5B rollback A','technical') returning id into household_a;
  insert into public.households(name,classification) values('F5B rollback B','technical') returning id into household_b;
  insert into public.household_members(household_id,user_id,role) values(household_a,user_a,'owner'),(household_a,user_b,'member'),(household_b,outsider,'owner');
  insert into public.wealth_assets(household_id,asset_type,label,ownership_type,acquisition_value,created_by,updated_by) values
    (household_a,'real_estate','F5B home','shared',500000,user_a,user_a) returning id into home_asset;
  insert into public.wealth_assets(household_id,asset_type,label,ownership_type,acquisition_value,created_by,updated_by) values
    (household_a,'vehicle','F5B car','individual',100000,user_a,user_a) returning id into vehicle_asset;
  insert into public.financial_events(household_id,event_type,description,occurred_at,created_by) values(household_a,'cash_expense','F5B linked source',now(),user_a) returning id into event_a;
  insert into public.financial_transactions(household_id,type,occurred_at,reason,created_by,description,amount,validated_at,event_id)
    values(household_a,'expense',now(),'F5B linked source',user_a,'F5B linked source',100,now(),event_a) returning id into tx_a;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',user_a::text,true);
  execute 'set local role authenticated';
  insert into public.home_profiles(asset_id,household_id,property_type,created_by) values(home_asset,household_a,'primary_residence',user_a);
  insert into public.home_benefits(household_id,asset_id,benefit_type,recognition,amount,created_by) values(household_a,home_asset,'tax_saving','projected',500,user_a);
  insert into public.home_benefits(household_id,asset_id,benefit_type,recognition,amount,financial_event_id,created_by) values(household_a,home_asset,'acquisition_aid','cash_received',100,event_a,user_a);
  insert into public.vehicle_profiles(asset_id,household_id,make,model,model_year,created_by) values(vehicle_asset,household_a,'Test','Car',2026,user_a);
  insert into public.vehicle_mileage_readings(household_id,asset_id,reading_date,odometer_km,created_by) values(household_a,vehicle_asset,current_date,1000,user_a);
  insert into public.vehicle_cost_plans(household_id,asset_id,category,label,expected_amount,due_date,created_by) values(household_a,vehicle_asset,'insurance','Assurance',1000,current_date+30,user_a);
  insert into public.asset_expense_links(household_id,asset_id,financial_event_id,analytic_category,created_by) values(household_a,vehicle_asset,event_a,'fuel',user_a);
  if (select event_amount from public.asset_expense_overview where asset_id=vehicle_asset)<>100 then raise exception 'Actual expense is not derived'; end if;
  if (select count(*) from public.financial_events where household_id=household_a)<>1 then raise exception 'Projection created FinancialEvent'; end if;

  perform set_config('request.jwt.claim.sub',outsider::text,true);
  if (select count(*) from public.home_profiles where household_id=household_a)<>0 then raise exception 'Cross household read allowed'; end if;
  begin insert into public.vehicle_cost_plans(household_id,asset_id,category,label,expected_amount,due_date,created_by) values(household_a,vehicle_asset,'other','Cross',1,current_date,outsider); raise exception 'Cross write allowed';
  exception when others then if sqlerrm='Cross write allowed' then raise; end if; end;
  execute 'reset role';

  begin update public.vehicle_mileage_readings set odometer_km=2 where asset_id=vehicle_asset; raise exception 'Mileage rewrite allowed';
  exception when others then if sqlerrm='Mileage rewrite allowed' then raise; end if; end;
  begin insert into public.home_benefits(household_id,asset_id,benefit_type,recognition,amount,created_by) values(household_a,home_asset,'tax_saving','cash_received',1,user_a); raise exception 'Real benefit without event allowed';
  exception when check_violation then null; end;
end $$;
rollback;
