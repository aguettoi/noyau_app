-- Sprint 2.2 / Lot 2: one atomic boundary for ledger and envelope postings.
begin;

create or replace function public.create_financial_transaction_with_envelopes(
  p_household_id uuid,
  p_type text,
  p_occurred_at timestamptz,
  p_description text,
  p_amount numeric,
  p_source_account_id uuid default null,
  p_destination_account_id uuid default null,
  p_category_id uuid default null,
  p_notes text default null,
  p_direction text default 'increase',
  p_envelope_allocations jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transaction_id uuid;
  v_group_id uuid := gen_random_uuid();
  v_to_allocate_id uuid;
  v_allocation jsonb;
  v_envelope_id uuid;
  v_allocation_amount numeric(14, 2);
  v_total numeric(14, 2) := 0;
  v_seen_envelopes uuid[] := '{}';
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_type not in ('expense', 'income', 'transfer', 'adjustment') then
    raise exception 'Unsupported transaction type';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'A strictly positive amount is required';
  end if;
  if jsonb_typeof(p_envelope_allocations) <> 'array' then
    raise exception 'Envelope allocations must be an array';
  end if;

  if p_type = 'expense' then
    if jsonb_array_length(p_envelope_allocations) = 0 then
      raise exception 'An expense requires at least one envelope allocation';
    end if;
    for v_allocation in select value from jsonb_array_elements(p_envelope_allocations)
    loop
      if coalesce(v_allocation ->> 'envelope_id', '') = ''
         or coalesce(v_allocation ->> 'amount', '') = '' then
        raise exception 'Each envelope allocation requires an envelope and amount';
      end if;
      v_envelope_id := (v_allocation ->> 'envelope_id')::uuid;
      v_allocation_amount := (v_allocation ->> 'amount')::numeric(14, 2);
      if v_allocation_amount <= 0 then
        raise exception 'Each envelope allocation amount must be positive';
      end if;
      if v_envelope_id = any(v_seen_envelopes) then
        raise exception 'An envelope may appear only once in an expense split';
      end if;
      if not exists (
        select 1 from public.envelopes
        where id = v_envelope_id
          and household_id = p_household_id
          and archived_at is null
      ) then
        raise exception 'Envelope does not belong to household or is archived';
      end if;
      v_seen_envelopes := array_append(v_seen_envelopes, v_envelope_id);
      v_total := v_total + v_allocation_amount;
    end loop;
    if v_total <> p_amount then
      raise exception 'Expense envelope allocations must equal the transaction amount';
    end if;
  elsif jsonb_array_length(p_envelope_allocations) <> 0 then
    raise exception 'Only expenses accept explicit envelope allocations';
  end if;

  v_transaction_id := public.create_ledger_transaction(
    p_household_id,
    p_type,
    p_occurred_at,
    p_description,
    p_amount,
    p_source_account_id,
    p_destination_account_id,
    p_category_id,
    p_notes,
    p_direction
  );

  if p_type = 'expense' then
    insert into public.envelope_movements(
      household_id, envelope_id, financial_transaction_id, movement_group_id,
      movement_type, direction, amount, occurred_at, description, created_by
    )
    select
      p_household_id,
      (value ->> 'envelope_id')::uuid,
      v_transaction_id,
      v_group_id,
      'consumption',
      'outflow',
      (value ->> 'amount')::numeric(14, 2),
      coalesce(p_occurred_at, now()),
      trim(p_description),
      auth.uid()
    from jsonb_array_elements(p_envelope_allocations);
  elsif p_type = 'income' then
    v_to_allocate_id := public.ensure_household_system_envelope(
      p_household_id,
      'to_allocate'
    );
    insert into public.envelope_movements(
      household_id, envelope_id, financial_transaction_id, movement_group_id,
      movement_type, direction, amount, occurred_at, description, created_by
    ) values (
      p_household_id, v_to_allocate_id, v_transaction_id, v_group_id,
      'allocation', 'inflow', p_amount, coalesce(p_occurred_at, now()),
      trim(p_description), auth.uid()
    );
  end if;

  return v_transaction_id;
end;
$$;

revoke all on function public.create_financial_transaction_with_envelopes(
  uuid, text, timestamptz, text, numeric, uuid, uuid, uuid, text, text, jsonb
) from public, anon;
grant execute on function public.create_financial_transaction_with_envelopes(
  uuid, text, timestamptz, text, numeric, uuid, uuid, uuid, text, text, jsonb
) to authenticated;

commit;
