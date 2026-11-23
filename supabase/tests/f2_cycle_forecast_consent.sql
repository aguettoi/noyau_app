begin;

do $$
declare
  v_definition text;
begin
  if not (select relrowsecurity from pg_class
    where oid = 'public.member_cycle_forecast_shares'::regclass) then
    raise exception 'F2 forecast consent must enforce RLS';
  end if;
  if has_table_privilege(
    'anon', 'public.member_cycle_forecast_shares', 'select'
  ) then
    raise exception 'anon must not read Cycle forecast consents';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.read_authorized_cycle_timeline_v2(uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.read_authorized_cycle_timeline_v2(uuid)',
    'execute'
  ) then
    raise exception 'F2 Cycle timeline RPC audience is invalid';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.read_authorized_cycle_timeline(uuid)',
    'execute'
  ) then
    raise exception 'legacy forecast projection must be retired';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'member_cycle_forecast_shares'
      and policyname = 'member_cycle_forecast_shares_owner_create'
      and with_check like '%auth.uid()%'
  ) then
    raise exception 'owner-only forecast consent create policy missing';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'member_cycle_forecast_shares'
      and policyname = 'member_cycle_forecast_shares_active_participants_read'
      and qual like '%is_household_member%'
  ) then
    raise exception 'forecast consent metadata is not restricted to active members';
  end if;
  select pg_get_functiondef(
    'public.read_authorized_cycle_timeline_v2(uuid)'::regprocedure
  ) into v_definition;
  if v_definition ~* '(symptoms|notes|flow|contraception|intimacy|libido|temperature|weight|member_cycle_private_entries)' then
    raise exception 'F2 projection exposes an intimate Cycle field';
  end if;
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'member_cycle_forecast_shares'
  ) then
    raise exception 'raw F2 consent rows must not be published';
  end if;
end $$;

do $$
declare
  owner_a uuid := gen_random_uuid();
  member_b uuid := gen_random_uuid();
  admin_c uuid := gen_random_uuid();
  outsider uuid := gen_random_uuid();
  household_a uuid;
  household_other uuid;
  visible_count integer;
