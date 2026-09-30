begin;

select set_config('request.jwt.claim.sub','2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);

insert into public.households(id,name,classification)
values('c3a00000-0000-4000-8000-000000000001','C3A rollback fixture','technical');
insert into public.household_members(household_id,user_id,role)
values(
  'c3a00000-0000-4000-8000-000000000001',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',
  'owner'
);
insert into public.households(id,name,classification)
values('c3a00000-0000-4000-8000-000000000004','C3A negative rollback fixture','technical');
insert into public.household_members(household_id,user_id,role)
values(
  'c3a00000-0000-4000-8000-000000000004',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',
  'owner'
);

do $$
declare
  v_household uuid := 'c3a00000-0000-4000-8000-000000000001';
  v_negative_household uuid := 'c3a00000-0000-4000-8000-000000000004';
  v_run uuid := 'c3a00000-0000-4000-8000-000000000002';
  v_plan jsonb;
  v_negative_plan jsonb;
  v_result jsonb;
  v_events int;
  v_movements int;
  v_refs int;
begin
  v_plan := jsonb_build_object(
    'cutover_id',v_run,
    'household_id',v_household,
    'source_fingerprint',repeat('a',64),
    'effective_date','2026-10-01',
    'accounts',jsonb_build_array(jsonb_build_object(
      'name','C3A Cash','kind','cash','opening_amount',10,
      'ownership_type','household','holder_user_ids','[]'::jsonb,
      'conflict_decision','create')),
    'envelopes',jsonb_build_array(
      jsonb_build_object('name','Positive A','opening_amount',100,'is_to_allocate',false,'conflict_decision','create'),
      jsonb_build_object('name','Zero B','opening_amount',0,'is_to_allocate',false,'conflict_decision','create'),
      jsonb_build_object('name','À répartir','opening_amount',0,'is_to_allocate',true,'conflict_decision','create')
    ),
    'blocking_errors','[]'::jsonb,
    'warnings','[]'::jsonb
  );

  v_result := public.execute_cutover_opening_import(
    v_household,v_run,repeat('a',64),'2026-10-01',v_plan);
  if v_result->>'status' <> 'RECONCILED' then
    raise exception 'C3A fixture did not reconcile: %',v_result;
  end if;
  select count(*) into v_refs from public.envelopes where household_id=v_household;
  select count(*) into v_events from public.financial_events
    where household_id=v_household and event_type='envelope_opening';
  select count(*) into v_movements from public.envelope_movements where household_id=v_household;
  if v_refs<>3 or v_events<>1 or v_movements<>1 then
    raise exception 'Expected 3 references, 1 envelope event, 1 movement; got %, %, %',
      v_refs,v_events,v_movements;
  end if;
  if exists (select 1 from public.envelope_movements m join public.envelopes e on e.id=m.envelope_id
    where m.household_id=v_household and (e.name='Zero B' or e.system_code='to_allocate')) then
    raise exception 'Zero references must not create movements';
  end if;
  if exists (select 1 from public.accounts
    where household_id=v_household and name ilike '%opening_offset%') then
    raise exception 'Legacy opening_offset must not be used';
  end if;

  -- An identical replay is a pure read of the immutable run.
  perform public.execute_cutover_opening_import(
    v_household,v_run,repeat('a',64),'2026-10-01',v_plan);
  if (select count(*) from public.envelopes where household_id=v_household)<>3
     or (select count(*) from public.financial_events where household_id=v_household and event_type='envelope_opening')<>1
     or (select count(*) from public.envelope_movements where household_id=v_household)<>1 then
    raise exception 'Replay duplicated a zero or positive opening';
  end if;

  -- Same economic identity with incompatible parameters must fail explicitly.
  begin
    perform public.execute_cutover_opening_import(
      v_household,v_run,repeat('a',64),'2026-10-01',
      jsonb_set(v_plan,'{envelopes,1,opening_amount}','1'::jsonb));
    raise exception 'Expected immutable plan conflict';
  exception when others then
    if sqlerrm not like '%immutable different cutover plan%' then raise; end if;
  end;

  -- Negative openings remain forbidden and roll back atomically.
  v_negative_plan := jsonb_set(v_plan,'{cutover_id}',
    '"c3a00000-0000-4000-8000-000000000003"'::jsonb);
  v_negative_plan := jsonb_set(v_negative_plan,'{source_fingerprint}',
    to_jsonb(repeat('b',64)));
  v_negative_plan := jsonb_set(v_negative_plan,'{effective_date}',
    '"2026-10-02"'::jsonb);
  v_negative_plan := jsonb_set(v_negative_plan,'{household_id}',
    to_jsonb(v_negative_household::text));
  v_negative_plan := jsonb_set(v_negative_plan,'{envelopes,1,opening_amount}',
    '-1'::jsonb);
  begin
    perform public.execute_cutover_opening_import(
      v_negative_household,'c3a00000-0000-4000-8000-000000000003',repeat('b',64),'2026-10-02',
      v_negative_plan);
    raise exception 'Expected negative opening rejection';
  exception when others then
    if sqlerrm not like '%non-negative opening%' then raise; end if;
  end;
end;
$$;

rollback;
