begin;

create or replace function public.quick_bulk_import_financial_events(
  p_household_id uuid,
  p_rows jsonb,
  p_idempotency_key text
) returns integer
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_row jsonb;
  v_index integer := 0;
  v_account_id uuid;
  v_envelope_id uuid;
  v_member_id uuid;
  v_kind text;
  v_amount numeric(14,2);
  v_occurred_at timestamptz;
  v_event_key uuid;
  v_allocations jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) = 0 or jsonb_array_length(p_rows) > 500 then
    raise exception 'Quick import requires between 1 and 500 rows';
  end if;
  if nullif(trim(p_idempotency_key), '') is null then
    raise exception 'An idempotency key is required';
  end if;

  -- Validate the complete payload before the first canonical write. Any later
  -- exception also rolls the entire PostgreSQL statement back atomically.
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_index := v_index + 1;
    v_kind := v_row ->> 'kind';
    v_amount := nullif(v_row ->> 'amount', '')::numeric;
    v_occurred_at := nullif(v_row ->> 'occurred_on', '')::date::timestamptz;
    if v_kind not in ('expense', 'income') or v_amount is null or v_amount <= 0
       or v_occurred_at is null or nullif(trim(v_row ->> 'description'), '') is null then
      raise exception 'Invalid quick import row %', v_index;
    end if;
    if upper(coalesce(v_row ->> 'currency', '')) <> 'MAD' then
      raise exception 'Unsupported currency on row %', v_index;
    end if;
    select a.id into v_account_id
    from public.accounts a
    where a.household_id = p_household_id and a.archived_at is null
      and not a.is_system and lower(a.name) = lower(trim(v_row ->> 'account_name'))
      and private.can_discover_account(a.id, auth.uid());
    if v_account_id is null then raise exception 'Unknown or unauthorized account on row %', v_index; end if;
    select hm.user_id into v_member_id
    from public.household_members hm join public.profiles p on p.id = hm.user_id
    where hm.household_id = p_household_id and hm.inactive_at is null
      and lower(trim(p.display_name)) = lower(trim(v_row ->> 'member_name'));
    if v_member_id is null then raise exception 'Unknown household member on row %', v_index; end if;
    v_envelope_id := null;
    if nullif(trim(v_row ->> 'envelope_name'), '') is not null then
      select e.id into v_envelope_id from public.envelopes e
      where e.household_id = p_household_id and e.archived_at is null
        and lower(e.name) = lower(trim(v_row ->> 'envelope_name'));
      if v_envelope_id is null then raise exception 'Unknown envelope on row %', v_index; end if;
    end if;
  end loop;

  v_index := 0;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_index := v_index + 1;
    v_kind := v_row ->> 'kind';
    v_amount := (v_row ->> 'amount')::numeric;
    v_occurred_at := (v_row ->> 'occurred_on')::date::timestamptz;
    select a.id into v_account_id from public.accounts a
      where a.household_id=p_household_id and a.archived_at is null and not a.is_system
        and lower(a.name)=lower(trim(v_row ->> 'account_name'))
        and private.can_discover_account(a.id,auth.uid());
    v_envelope_id := null;
    if nullif(trim(v_row ->> 'envelope_name'), '') is not null then
      select e.id into v_envelope_id from public.envelopes e
      where e.household_id=p_household_id and e.archived_at is null
        and lower(e.name)=lower(trim(v_row ->> 'envelope_name'));
    end if;
    v_event_key := md5(p_idempotency_key || ':' || v_index::text)::uuid;
    v_allocations := case when v_envelope_id is null then '[]'::jsonb else
      jsonb_build_array(jsonb_build_object('envelope_id',v_envelope_id,'amount',v_amount)) end;
    if v_kind = 'expense' then
      perform public.create_cash_expense_with_payment_context(
        p_household_id,v_occurred_at,trim(v_row ->> 'description'),v_amount,
        v_account_id,null,v_allocations,
        concat_ws(' · ',nullif(trim(v_row ->> 'category'),''),nullif(trim(v_row ->> 'external_reference'),'')),
        v_event_key);
    else
      perform public.create_cash_income_event(
        p_household_id,v_occurred_at,trim(v_row ->> 'description'),v_amount,
        v_account_id,v_allocations,
        concat_ws(' · ',nullif(trim(v_row ->> 'category'),''),nullif(trim(v_row ->> 'external_reference'),'')),
        v_event_key);
    end if;
  end loop;
  return v_index;
end;
$$;

revoke all on function public.quick_bulk_import_financial_events(uuid,jsonb,text) from public, anon;
grant execute on function public.quick_bulk_import_financial_events(uuid,jsonb,text) to authenticated;

commit;
