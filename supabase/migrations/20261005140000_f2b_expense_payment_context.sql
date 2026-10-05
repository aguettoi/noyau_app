-- F2B: persist the actual payment method and an immutable recommendation
-- snapshot on the canonical expense FinancialEvent. No compensating entry is
-- created: the existing expense RPC remains the only financial write path.

alter table public.financial_events
  add column if not exists actual_payment_method_id uuid,
  add column if not exists payment_recommendation_snapshot jsonb;

alter table public.financial_events
  drop constraint if exists financial_events_actual_payment_method_household_fk;
alter table public.financial_events
  add constraint financial_events_actual_payment_method_household_fk
  foreign key (actual_payment_method_id, household_id)
  references public.payment_methods(id, household_id);

alter table public.financial_events
  drop constraint if exists financial_events_payment_recommendation_snapshot_check;
alter table public.financial_events
  add constraint financial_events_payment_recommendation_snapshot_check
  check (
    payment_recommendation_snapshot is null
    or jsonb_typeof(payment_recommendation_snapshot) = 'array'
  );

create or replace function public.create_cash_expense_with_payment_context(
  p_household_id uuid,
  p_occurred_at timestamptz,
  p_description text,
  p_amount numeric,
  p_source_account_id uuid,
  p_actual_payment_method_id uuid,
  p_envelope_allocations jsonb,
  p_notes text,
  p_idempotency_key uuid
) returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_event_id uuid;
  v_method public.payment_methods%rowtype;
  v_snapshot jsonb;
  v_existing_method_id uuid;
  v_existing_snapshot jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;

  perform public.assert_financial_event_ordinary_account(
    p_household_id, p_source_account_id
  );

  if p_actual_payment_method_id is not null then
    select * into v_method
    from public.payment_methods
    where id = p_actual_payment_method_id
      and household_id = p_household_id;
    if not found then
      raise exception 'Payment method household mismatch';
    end if;
    if not v_method.active then
      raise exception 'Inactive payment method cannot be used for a new expense';
    end if;
    if v_method.account_id is not null
       and v_method.account_id <> p_source_account_id then
      raise exception 'Payment method account mismatch';
    end if;
    if v_method.holder_user_id is not null and not exists (
      select 1 from public.household_members hm
      where hm.household_id = p_household_id
        and hm.user_id = v_method.holder_user_id
    ) then
      raise exception 'Payment method holder household mismatch';
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'envelope_id', e.id,
    'recommended_account_id', e.recommended_account_id,
    'recommended_payment_method_id', e.recommended_payment_method_id,
    'actual_account_matches',
      e.recommended_account_id is null
      or e.recommended_account_id = p_source_account_id,
    'actual_payment_method_matches',
      e.recommended_payment_method_id is null
      or e.recommended_payment_method_id = p_actual_payment_method_id
  ) order by allocation.ordinality), '[]'::jsonb)
  into v_snapshot
  from jsonb_array_elements(p_envelope_allocations)
    with ordinality allocation(value, ordinality)
  join public.envelopes e
    on e.id = nullif(allocation.value ->> 'envelope_id', '')::uuid
   and e.household_id = p_household_id;

  v_event_id := public.create_cash_expense_event(
    p_household_id, p_occurred_at, p_description, p_amount,
    p_source_account_id, p_envelope_allocations, p_notes, p_idempotency_key
  );

  select actual_payment_method_id, payment_recommendation_snapshot
  into v_existing_method_id, v_existing_snapshot
  from public.financial_events
  where id = v_event_id
  for update;

  if v_existing_snapshot is not null then
    if v_existing_method_id is distinct from p_actual_payment_method_id
       or v_existing_snapshot is distinct from v_snapshot then
      raise exception 'Idempotent expense replay has different payment context';
    end if;
    return v_event_id;
  end if;

  update public.financial_events
  set actual_payment_method_id = p_actual_payment_method_id,
      payment_recommendation_snapshot = v_snapshot
  where id = v_event_id;

  return v_event_id;
end;
$$;

revoke all on function public.create_cash_expense_with_payment_context(
  uuid,timestamptz,text,numeric,uuid,uuid,jsonb,text,uuid
) from public, anon;
grant execute on function public.create_cash_expense_with_payment_context(
  uuid,timestamptz,text,numeric,uuid,uuid,jsonb,text,uuid
) to authenticated;
