-- Avoid PL/pgSQL output-column ambiguity in the partial-index upsert.
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

  update public.household_invitations i
  set status = 'expired'
  where i.household_id = p_household_id
    and i.invited_email = v_email
    and i.status = 'pending'
    and i.expires_at <= now();

  select i.* into v_invitation
  from public.household_invitations i
  where i.household_id = p_household_id
    and i.invited_email = v_email
    and i.status = 'pending'
  for update;

  if found then
    update public.household_invitations i
    set invited_by = auth.uid(), expires_at = now() + interval '14 days'
    where i.id = v_invitation.id
    returning i.* into v_invitation;
  else
    insert into public.household_invitations(
      household_id, invited_by, invited_email, proposed_role
    ) values (p_household_id, auth.uid(), v_email, 'member')
    returning * into v_invitation;
  end if;

  return query
  select v_invitation.id, h.id, h.name, v_invitation.invited_email,
         v_invitation.proposed_role, v_invitation.status,
         v_invitation.expires_at
  from public.households h where h.id = v_invitation.household_id;
end;
$$;

revoke all on function public.create_household_invitation(uuid, text) from public, anon;
grant execute on function public.create_household_invitation(uuid, text) to authenticated;
