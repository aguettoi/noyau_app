-- F1: profile, household settings and safe membership administration.
-- No financial tables, events, postings or envelope ledgers are touched.

alter table public.households
  add column if not exists budget_validation_mode text not null default 'authorized_member'
  check (budget_validation_mode in ('authorized_member', 'joint_required'));

create or replace function public.update_my_profile(p_display_name text)
returns public.profiles
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_profile public.profiles;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(trim(p_display_name), '') is null
     or char_length(trim(p_display_name)) > 80 then
    raise exception 'Display name must contain between 1 and 80 characters';
  end if;
  update public.profiles
  set display_name = trim(p_display_name)
  where id = auth.uid()
  returning * into v_profile;
  if not found then raise exception 'Profile not found'; end if;
  return v_profile;
end;
$$;

create or replace function public.update_household_settings(
  p_household_id uuid,
  p_name text,
  p_budget_validation_mode text
)
returns public.households
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_household public.households;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_budget_validation_mode not in ('authorized_member', 'joint_required') then
    raise exception 'Invalid budget validation mode';
  end if;
  if nullif(trim(p_name), '') is null or char_length(trim(p_name)) > 80 then
    raise exception 'Household name must contain between 1 and 80 characters';
  end if;
  update public.households h
  set name = trim(p_name), budget_validation_mode = p_budget_validation_mode
  where h.id = p_household_id
    and exists (
      select 1 from public.household_members hm
      where hm.household_id = h.id and hm.user_id = auth.uid() and hm.role = 'owner'
    )
  returning h.* into v_household;
  if not found then raise exception 'Only an owner may update this household'; end if;
  return v_household;
end;
$$;

create or replace function public.list_household_invitations(p_household_id uuid)
returns table (invitation_id uuid, invited_email text, proposed_role text, status text, expires_at timestamptz)
language sql stable security definer set search_path = public, auth
as $$
  select i.id, i.invited_email, i.proposed_role,
         case when i.status = 'pending' and i.expires_at <= now() then 'expired' else i.status end,
         i.expires_at
  from public.household_invitations i
  where i.household_id = p_household_id
    and exists (
      select 1 from public.household_members hm
      where hm.household_id = p_household_id and hm.user_id = auth.uid() and hm.role = 'owner'
    )
  order by i.created_at asc;
$$;

create or replace function public.revoke_household_invitation(p_invitation_id uuid)
returns void language plpgsql security definer set search_path = public, auth
as $$
begin
  update public.household_invitations i
  set status = 'revoked'
  where i.id = p_invitation_id
    and i.status = 'pending'
    and exists (
      select 1 from public.household_members hm
      where hm.household_id = i.household_id and hm.user_id = auth.uid() and hm.role = 'owner'
    );
  if not found then raise exception 'Invitation cannot be revoked'; end if;
end;
$$;

create or replace function public.change_household_member_role(
  p_household_id uuid, p_user_id uuid, p_role text
)
returns void language plpgsql security definer set search_path = public, auth
as $$
declare v_owner_count integer;
begin
  if p_role not in ('owner', 'member') then raise exception 'Invalid role'; end if;
  if not exists (
    select 1 from public.household_members
    where household_id = p_household_id and user_id = auth.uid() and role = 'owner'
  ) then raise exception 'Only an owner may change roles'; end if;
  if p_role = 'member' then
    select count(*) into v_owner_count from public.household_members
    where household_id = p_household_id and role = 'owner';
    if v_owner_count <= 1 and exists (
      select 1 from public.household_members
      where household_id = p_household_id and user_id = p_user_id and role = 'owner'
    ) then raise exception 'The last owner cannot be demoted'; end if;
  end if;
  update public.household_members set role = p_role
  where household_id = p_household_id and user_id = p_user_id;
  if not found then raise exception 'Member not found'; end if;
end;
$$;

create or replace function public.leave_household(p_household_id uuid)
returns void language plpgsql security definer set search_path = public, auth
as $$
declare v_owner_count integer;
begin
  if not exists (select 1 from public.household_members where household_id = p_household_id and user_id = auth.uid()) then
    raise exception 'Membership not found';
  end if;
  select count(*) into v_owner_count from public.household_members where household_id = p_household_id and role = 'owner';
  if v_owner_count = 1 and exists (
    select 1 from public.household_members where household_id = p_household_id and user_id = auth.uid() and role = 'owner'
  ) then raise exception 'The last owner cannot leave the household'; end if;
  delete from public.household_members where household_id = p_household_id and user_id = auth.uid();
end;
$$;

create or replace function public.remove_household_member(p_household_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public, auth
as $$
declare v_owner_count integer;
begin
  if not exists (select 1 from public.household_members where household_id = p_household_id and user_id = auth.uid() and role = 'owner') then
    raise exception 'Only an owner may remove a member';
  end if;
  if p_user_id = auth.uid() then raise exception 'Use leave_household to leave'; end if;
  select count(*) into v_owner_count from public.household_members where household_id = p_household_id and role = 'owner';
  if v_owner_count = 1 and exists (select 1 from public.household_members where household_id = p_household_id and user_id = p_user_id and role = 'owner') then
    raise exception 'The last owner cannot be removed';
  end if;
  delete from public.household_members where household_id = p_household_id and user_id = p_user_id;
  if not found then raise exception 'Member not found'; end if;
end;
$$;

revoke all on function public.update_my_profile(text) from public, anon;
revoke all on function public.update_household_settings(uuid,text,text) from public, anon;
revoke all on function public.list_household_invitations(uuid) from public, anon;
revoke all on function public.revoke_household_invitation(uuid) from public, anon;
revoke all on function public.change_household_member_role(uuid,uuid,text) from public, anon;
revoke all on function public.leave_household(uuid) from public, anon;
revoke all on function public.remove_household_member(uuid,uuid) from public, anon;
grant execute on function public.update_my_profile(text) to authenticated;
grant execute on function public.update_household_settings(uuid,text,text) to authenticated;
grant execute on function public.list_household_invitations(uuid) to authenticated;
grant execute on function public.revoke_household_invitation(uuid) to authenticated;
grant execute on function public.change_household_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.leave_household(uuid) to authenticated;
grant execute on function public.remove_household_member(uuid,uuid) to authenticated;
