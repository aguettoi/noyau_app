-- Atomic and idempotent materialisation of an already validated accounts import.
-- The Flutter client sends centimes; conversion to numeric MAD stays server-side
-- to preserve exact monetary values.
create table public.accounts_import_executions (
  household_id uuid not null references public.households(id) on delete cascade,
  id uuid not null,
  status text not null check (status = 'completed'),
  result jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz not null default now(),
  primary key (household_id, id)
);

create index accounts_import_executions_household_created_idx
  on public.accounts_import_executions(household_id, created_at desc);

alter table public.accounts_import_executions enable row level security;

create policy "members read accounts import executions"
  on public.accounts_import_executions for select
  using (public.is_household_member(household_id));

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
  v_opening_balance_cents bigint;
  v_existing_result jsonb;
  v_result jsonb := jsonb_build_object('status', 'completed');
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;

  if p_import_execution_id is null then
    raise exception 'An import execution identifier is required';
  end if;

  if jsonb_typeof(p_operations) <> 'array' then
    raise exception 'Import operations must be an array';
  end if;

  insert into public.accounts_import_executions (
    household_id, id, status, result, created_by
  ) values (
    p_household_id, p_import_execution_id, 'completed', v_result, auth.uid()
  ) on conflict (household_id, id) do nothing;

  if not found then
    select result into v_existing_result
    from public.accounts_import_executions
    where household_id = p_household_id and id = p_import_execution_id;

    return coalesce(v_existing_result, v_result) ||
      jsonb_build_object('already_processed', true);
  end if;

  for v_operation in select value from jsonb_array_elements(p_operations)
  loop
    v_name := trim(coalesce(v_operation ->> 'name', ''));
    v_opening_balance_cents := nullif(v_operation ->> 'opening_balance_cents', '')::bigint;

    if v_name = '' then
      raise exception 'Each account import operation requires a name';
    end if;

    case v_operation ->> 'operation'
      when 'create' then
        v_kind := v_operation ->> 'kind';
        if v_kind not in ('bank', 'cash', 'savings', 'loan') then
          raise exception 'Unsupported account kind';
        end if;

        insert into public.accounts (household_id, name, kind, opening_balance)
        values (
          p_household_id,
          v_name,
          v_kind,
          coalesce(v_opening_balance_cents, 0) / 100.0
        );
      when 'replace_opening_balance' then
        if v_opening_balance_cents is null then
          raise exception 'Replacing an opening balance requires a value';
        end if;

        update public.accounts
        set opening_balance = v_opening_balance_cents / 100.0
        where household_id = p_household_id and name = v_name;

        if not found then
          raise exception 'Account to update does not exist';
        end if;
      else
        raise exception 'Unsupported account import operation';
    end case;
  end loop;

  update public.accounts_import_executions
  set completed_at = now(), result = v_result
  where household_id = p_household_id and id = p_import_execution_id;

  return v_result || jsonb_build_object('already_processed', false);
end;
$$;

revoke all on function public.execute_accounts_import(uuid, uuid, jsonb) from public, anon;
grant execute on function public.execute_accounts_import(uuid, uuid, jsonb) to authenticated;
