-- Account ownership is scoped to a household member identity, never a free name.
alter table public.accounts
  add column if not exists ownership_type text not null default 'household'
  check (ownership_type in ('household', 'individual', 'shared'));

-- Enables the composite foreign key that guarantees an account holder belongs
-- to the same household as its account.
alter table public.accounts
  add constraint accounts_id_household_unique unique (id, household_id);

create table public.account_holders (
  account_id uuid not null,
  household_id uuid not null,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (account_id, user_id),
  foreign key (account_id, household_id)
    references public.accounts(id, household_id) on delete cascade,
  foreign key (household_id, user_id)
    references public.household_members(household_id, user_id) on delete restrict
);

create index account_holders_household_user_idx
  on public.account_holders(household_id, user_id);

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

  if v_ownership_type = 'household' and v_holder_count <> 0 then
    raise exception 'A household account cannot have holders';
  elsif v_ownership_type = 'individual' and v_holder_count <> 1 then
    raise exception 'An individual account requires exactly one holder';
  elsif v_ownership_type = 'shared' and v_holder_count < 2 then
    raise exception 'A shared account requires at least two holders';
  end if;
end;
$$;

create or replace function public.assert_account_ownership_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name = 'accounts' then
    perform public.assert_account_ownership(coalesce(new.id, old.id));
  else
    perform public.assert_account_ownership(coalesce(new.account_id, old.account_id));
  end if;
  return null;
end;
$$;

create constraint trigger accounts_ownership_valid
after insert or update of ownership_type on public.accounts
deferrable initially deferred for each row
execute function public.assert_account_ownership_trigger();

create constraint trigger account_holders_ownership_valid
after insert or update or delete on public.account_holders
deferrable initially deferred for each row
execute function public.assert_account_ownership_trigger();

alter table public.account_holders enable row level security;

create policy "members read account holders" on public.account_holders for select
using (public.is_household_member(household_id));
create policy "members manage account holders" on public.account_holders for all
using (public.is_household_member(household_id))
with check (public.is_household_member(household_id));

create policy "members read household profiles" on public.profiles for select
using (
  exists (
    select 1
    from public.household_members self_member
    join public.household_members target_member
      on target_member.household_id = self_member.household_id
    where self_member.user_id = auth.uid()
      and target_member.user_id = profiles.id
  )
);

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
  if (p_ownership_type = 'household' and v_holder_count <> 0)
     or (p_ownership_type = 'individual' and v_holder_count <> 1)
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

revoke all on function public.create_account_with_holders(uuid, text, text, numeric, timestamptz, text, uuid[]) from public, anon;
grant execute on function public.create_account_with_holders(uuid, text, text, numeric, timestamptz, text, uuid[]) to authenticated;

create or replace function public.execute_accounts_import(
  p_household_id uuid,
  p_import_execution_id uuid,
  p_operations jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation jsonb;
  v_name text;
  v_kind text;
  v_ownership_type text;
  v_holder_user_ids uuid[];
  v_opening_balance_cents bigint;
  v_existing_result jsonb;
  v_result jsonb := jsonb_build_object('status', 'completed');
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_import_execution_id is null then raise exception 'An import execution identifier is required'; end if;
  if jsonb_typeof(p_operations) <> 'array' then raise exception 'Import operations must be an array'; end if;

  insert into public.accounts_import_executions (household_id, id, status, result, created_by)
  values (p_household_id, p_import_execution_id, 'completed', v_result, auth.uid())
  on conflict (household_id, id) do nothing;
  if not found then
    select result into v_existing_result from public.accounts_import_executions
    where household_id = p_household_id and id = p_import_execution_id;
    return coalesce(v_existing_result, v_result) || jsonb_build_object('already_processed', true);
  end if;

  for v_operation in select value from jsonb_array_elements(p_operations) loop
    v_name := trim(coalesce(v_operation ->> 'name', ''));
    v_opening_balance_cents := nullif(v_operation ->> 'opening_balance_cents', '')::bigint;
    if v_name = '' then raise exception 'Each account import operation requires a name'; end if;
    case v_operation ->> 'operation'
      when 'create' then
        v_kind := v_operation ->> 'kind';
        v_ownership_type := coalesce(v_operation ->> 'ownership_type', 'household');
        select coalesce(array_agg(value::uuid), '{}') into v_holder_user_ids
        from jsonb_array_elements_text(coalesce(v_operation -> 'holder_user_ids', '[]'::jsonb)) value;
        if v_kind not in ('bank', 'cash', 'savings', 'loan') then raise exception 'Unsupported account kind'; end if;
        perform public.create_account_with_holders(
          p_household_id, v_name, v_kind, coalesce(v_opening_balance_cents, 0) / 100.0,
          null, v_ownership_type, v_holder_user_ids
        );
      when 'replace_opening_balance' then
        if v_opening_balance_cents is null then raise exception 'Replacing an opening balance requires a value'; end if;
        update public.accounts set opening_balance = v_opening_balance_cents / 100.0
        where household_id = p_household_id and name = v_name;
        if not found then raise exception 'Account to update does not exist'; end if;
      else raise exception 'Unsupported account import operation';
    end case;
  end loop;
  update public.accounts_import_executions set completed_at = now(), result = v_result
  where household_id = p_household_id and id = p_import_execution_id;
  return v_result || jsonb_build_object('already_processed', false);
end;
$$;
