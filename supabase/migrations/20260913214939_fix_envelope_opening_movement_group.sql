-- Preserve the existing non-null movement-group invariant for canonical
-- envelope openings. The group is internal to the one FinancialEvent.
begin;

create or replace function public.create_envelope_opening_event(
  p_household_id uuid, p_occurred_at timestamptz, p_description text,
  p_openings jsonb, p_notes text default null, p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_event_id uuid;
  v_movement_group_id uuid := gen_random_uuid();
  v_item jsonb;
  v_envelope_id uuid;
  v_amount numeric;
  v_seen uuid[] := '{}';
begin
  v_event_id := public.create_or_get_financial_event(
    p_household_id, 'envelope_opening', p_occurred_at, p_description, p_notes, p_idempotency_key);
  if exists (select 1 from public.envelope_movements where event_id = v_event_id) then return v_event_id; end if;
  if jsonb_typeof(p_openings) <> 'array' or jsonb_array_length(p_openings) = 0 then
    raise exception 'At least one envelope opening is required';
  end if;
  for v_item in select value from jsonb_array_elements(p_openings) loop
    v_envelope_id := nullif(v_item->>'envelope_id','')::uuid;
    v_amount := nullif(v_item->>'amount','')::numeric;
    if v_envelope_id is null or v_amount is null or v_amount <= 0 then raise exception 'Each envelope opening requires a positive amount and envelope'; end if;
    if v_envelope_id = any(v_seen) then raise exception 'An envelope can appear only once in an opening'; end if;
    if not exists (select 1 from public.envelopes where id=v_envelope_id and household_id=p_household_id and archived_at is null) then raise exception 'Opening envelope is not an active household envelope'; end if;
    v_seen := array_append(v_seen,v_envelope_id);
  end loop;
  insert into public.envelope_movements(household_id,event_id,envelope_id,movement_group_id,movement_type,direction,amount,occurred_at,description,created_by)
  select p_household_id,v_event_id,(value->>'envelope_id')::uuid,v_movement_group_id,'opening','inflow',(value->>'amount')::numeric,
    coalesce(p_occurred_at,now()),trim(p_description),auth.uid()
  from jsonb_array_elements(p_openings);
  return v_event_id;
end;
$$;

commit;