begin
  insert into auth.users(
    instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) values
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','f2-cycle-owner@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',member_b,'authenticated','authenticated','f2-cycle-member@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',admin_c,'authenticated','authenticated','f2-cycle-admin@example.test','',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f2-cycle-outsider@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification)
    values ('F2 Cycle rollback','technical') returning id into household_a;
  insert into public.households(name,classification)
    values ('F2 Cycle other rollback','technical') returning id into household_other;
  insert into public.household_members(household_id,user_id,role) values
    (household_a,owner_a,'owner'),
    (household_a,member_b,'member'),
    (household_a,admin_c,'owner'),
    (household_other,outsider,'owner');
  insert into public.member_cycle_events(
    household_id,owner_user_id,starts_on,ends_on,phase,flow,symptoms,notes
  ) values
    (household_a,owner_a,date '2026-08-01',date '2026-08-05','period','medium',array['private-a'],'private-a'),
    (household_a,owner_a,date '2026-08-29',date '2026-09-02','period','heavy',array['private-b'],'private-b'),
    (household_a,owner_a,date '2026-09-26',date '2026-09-30','period','light',array['private-c'],'private-c');

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',member_b::text,true);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  insert into public.member_cycle_private_entries(
    household_id,owner_user_id,occurred_on,observed_at,category,
    payload,test_result
  ) values (
    household_a,owner_a,date '2026-10-01',timestamptz '2026-10-01 07:00:00+00',
    'lh_test','{}','positive'
  );
  insert into public.member_cycle_private_entries(
    household_id,owner_user_id,occurred_on,observed_at,category,
    payload,measurement_value,measurement_unit
  ) values (
    household_a,owner_a,date '2026-10-02',timestamptz '2026-10-02 06:45:00+00',
    'basal_temperature','{}',36.55,'celsius'
  );
  begin
    insert into public.member_cycle_private_entries(
      household_id,owner_user_id,occurred_on,category,payload,
      measurement_value,measurement_unit
    ) values (
      household_a,owner_a,date '2026-10-02','basal_temperature','{}',
      null,'celsius'
    );
    raise exception 'incomplete BBT measurement passed validation';
  exception when others then
    if sqlerrm = 'incomplete BBT measurement passed validation' then raise; end if;
  end;
  begin
    insert into public.member_cycle_private_entries(
      household_id,owner_user_id,occurred_on,category,payload,test_result
    ) values (
      household_a,owner_a,date '2026-10-02','symptom','{}','positive'
    );
    raise exception 'structured LH value leaked into another category';
  exception when others then
    if sqlerrm = 'structured LH value leaked into another category' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub',member_b::text,true);
  if exists (
    select 1 from public.member_cycle_private_entries
    where household_id = household_a and owner_user_id = owner_a
  ) then
    raise exception 'recipient read owner LH/BBT private journal';
  end if;
  begin
    insert into public.member_cycle_private_entries(
      household_id,owner_user_id,occurred_on,category,payload,test_result
    ) values (household_a,owner_a,date '2026-10-03','lh_test','{}','negative');
    raise exception 'recipient wrote owner LH/BBT private journal';
  exception when others then
    if sqlerrm = 'recipient wrote owner LH/BBT private journal' then raise; end if;
  end;

  select count(*) into visible_count
  from public.read_authorized_cycle_timeline_v2(household_a)
  where owner_user_id = owner_a;
  if visible_count <> 0 then
    raise exception 'unauthorized member received Cycle data';
  end if;

  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  insert into public.member_cycle_calendar_shares(
    household_id,owner_user_id,recipient_user_id
  ) values (household_a,owner_a,member_b);
  perform set_config('request.jwt.claim.sub',member_b::text,true);
  if not exists (
    select 1 from public.read_authorized_cycle_timeline_v2(household_a)
    where owner_user_id = owner_a and projection_kind = 'observation'
  ) or exists (
    select 1 from public.read_authorized_cycle_timeline_v2(household_a)
    where owner_user_id = owner_a and projection_kind = 'forecast'
  ) then
    raise exception 'dates consent leaked or failed to isolate forecasts';
  end if;

  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  insert into public.member_cycle_forecast_shares(
    household_id,owner_user_id,recipient_user_id
  ) values (household_a,owner_a,member_b);
  perform set_config('request.jwt.claim.sub',member_b::text,true);
  if not exists (
    select 1 from public.read_authorized_cycle_timeline_v2(household_a)
    where owner_user_id = owner_a and projection_kind = 'forecast'
  ) then
    raise exception 'explicit forecast consent was not projected';
  end if;

  perform set_config('request.jwt.claim.sub',admin_c::text,true);
  insert into public.member_cycle_events(
    household_id,owner_user_id,starts_on,phase
  ) values
    (household_a,admin_c,date '2026-01-01','period'),
    (household_a,admin_c,date '2026-01-19','period'),
    (household_a,admin_c,date '2026-03-15','period'),
    (household_a,admin_c,date '2026-04-04','period'),
    (household_a,admin_c,date '2026-06-03','period');
  insert into public.member_cycle_forecast_shares(
    household_id,owner_user_id,recipient_user_id
  ) values (household_a,admin_c,member_b);
  perform set_config('request.jwt.claim.sub',member_b::text,true);
  if exists (
    select 1 from public.read_authorized_cycle_timeline_v2(household_a)
    where owner_user_id = admin_c and projection_kind = 'forecast'
  ) then
    raise exception 'unstable Cycle history did not abstain';
  end if;

  perform set_config('request.jwt.claim.sub',admin_c::text,true);
  begin
    insert into public.member_cycle_forecast_shares(
      household_id,owner_user_id,recipient_user_id
    ) values (household_a,owner_a,admin_c);
    raise exception 'household admin bypassed Cycle owner consent';
  exception when others then
    if sqlerrm = 'household admin bypassed Cycle owner consent' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  delete from public.member_cycle_forecast_shares
  where household_id = household_a
    and owner_user_id = owner_a
    and recipient_user_id = member_b;
  perform set_config('request.jwt.claim.sub',member_b::text,true);
  if exists (
    select 1 from public.read_authorized_cycle_timeline_v2(household_a)
    where owner_user_id = owner_a and projection_kind = 'forecast'
  ) then
    raise exception 'revoked forecast remained visible';
  end if;

  perform set_config('request.jwt.claim.sub',outsider::text,true);
  if exists (
    select 1 from public.read_authorized_cycle_timeline_v2(household_a)
  ) then
    raise exception 'other household received Cycle projection';
  end if;
end $$;

select 'PASS: F2 independent forecast consent and minimized projection' as certification;
rollback;
