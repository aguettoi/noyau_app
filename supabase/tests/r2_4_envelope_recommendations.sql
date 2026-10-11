begin;

insert into public.accounts(id,household_id,name,kind,ownership_type,archived_at)
values ('10000000-0000-4000-8000-000000000241','c87bbe8c-b349-4e90-88d6-a0b664488dc7','R2.4 inactif','bank','household',now());
insert into public.payment_methods(id,household_id,account_id,method_type,label,active,created_by)
values ('10000000-0000-4000-8000-000000000242','c87bbe8c-b349-4e90-88d6-a0b664488dc7','702d70dd-a62a-4446-b6ea-835b3d0a6615','bank_card','R2.4 carte',true,'2e06922c-dc19-4715-9f78-7152aaf3dfcc');

insert into public.budget_scenarios(id,household_id,name,active,valid_from,valid_to,created_by)
values ('10000000-0000-4000-8000-000000000243','c87bbe8c-b349-4e90-88d6-a0b664488dc7','R2.4 multi',true,'2035-01-01','2035-01-31','2e06922c-dc19-4715-9f78-7152aaf3dfcc');
insert into public.budget_scenario_versions(id,household_id,scenario_id,version,created_by)
values ('10000000-0000-4000-8000-000000000244','c87bbe8c-b349-4e90-88d6-a0b664488dc7','10000000-0000-4000-8000-000000000243',1,'2e06922c-dc19-4715-9f78-7152aaf3dfcc');
update public.budget_scenarios set current_version_id='10000000-0000-4000-8000-000000000244'
where id='10000000-0000-4000-8000-000000000243';
insert into public.budget_scenario_sources(id,household_id,scenario_version_id,source_type,name,expected_amount)
values ('10000000-0000-4000-8000-000000000245','c87bbe8c-b349-4e90-88d6-a0b664488dc7','10000000-0000-4000-8000-000000000244','common_capacity','R2.4 source',400);
insert into public.budget_scenario_steps(
  id,household_id,scenario_version_id,step_order,source_id,envelope_id,
  allocation_method,amount,contribution_key,funding_source_preference
) values
('10000000-0000-4000-8000-000000000246','c87bbe8c-b349-4e90-88d6-a0b664488dc7','10000000-0000-4000-8000-000000000244',1,'10000000-0000-4000-8000-000000000245','11ba989c-1017-4878-9c93-339284390ae4','fixed',100,'equal','702d70dd-a62a-4446-b6ea-835b3d0a6615'),
('10000000-0000-4000-8000-000000000247','c87bbe8c-b349-4e90-88d6-a0b664488dc7','10000000-0000-4000-8000-000000000244',2,'10000000-0000-4000-8000-000000000245','11ba989c-1017-4878-9c93-339284390ae4','fixed',300,'equal','ff375719-1c2c-4873-8abd-eb58b3760148');
insert into public.budget_periods(id,household_id,starts_on,ends_on,status,scenario_id,created_by)
values ('10000000-0000-4000-8000-000000000248','c87bbe8c-b349-4e90-88d6-a0b664488dc7','2035-01-01','2035-01-31','active','10000000-0000-4000-8000-000000000243','2e06922c-dc19-4715-9f78-7152aaf3dfcc');

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
set local role authenticated;

do $$
declare v_preview jsonb; v_count integer; v_total numeric; v_failed boolean;
begin
  perform public.set_envelope_recommendation(
    '823d0a24-22dd-4254-9b0a-5f9fe4f7fecf',
    '702d70dd-a62a-4446-b6ea-835b3d0a6615',
    '10000000-0000-4000-8000-000000000242'
  );
  perform public.set_envelope_recommendation(
    '823d0a24-22dd-4254-9b0a-5f9fe4f7fecf',
    'ff375719-1c2c-4873-8abd-eb58b3760148',null
  );
  select count(*) into v_count from public.envelope_recommendation_events
  where envelope_id='823d0a24-22dd-4254-9b0a-5f9fe4f7fecf'
    and actor_user_id='2e06922c-dc19-4715-9f78-7152aaf3dfcc';
  if v_count<>2 then raise exception 'Recommendation audit failed'; end if;

  v_failed:=false;
  begin
    perform public.set_envelope_recommendation(
      '823d0a24-22dd-4254-9b0a-5f9fe4f7fecf',
      '10000000-0000-4000-8000-000000000241',null
    );
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Inactive account accepted'; end if;

  v_preview:=public.monthly_close_automatic_target_preview(
    'c87bbe8c-b349-4e90-88d6-a0b664488dc7','2035-01-01'
  );
  select count(*),sum((value->>'target_amount')::numeric)
    into v_count,v_total from jsonb_array_elements(v_preview->'targets')
    where value->>'envelope_id'='11ba989c-1017-4878-9c93-339284390ae4';
  if v_count<>2 or v_total<>250 then raise exception 'Multi-account target failed: % / %',v_count,v_total; end if;

  perform set_config('request.jwt.claim.sub','8645c7b4-c9d8-4cf7-9090-6f404a418391',true);
  v_failed:=false;
  begin
    perform public.set_envelope_recommendation(
      '823d0a24-22dd-4254-9b0a-5f9fe4f7fecf',null,null
    );
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Cross-household recommendation accepted'; end if;
end $$;

rollback;
