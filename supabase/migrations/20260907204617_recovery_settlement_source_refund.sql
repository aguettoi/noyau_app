-- Recovery settlements always restore their linked source envelope when one
-- exists. The legacy boolean parameter is retained for RPC compatibility but
-- deliberately no longer controls the canonical financial outcome.
create or replace function public.settle_recovery_event(
  p_household_id uuid, p_obligation_id uuid, p_occurred_at timestamptz,
  p_description text, p_amount numeric, p_destination_account_id uuid,
  p_refund_source_envelope boolean default false, p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_event_id uuid;
  v_transaction_id uuid;
  v_receivable_id uuid;
  v_remaining numeric;
  v_source_event_id uuid;
  v_source_envelope_id uuid;
  v_available_refund numeric;
  v_group_id uuid;
begin
  v_event_id := public.create_or_get_financial_event(
    p_household_id,
    'recovery_settlement',
    p_occurred_at,
    p_description,
    p_notes,
    p_idempotency_key
  );
  if exists (
    select 1 from public.obligation_settlements where event_id = v_event_id
  ) then
    return v_event_id;
  end if;

  perform public.assert_financial_event_ordinary_account(
    p_household_id,
    p_destination_account_id
  );
  select recovery_source_event_id, recovery_source_envelope_id
    into v_source_event_id, v_source_envelope_id
  from public.obligations
  where id = p_obligation_id
    and household_id = p_household_id
    and obligation_kind = 'receivable'
    and receivable_kind = 'recovery'
  for update;
  if not found then
    raise exception 'Open recovery receivable does not belong to household';
  end if;

  select remaining_amount into v_remaining
  from public.obligation_balances
  where obligation_id = p_obligation_id and household_id = p_household_id;
  if p_amount is null or p_amount <= 0 or p_amount > v_remaining then
    raise exception 'Settlement amount exceeds remaining recovery';
  end if;

  if v_source_envelope_id is not null then
    if not exists (
      select 1 from public.envelopes
      where id = v_source_envelope_id and household_id = p_household_id
    ) then
      raise exception 'Recovery source envelope does not belong to household';
    end if;

    select
      coalesce(sum(movements.amount) filter (
        where movements.movement_type = 'consumption'
      ), 0) - coalesce(sum(movements.amount) filter (
        where movements.movement_type = 'refund'
      ), 0)
      into v_available_refund
    from public.envelope_movements movements
    left join public.obligation_settlements settlements
      on settlements.event_id = movements.event_id
    left join public.obligations recovery_obligations
      on recovery_obligations.id = settlements.obligation_id
    where movements.household_id = p_household_id
      and movements.envelope_id = v_source_envelope_id
      and (
        movements.event_id = v_source_event_id
        or (
          recovery_obligations.recovery_source_event_id = v_source_event_id
          and recovery_obligations.recovery_source_envelope_id = v_source_envelope_id
        )
      );
    if p_amount > v_available_refund then
      raise exception 'Recovery refund exceeds unreimbursed source envelope consumption';
    end if;
  end if;

  v_receivable_id := public.ensure_financial_event_system_account(
    p_household_id,
    'receivable'
  );
  v_transaction_id := public.insert_financial_event_ledger_transaction(
    p_household_id,
    v_event_id,
    'recovery_settlement',
    p_occurred_at,
    p_description,
    p_amount,
    null,
    p_destination_account_id,
    p_destination_account_id,
    v_receivable_id,
    p_notes
  );
  insert into public.obligation_settlements(
    household_id, obligation_id, event_id, financial_transaction_id, amount,
    occurred_at, created_by
  ) values (
    p_household_id, p_obligation_id, v_event_id, v_transaction_id, p_amount,
    coalesce(p_occurred_at, now()), auth.uid()
  );

  if v_source_envelope_id is not null then
    v_group_id := gen_random_uuid();
    insert into public.envelope_movements(
      household_id, event_id, envelope_id, financial_transaction_id,
      movement_group_id, movement_type, direction, amount, occurred_at,
      description, created_by
    ) values (
      p_household_id, v_event_id, v_source_envelope_id, v_transaction_id,
      v_group_id, 'refund', 'inflow', p_amount,
      coalesce(p_occurred_at, now()), trim(p_description), auth.uid()
    );
  end if;
  return v_event_id;
end;
$$;

revoke all on function public.settle_recovery_event(
  uuid, uuid, timestamptz, text, numeric, uuid, boolean, text, uuid
) from public, anon;
grant execute on function public.settle_recovery_event(
  uuid, uuid, timestamptz, text, numeric, uuid, boolean, text, uuid
) to authenticated;
