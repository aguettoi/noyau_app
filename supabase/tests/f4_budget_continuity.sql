-- F4 authenticated/transactional matrix. Every fixture is rolled back.
begin;
do $$
declare
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); h uuid; h2 uuid;
  scenario uuid; source_period uuid; copied_period uuid; run uuid; run2 uuid; envelope uuid; shopping uuid; plan uuid; item uuid;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
   ('00000000-0000-0000-0000-000000000000',a,'authenticated','authenticated','f4-a@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',b,'authenticated','authenticated','f4-b@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f4-out@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification,budget_validation_mode) values('F4 rollback','technical','joint_required') returning id into h;
  insert into public.households(name,classification) values('F4 other rollback','technical') returning id into h2;
  insert into public.household_members(household_id,user_id,role) values(h,a,'owner'),(h,b,'member'),(h2,outsider,'owner');
  insert into public.envelopes(household_id,name) values(h,'F4 envelope') returning id into envelope;
  insert into public.budget_scenarios(household_id,name,active,priority,created_by) values(h,'October template',true,0,a) returning id into scenario;
  insert into public.budget_scenario_rules(household_id,scenario_id,envelope_id,allocation_method,amount,priority,rollover_policy,contribution_rule,active)
    values(h,scenario,envelope,'fixed',100,0,'report_total','custom',true);
  insert into public.budget_periods(household_id,starts_on,ends_on,status,scenario_id,created_by) values(h,'2026-10-01','2026-10-31','draft',scenario,a) returning id into source_period;
  insert into public.budget_allocation_runs(household_id,budget_period_id,scenario_id,status,available_resources,calculated_total,remaining_unallocated,summary,created_by)
    values(h,source_period,scenario,'simulated',100,100,0,'{}',a) returning id into run;
  insert into public.shopping_items(household_id,label,estimated_amount,status,created_by) values(h,'F4 project',100,'planned',a) returning id into shopping;
  insert into public.priority_plans(household_id,name,status,monthly_capacity,created_by) values(h,'F4 plan','active',100,a) returning id into plan;
  insert into public.priority_plan_items(household_id,plan_id,rank,shopping_item_id,created_by) values(h,plan,1,shopping,a) returning id into item;

  perform set_config('request.jwt.claim.role','authenticated',true); perform set_config('request.jwt.claim.sub',a::text,true); execute 'set local role authenticated';
  copied_period:=public.prepare_budget_period_v2(h,'2026-11-01','copy_previous',source_period);
  if public.prepare_budget_period_v2(h,'2026-11-01','copy_previous',source_period)<>copied_period then raise exception 'Month duplication is not idempotent'; end if;
  if (select copied_from_period_id from public.budget_periods where id=copied_period)<>source_period then raise exception 'Copy origin missing'; end if;
  if (select scenario_id from public.budget_periods where id=copied_period)=scenario then raise exception 'Copied month is not independent'; end if;
  if (select count(*) from public.financial_events where household_id=h)<>0 then raise exception 'Monthly copy created financial activity'; end if;

  perform public.approve_budget_allocation_run(h,run);
  if (select status from public.budget_allocation_runs where id=run)<>'simulated' then raise exception 'Joint approval applied too early'; end if;
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.approve_budget_allocation_run(h,run);
  if (select status from public.budget_allocation_runs where id=run)<>'approved' then raise exception 'Joint approval did not complete'; end if;
  execute 'reset role';
  insert into public.budget_allocation_runs(household_id,budget_period_id,scenario_id,status,available_resources,calculated_total,remaining_unallocated,summary,created_by)
    values(h,source_period,scenario,'simulated',100,100,0,'{"changed":true}',a) returning id into run2;
  perform set_config('request.jwt.claim.role','authenticated',true); perform set_config('request.jwt.claim.sub',b::text,true); execute 'set local role authenticated';
  perform public.approve_budget_allocation_run(h,run2);
  if (select status from public.budget_allocation_runs where id=run2)<>'simulated' then raise exception 'Approval from an older immutable run was reused'; end if;

  perform public.set_shopping_financing_plan(h,shopping,'projected_bonus',100,100,null,scenario,'Projection only');
  perform public.set_priority_item_decision(h,item,'wait',scenario,'No payment');
  if (select count(*) from public.financial_events where household_id=h)<>0 then raise exception 'Planning decision created financial activity'; end if;
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin perform public.set_priority_item_decision(h,item,'buy_now',null,null); raise exception 'Cross household accepted'; exception when others then if sqlerrm='Cross household accepted' then raise; end if; end;
end $$;
rollback;
