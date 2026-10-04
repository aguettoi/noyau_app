-- Transactional Auth-final / household / invitation / RLS recipe.
begin;

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_member uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_household uuid;
  v_invitation uuid;
  v_count bigint;
begin
  insert into auth.users(
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) values
    ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated',
     'authenticated', 'auth-final-owner@example.test', '', now(), '{}',
     '{"display_name":"Owner fixture"}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_member, 'authenticated',
     'authenticated', 'auth-final-member@example.test', '', now(), '{}',
     '{"display_name":"Member fixture"}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_outsider, 'authenticated',
     'authenticated', 'auth-final-outsider@example.test', '', now(), '{}',
     '{"display_name":"Outsider fixture"}', now(), now());

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_household := public.create_household('Auth final fixture');

  if (select classification from public.households where id = v_household) <> 'operational' then
    raise exception 'Created household must be operational';
  end if;
  if not exists (
    select 1 from public.household_members
    where household_id = v_household and user_id = v_owner and role = 'owner'
  ) then raise exception 'Owner membership missing'; end if;

  select invitation_id into v_invitation
  from public.create_household_invitation(
    v_household, 'AUTH-FINAL-MEMBER@example.test'
  );

  -- Invitation alone is not membership and grants no financial authority.
  if public.is_household_member(v_household) is not true then
    raise exception 'Owner membership unexpectedly missing';
  end if;
  if exists (
    select 1 from public.household_members
    where household_id = v_household and user_id = v_member
  ) then raise exception 'Invitation granted membership prematurely'; end if;

  perform set_config('request.jwt.claim.sub', v_outsider::text, true);
  select count(*) into v_count from public.list_my_pending_household_invitations();
  if v_count <> 0 then raise exception 'Outsider saw another email invitation'; end if;
  begin
    perform public.accept_household_invitation(v_invitation);
    raise exception 'Outsider accepted invitation';
  exception when others then
    if sqlerrm = 'Outsider accepted invitation' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', v_member::text, true);
  select count(*) into v_count from public.list_my_pending_household_invitations();
  if v_count <> 1 then raise exception 'Invitee cannot see pending invitation'; end if;
  perform public.accept_household_invitation(v_invitation);
  if not exists (
    select 1 from public.household_members
    where household_id = v_household and user_id = v_member and role = 'member'
  ) then raise exception 'Accepted member membership missing'; end if;

  -- Canonical audit actors remain the authenticated user after invitation.
  insert into public.envelopes(household_id, name)
  values (v_household, 'Actor rollback fixture');
  if not exists (
    select 1 from public.audit_events
    where household_id = v_household
      and entity_type = 'envelopes'
      and action = 'insert'
      and actor_id = v_member
  ) then raise exception 'Invited member actor was not preserved'; end if;

  begin
    perform public.accept_household_invitation(v_invitation);
    raise exception 'Consumed invitation was replayed';
  exception when others then
    if sqlerrm = 'Consumed invitation was replayed' then raise; end if;
  end;

  -- Household onboarding remains non-financial.
  if (select count(*) from public.accounts where household_id = v_household) <> 0
     or (select count(*) from public.envelopes where household_id = v_household) <> 1
     or (select count(*) from public.financial_events where household_id = v_household) <> 0
     or (select count(*) from public.obligations where household_id = v_household) <> 0 then
    raise exception 'Auth onboarding created financial data';
  end if;

  -- A user cannot create a second operational household.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  begin
    perform public.create_household('Second operational household');
    raise exception 'Second operational household was allowed';
  exception when others then
    if sqlerrm = 'Second operational household was allowed' then raise; end if;
  end;
end;
$$;

rollback;
