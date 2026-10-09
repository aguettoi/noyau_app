-- F8: memberships are retired without deleting the historical identity.
-- New operations only use active members; historical foreign keys remain valid.

alter table public.household_members
  add column if not exists inactive_at timestamptz;

create index if not exists household_members_active_household_idx
  on public.household_members(household_id, created_at)
  where inactive_at is null;

create or replace function public.is_household_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.household_members
    where household_id = target_household
      and user_id = auth.uid()
      and inactive_at is null
  );
$$;

create or replace function public.is_active_household_member(
  target_household uuid,
  target_user uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.household_members
    where household_id = target_household
      and user_id = target_user
      and inactive_at is null
  );
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
    where household_id = p_household_id and user_id = auth.uid()
      and role = 'owner' and inactive_at is null
  ) then raise exception 'Only an owner may change roles'; end if;
  if p_role = 'member' then
    select count(*) into v_owner_count from public.household_members
    where household_id = p_household_id and role = 'owner' and inactive_at is null;
    if v_owner_count <= 1 and exists (
      select 1 from public.household_members
      where household_id = p_household_id and user_id = p_user_id
        and role = 'owner' and inactive_at is null
    ) then raise exception 'The last owner cannot be demoted'; end if;
  end if;
  update public.household_members set role = p_role
  where household_id = p_household_id and user_id = p_user_id
    and inactive_at is null;
  if not found then raise exception 'Active member not found'; end if;
end;
$$;

create or replace function public.leave_household(p_household_id uuid)
returns void language plpgsql security definer set search_path = public, auth
as $$
declare v_owner_count integer;
begin
  if not exists (
    select 1 from public.household_members
    where household_id = p_household_id and user_id = auth.uid()
      and inactive_at is null
  ) then raise exception 'Membership not found'; end if;
  select count(*) into v_owner_count from public.household_members
  where household_id = p_household_id and role = 'owner' and inactive_at is null;
  if v_owner_count = 1 and exists (
    select 1 from public.household_members
    where household_id = p_household_id and user_id = auth.uid()
      and role = 'owner' and inactive_at is null
  ) then raise exception 'The last owner cannot leave the household'; end if;
  update public.household_members set inactive_at = now()
  where household_id = p_household_id and user_id = auth.uid()
    and inactive_at is null;
end;
$$;

create or replace function public.remove_household_member(
  p_household_id uuid, p_user_id uuid
)
returns void language plpgsql security definer set search_path = public, auth
as $$
declare v_owner_count integer;
begin
  if not exists (
    select 1 from public.household_members
    where household_id = p_household_id and user_id = auth.uid()
      and role = 'owner' and inactive_at is null
  ) then raise exception 'Only an owner may remove a member'; end if;
  if p_user_id = auth.uid() then raise exception 'Use leave_household to leave'; end if;
  select count(*) into v_owner_count from public.household_members
  where household_id = p_household_id and role = 'owner' and inactive_at is null;
  if v_owner_count = 1 and exists (
    select 1 from public.household_members
    where household_id = p_household_id and user_id = p_user_id
      and role = 'owner' and inactive_at is null
  ) then raise exception 'The last owner cannot be removed'; end if;
  update public.household_members set inactive_at = now()
  where household_id = p_household_id and user_id = p_user_id
    and inactive_at is null;
  if not found then raise exception 'Active member not found'; end if;
end;
$$;

create or replace function public.accept_household_invitation(p_invitation_id uuid)
returns uuid language plpgsql security definer set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_invitation public.household_invitations%rowtype;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  select lower(email) into v_email from auth.users
  where id = v_user_id and email_confirmed_at is not null;
  if v_email is null then raise exception 'Email confirmation required'; end if;
  select * into v_invitation from public.household_invitations
  where id = p_invitation_id for update;
  if not found or v_invitation.status <> 'pending'
     or v_invitation.expires_at <= now()
     or v_invitation.invited_email <> v_email then
    raise exception 'Invitation unavailable or not intended for this account';
  end if;
  if not exists (
    select 1 from public.households h
    where h.id = v_invitation.household_id and h.classification = 'operational'
  ) then raise exception 'Invitation household is not operational'; end if;
  insert into public.household_members(household_id, user_id, role, inactive_at)
  values (v_invitation.household_id, v_user_id, 'member', null)
  on conflict (household_id, user_id) do update
    set role = 'member', inactive_at = null;
  update public.household_invitations
  set status = 'accepted', accepted_by = v_user_id, accepted_at = now()
  where id = v_invitation.id;
  return v_invitation.household_id;
end;
$$;

create or replace function public.approve_budget_allocation_run(
  p_household_id uuid, p_run_id uuid
)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text; v_remaining numeric; v_hash text; v_mode text; v_required integer; v_count integer;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select status, remaining_unallocated into v_status, v_remaining
  from public.budget_allocation_runs
  where id=p_run_id and household_id=p_household_id for update;
  if not found then raise exception 'Budget run does not belong to household'; end if;
  if v_status not in ('simulated','approved') then raise exception 'Only a simulated budget run can be approved'; end if;
  if v_remaining < 0 then raise exception 'An over-allocated budget run cannot be approved'; end if;
  v_hash := public.budget_run_revision_hash(p_run_id,p_household_id);
  insert into public.budget_run_approvals(run_id,household_id,member_user_id,revision_hash)
  values(p_run_id,p_household_id,auth.uid(),v_hash)
  on conflict(run_id,member_user_id) do update
    set revision_hash=excluded.revision_hash, approved_at=now();
  select budget_validation_mode into v_mode from public.households where id=p_household_id;
  select count(*) into v_required from public.household_members
  where household_id=p_household_id and inactive_at is null;
  select count(*) into v_count
  from public.budget_run_approvals a
  join public.household_members m
    on m.household_id=a.household_id and m.user_id=a.member_user_id
  where a.run_id=p_run_id and a.household_id=p_household_id
    and a.revision_hash=v_hash and m.inactive_at is null;
  if v_mode='authorized_member' or v_count>=v_required then
    update public.budget_allocation_runs
    set status='approved',approved_by=auth.uid(),approved_at=now()
    where id=p_run_id and household_id=p_household_id and status='simulated';
  end if;
