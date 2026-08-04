-- All account ownership types use account_holders. The type only defines
-- cardinality: household accepts zero or more, individual exactly one and
-- shared at least two holders.
create or replace function public.assert_account_ownership(p_account_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ownership_type text;
  v_holder_count integer;
begin
  select ownership_type into v_ownership_type
  from public.accounts where id = p_account_id;
  if not found then
    return;
  end if;

  select count(*) into v_holder_count
  from public.account_holders where account_id = p_account_id;

  if v_ownership_type = 'individual' and v_holder_count <> 1 then
    raise exception 'An individual account requires exactly one holder';
  elsif v_ownership_type = 'shared' and v_holder_count < 2 then
    raise exception 'A shared account requires at least two holders';
  end if;
end;
$$;

create or replace function public.create_account_with_holders(
  p_household_id uuid,
  p_name text,
  p_kind text,
  p_opening_balance numeric,
  p_archived_at timestamptz,
  p_ownership_type text,
  p_holder_user_ids uuid[] default '{}'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_holder_id uuid;
  v_holder_count integer := coalesce(cardinality(p_holder_user_ids), 0);
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_ownership_type not in ('household', 'individual', 'shared') then
    raise exception 'Unsupported account ownership type';
  end if;
  if (p_ownership_type = 'individual' and v_holder_count <> 1)
     or (p_ownership_type = 'shared' and v_holder_count < 2)
     or (select count(distinct value) from unnest(p_holder_user_ids) value) <> v_holder_count then
    raise exception 'Invalid account holders for the ownership type';
  end if;

  foreach v_holder_id in array p_holder_user_ids loop
    if not exists (
      select 1 from public.household_members
      where household_id = p_household_id and user_id = v_holder_id
    ) then
      raise exception 'An account holder must belong to the household';
    end if;
  end loop;

  insert into public.accounts (
    household_id, name, kind, opening_balance, archived_at, ownership_type
  ) values (
    p_household_id, trim(p_name), p_kind, p_opening_balance, p_archived_at, p_ownership_type
  ) returning id into v_account_id;

  foreach v_holder_id in array p_holder_user_ids loop
    insert into public.account_holders(account_id, household_id, user_id)
    values (v_account_id, p_household_id, v_holder_id);
  end loop;
  return v_account_id;
end;
$$;
