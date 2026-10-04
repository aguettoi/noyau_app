-- Final-user authentication onboarding. Financial data is deliberately absent.

create table public.household_invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  invited_by uuid not null references auth.users(id) on delete restrict,
  invited_email text not null,
  proposed_role text not null default 'member' check (proposed_role = 'member'),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_by uuid references auth.users(id) on delete restrict,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  check (invited_email = lower(trim(invited_email))),
  check ((status = 'accepted') = (accepted_by is not null and accepted_at is not null))
);

create unique index household_invitations_one_pending_email_idx
  on public.household_invitations(household_id, invited_email)
  where status = 'pending';

create index household_invitations_email_status_idx
  on public.household_invitations(invited_email, status, expires_at);

alter table public.household_invitations enable row level security;

-- Invitations are intentionally RPC-only. An invitation does not grant any
-- household or financial-table access.
revoke all on public.household_invitations from anon, authenticated;

create or replace function public.create_household(household_name text)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not exists (
    select 1 from auth.users u
    where u.id = v_user_id and u.email_confirmed_at is not null
  ) then
    raise exception 'Email confirmation required';
  end if;
  if nullif(trim(household_name), '') is null
     or char_length(trim(household_name)) > 80 then
    raise exception 'Household name must contain between 1 and 80 characters';
  end if;
  if exists (
    select 1
    from public.household_members hm
    join public.households h on h.id = hm.household_id
    where hm.user_id = v_user_id and h.classification = 'operational'
  ) then
    raise exception 'User already belongs to an operational household';
  end if;

  insert into public.households(name, classification)
  values (trim(household_name), 'operational')
  returning id into v_household_id;

  insert into public.household_members(household_id, user_id, role)
  values (v_household_id, v_user_id, 'owner');

  return v_household_id;
end;
$$;

create or replace function public.create_household_invitation(
  p_household_id uuid,
  p_invited_email text
)
returns table (
  invitation_id uuid,
  household_id uuid,
  household_name text,
  invited_email text,
  proposed_role text,
  status text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text := lower(trim(p_invited_email));
  v_invitation public.household_invitations%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if v_email is null or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    raise exception 'A valid invited email is required';
  end if;
  if not exists (
    select 1 from public.household_members hm
    join public.households h on h.id = hm.household_id
    where hm.household_id = p_household_id
      and hm.user_id = auth.uid()
      and hm.role = 'owner'
      and h.classification = 'operational'
  ) then
    raise exception 'Only an operational household owner may invite a member';
  end if;
  if exists (
    select 1 from public.household_members hm
    join auth.users u on u.id = hm.user_id
    where hm.household_id = p_household_id and lower(u.email) = v_email
  ) then
    raise exception 'This email already belongs to the household';
  end if;

  update public.household_invitations
  set status = 'expired'
  where household_id = p_household_id
    and invited_email = v_email
    and status = 'pending'
    and expires_at <= now();

  insert into public.household_invitations(
    household_id, invited_by, invited_email, proposed_role
  ) values (p_household_id, auth.uid(), v_email, 'member')
  on conflict (household_id, invited_email) where status = 'pending'
  do update set
    invited_by = excluded.invited_by,
    expires_at = now() + interval '14 days'
  returning * into v_invitation;

  return query
  select v_invitation.id, h.id, h.name, v_invitation.invited_email,
         v_invitation.proposed_role, v_invitation.status,
         v_invitation.expires_at
  from public.households h where h.id = v_invitation.household_id;
end;
$$;

create or replace function public.list_my_pending_household_invitations()
returns table (
  invitation_id uuid,
  household_id uuid,
  household_name text,
  invited_by_name text,
  proposed_role text,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select i.id, i.household_id, h.name,
         coalesce(p.display_name, 'Un membre du foyer'),
         i.proposed_role, i.expires_at
  from public.household_invitations i
  join public.households h on h.id = i.household_id
  left join public.profiles p on p.id = i.invited_by
  join auth.users u on u.id = auth.uid()
  where lower(u.email) = i.invited_email
    and u.email_confirmed_at is not null
    and i.status = 'pending'
    and i.expires_at > now()
    and h.classification = 'operational'
  order by i.created_at asc;
$$;

create or replace function public.accept_household_invitation(p_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_invitation public.household_invitations%rowtype;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  select lower(email) into v_email
  from auth.users
  where id = v_user_id and email_confirmed_at is not null;
  if v_email is null then raise exception 'Email confirmation required'; end if;

  select * into v_invitation
  from public.household_invitations
  where id = p_invitation_id
  for update;

  if not found
     or v_invitation.status <> 'pending'
     or v_invitation.expires_at <= now()
     or v_invitation.invited_email <> v_email then
    raise exception 'Invitation unavailable or not intended for this account';
  end if;
  if not exists (
    select 1 from public.households h
    where h.id = v_invitation.household_id and h.classification = 'operational'
  ) then
    raise exception 'Invitation household is not operational';
  end if;

  insert into public.household_members(household_id, user_id, role)
  values (v_invitation.household_id, v_user_id, 'member')
  on conflict (household_id, user_id) do nothing;

  update public.household_invitations
  set status = 'accepted', accepted_by = v_user_id, accepted_at = now()
  where id = v_invitation.id;

  return v_invitation.household_id;
end;
$$;

revoke all on function public.create_household(text) from public, anon;
revoke all on function public.create_household_invitation(uuid, text) from public, anon;
revoke all on function public.list_my_pending_household_invitations() from public, anon;
revoke all on function public.accept_household_invitation(uuid) from public, anon;
grant execute on function public.create_household(text) to authenticated;
grant execute on function public.create_household_invitation(uuid, text) to authenticated;
grant execute on function public.list_my_pending_household_invitations() to authenticated;
grant execute on function public.accept_household_invitation(uuid) to authenticated;

comment on table public.household_invitations is
  'Email-bound, expiring invitations. They never grant financial access until explicitly accepted.';