end;
$$;

create or replace function public.assert_budget_run_approved_for_current_revision()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_mode text; v_hash text; v_required integer; v_count integer;
begin
  if new.status <> 'applied' or old.status='applied' then return new; end if;
  v_hash:=public.budget_run_revision_hash(new.id,new.household_id);
  select budget_validation_mode into v_mode from public.households where id=new.household_id;
  select count(*) into v_required from public.household_members
  where household_id=new.household_id and inactive_at is null;
  select count(*) into v_count
  from public.budget_run_approvals a
  join public.household_members m
    on m.household_id=a.household_id and m.user_id=a.member_user_id
  where a.run_id=new.id and a.household_id=new.household_id
    and a.revision_hash=v_hash and m.inactive_at is null;
  if v_count < (case when v_mode='joint_required' then v_required else 1 end)
  then raise exception 'Budget approvals are incomplete or obsolete'; end if;
  return new;
end;
$$;

revoke all on function public.is_active_household_member(uuid,uuid) from public, anon;
grant execute on function public.is_active_household_member(uuid,uuid) to authenticated;
revoke all on function public.change_household_member_role(uuid,uuid,text) from public, anon;
revoke all on function public.leave_household(uuid) from public, anon;
revoke all on function public.remove_household_member(uuid,uuid) from public, anon;
revoke all on function public.accept_household_invitation(uuid) from public, anon;
revoke all on function public.approve_budget_allocation_run(uuid,uuid) from public, anon;
grant execute on function public.change_household_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.leave_household(uuid) to authenticated;
grant execute on function public.remove_household_member(uuid,uuid) to authenticated;
grant execute on function public.accept_household_invitation(uuid) to authenticated;
grant execute on function public.approve_budget_allocation_run(uuid,uuid) to authenticated;

create or replace function public.ensure_active_member_references()
returns trigger language plpgsql set search_path = public as $$
declare
  v_column text;
  v_user_id uuid;
begin
  foreach v_column in array TG_ARGV loop
    v_user_id := nullif(to_jsonb(new)->>v_column, '')::uuid;
    if v_user_id is not null and not public.is_active_household_member(new.household_id, v_user_id) then
      raise exception 'Inactive or cross-household member reference: %', v_column;
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists member_compensations_active_parties on public.member_compensations;
create trigger member_compensations_active_parties
before insert or update of debtor_user_id, creditor_user_id on public.member_compensations
for each row execute function public.ensure_active_member_references('debtor_user_id','creditor_user_id');

drop trigger if exists household_tasks_active_assignee on public.household_tasks;
create trigger household_tasks_active_assignee
before insert or update of assignee_user_id on public.household_tasks
for each row execute function public.ensure_active_member_references('assignee_user_id');

drop trigger if exists payment_methods_active_holder on public.payment_methods;
create trigger payment_methods_active_holder
before insert or update of holder_user_id on public.payment_methods
for each row execute function public.ensure_active_member_references('holder_user_id');

drop trigger if exists account_holders_active_holder on public.account_holders;
create trigger account_holders_active_holder
before insert or update of user_id on public.account_holders
for each row execute function public.ensure_active_member_references('user_id');

drop trigger if exists budget_member_incomes_active_member on public.budget_scenario_member_incomes;
create trigger budget_member_incomes_active_member
before insert or update of member_user_id on public.budget_scenario_member_incomes
for each row execute function public.ensure_active_member_references('member_user_id');

drop trigger if exists budget_sources_active_member on public.budget_scenario_sources;
create trigger budget_sources_active_member
before insert or update of member_user_id on public.budget_scenario_sources
for each row execute function public.ensure_active_member_references('member_user_id');

drop trigger if exists budget_steps_active_member on public.budget_scenario_steps;
create trigger budget_steps_active_member
before insert or update of member_user_id on public.budget_scenario_steps
for each row execute function public.ensure_active_member_references('member_user_id');

drop trigger if exists budget_rules_active_member on public.budget_scenario_rules;
create trigger budget_rules_active_member
before insert or update of funding_member_user_id on public.budget_scenario_rules
for each row execute function public.ensure_active_member_references('funding_member_user_id');

drop trigger if exists shopping_priorities_active_member on public.shopping_item_member_priorities;
create trigger shopping_priorities_active_member
before insert or update of member_user_id on public.shopping_item_member_priorities
for each row execute function public.ensure_active_member_references('member_user_id');

drop trigger if exists wealth_asset_owners_active_member on public.wealth_asset_owners;
create trigger wealth_asset_owners_active_member
before insert or update of user_id on public.wealth_asset_owners
for each row execute function public.ensure_active_member_references('user_id');

revoke all on function public.ensure_active_member_references() from public, anon, authenticated;
