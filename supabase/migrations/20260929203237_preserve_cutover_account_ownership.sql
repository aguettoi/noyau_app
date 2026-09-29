-- Preserve canonical account ownership while materializing Cutover B1.
-- This is additive: no historical row is rewritten or backfilled.
begin;

create or replace function public.execute_cutover_opening_import_materialize(
  p_household_id uuid,
  p_cutover_id uuid,
  p_source_fingerprint text,
  p_effective_date date,
  p_plan jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_actor_id uuid := auth.uid();
  v_run public.cutover_opening_runs%rowtype;
  v_existing public.cutover_opening_runs%rowtype;
  v_plan_fingerprint text;
  v_account jsonb;
  v_envelope jsonb;
  v_account_id uuid;
  v_envelope_id uuid;
  v_event_id uuid;
  v_account_name text;
  v_envelope_name text;
  v_kind text;
  v_amount numeric;
  v_conflict text;
  v_ownership_type text;
  v_existing_ownership_type text;
  v_holder_ids uuid[];
  v_existing_holder_ids uuid[];
  v_holder_id uuid;
  v_is_to_allocate boolean;
  v_account_events jsonb := '[]'::jsonb;
  v_envelope_openings jsonb := '[]'::jsonb;
  v_account_result jsonb := '[]'::jsonb;
  v_envelope_result jsonb := '[]'::jsonb;
  v_envelope_event_id uuid;
  v_result jsonb;
  v_seen text[] := '{}';
  v_key text;
begin
  if v_actor_id is null then raise exception 'Authentication required'; end if;
  perform public.assert_household_access(p_household_id);
  if p_cutover_id is null then raise exception 'Cutover id is required'; end if;
  if p_source_fingerprint is null or p_source_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'A SHA-256 source fingerprint is required';
  end if;
  if p_effective_date is null then raise exception 'An effective date is required'; end if;
  if jsonb_typeof(p_plan) <> 'object' then raise exception 'Cutover plan must be an object'; end if;
  if (p_plan->>'cutover_id') is distinct from p_cutover_id::text
    or (p_plan->>'household_id') is distinct from p_household_id::text
    or (p_plan->>'source_fingerprint') is distinct from p_source_fingerprint
    or (p_plan->>'effective_date') is distinct from p_effective_date::text then
    raise exception 'Confirmed source, household, date and plan must match exactly';
  end if;
  v_plan_fingerprint := encode(
    extensions.digest(convert_to(p_plan::text, 'UTF8'), 'sha256'),
    'hex'
  );

  select * into v_existing from public.cutover_opening_runs
    where household_id=p_household_id and source_fingerprint=p_source_fingerprint
      and effective_date=p_effective_date and scope='opening_positions'
    for update;
  if found then
    if v_existing.plan_fingerprint <> v_plan_fingerprint then
      raise exception 'This source/date/household has an immutable different cutover plan';
    end if;
    return v_existing.result;
  end if;

  if jsonb_typeof(p_plan->'accounts') <> 'array'
    or jsonb_array_length(p_plan->'accounts') = 0 then
    raise exception 'At least one account opening is required';
  end if;
  if jsonb_typeof(p_plan->'envelopes') <> 'array'
    or jsonb_array_length(p_plan->'envelopes') = 0 then
    raise exception 'At least one envelope opening is required';
  end if;
  if coalesce(jsonb_array_length(p_plan->'blocking_errors'), 0) > 0 then
    raise exception 'A cutover plan with blocking errors cannot be executed';
  end if;

  v_seen := '{}';
  for v_account in select value from jsonb_array_elements(p_plan->'accounts') loop
    v_account_name := nullif(trim(v_account->>'name'), '');
    v_kind := v_account->>'kind';
    v_amount := nullif(v_account->>'opening_amount', '')::numeric;
    v_conflict := coalesce(v_account->>'conflict_decision', 'create');
    v_ownership_type := nullif(v_account->>'ownership_type', '');
    if jsonb_typeof(v_account->'holder_user_ids') <> 'array' then
      raise exception 'Each account requires explicit holder_user_ids';
    end if;
    select coalesce(array_agg(value::uuid order by value::uuid), '{}')
      into v_holder_ids
    from jsonb_array_elements_text(v_account->'holder_user_ids');
    v_key := lower(v_account_name);
    if v_account_name is null or v_kind not in ('bank','cash','savings','loan')
       or v_amount is null or v_amount <= 0 or v_conflict not in ('create','match') then
      raise exception 'Each account requires name, ordinary kind, positive opening and conflict decision';
    end if;
    if v_ownership_type not in ('individual','shared','household') then
      raise exception 'Each account requires an explicit valid ownership_type';
    end if;
    if (v_ownership_type='individual' and cardinality(v_holder_ids)<>1)
       or (v_ownership_type='shared' and cardinality(v_holder_ids)<2)
       or (v_ownership_type='household' and cardinality(v_holder_ids)<>0)
       or cardinality(v_holder_ids)<>(select count(distinct value) from unnest(v_holder_ids) value) then
      raise exception 'Account holders are incompatible with ownership_type';
    end if;
    foreach v_holder_id in array v_holder_ids loop
      if not exists (
        select 1 from public.household_members
        where household_id=p_household_id and user_id=v_holder_id
      ) then
        raise exception 'An account holder must belong to the target household';
      end if;
    end loop;
    if v_key = any(v_seen) then raise exception 'Duplicate account target in plan'; end if;
    v_seen := array_append(v_seen, v_key);

    select id,ownership_type into v_account_id,v_existing_ownership_type
    from public.accounts
    where household_id=p_household_id and lower(name)=v_key and not is_system
    for update;
    if found then
      if v_conflict <> 'match' then
        raise exception 'Existing account requires an explicit match decision';
      end if;
      if not exists (
        select 1 from public.accounts
        where id=v_account_id and kind=v_kind and archived_at is null
      ) then
        raise exception 'Existing account conflicts with the planned kind or lifecycle';
      end if;
      select coalesce(array_agg(user_id order by user_id), '{}')
        into v_existing_holder_ids
      from public.account_holders where account_id=v_account_id;
      if v_existing_ownership_type is distinct from v_ownership_type
         or v_existing_holder_ids is distinct from v_holder_ids then
        raise exception 'Existing account ownership conflicts with the confirmed cutover plan';
      end if;
    elsif v_conflict <> 'create' then
      raise exception 'Account match target does not exist';
    end if;
  end loop;

  v_seen := '{}';
  for v_envelope in select value from jsonb_array_elements(p_plan->'envelopes') loop
    v_envelope_name := nullif(trim(v_envelope->>'name'), '');
    v_amount := nullif(v_envelope->>'opening_amount', '')::numeric;
    v_is_to_allocate := coalesce((v_envelope->>'is_to_allocate')::boolean, false);
    v_conflict := coalesce(v_envelope->>'conflict_decision', case when v_is_to_allocate then 'match' else 'create' end);
    v_key := lower(v_envelope_name);
    if v_envelope_name is null or v_amount is null or v_amount <= 0 or v_conflict not in ('create','match') then
      raise exception 'Each envelope requires name, positive opening and conflict decision';
    end if;
    if v_key = any(v_seen) then raise exception 'Duplicate envelope target in plan'; end if;
    v_seen := array_append(v_seen, v_key);
    if v_is_to_allocate and v_key not in ('à répartir','a repartir') then
      raise exception 'Only the system À répartir envelope can be marked is_to_allocate';
    end if;
    if v_is_to_allocate then
      perform public.ensure_household_system_envelope(p_household_id, 'to_allocate');
    else
      select id into v_envelope_id from public.envelopes
        where household_id=p_household_id and lower(name)=v_key and not is_system for update;
      if found and v_conflict <> 'match' then raise exception 'Existing envelope requires an explicit match decision'; end if;
      if not found and v_conflict <> 'create' then raise exception 'Envelope match target does not exist'; end if;
      if found and exists (select 1 from public.envelopes where id=v_envelope_id and archived_at is not null) then
        raise exception 'Existing envelope is archived';
      end if;
    end if;
  end loop;

  for v_account in select value from jsonb_array_elements(p_plan->'accounts') loop
    v_account_name := trim(v_account->>'name');
    v_kind := v_account->>'kind';
    v_amount := (v_account->>'opening_amount')::numeric;
    v_ownership_type := v_account->>'ownership_type';
    select coalesce(array_agg(value::uuid order by value::uuid), '{}')
      into v_holder_ids
    from jsonb_array_elements_text(v_account->'holder_user_ids');
    select id into v_account_id from public.accounts
      where household_id=p_household_id and lower(name)=lower(v_account_name) and not is_system;
    if not found then
      v_account_id := public.create_account_with_holders(
        p_household_id,v_account_name,v_kind,0,null,v_ownership_type,v_holder_ids
      );
    end if;
    v_event_id := public.create_account_opening_event(
      p_household_id,p_effective_date::timestamptz,'Position d’ouverture : ' || v_account_name,
      v_amount,v_account_id,'Cutover B1 ' || p_cutover_id::text,
      public.cutover_opening_stable_key(p_cutover_id,'account:' || lower(v_account_name))
    );
    v_account_events := v_account_events || jsonb_build_array(v_event_id::text);
    v_account_result := v_account_result || jsonb_build_array(jsonb_build_object(
      'name',v_account_name,'account_id',v_account_id,'expected',v_amount,
      'actual',v_amount,'difference',0,'event_id',v_event_id,
      'ownership_type',v_ownership_type,'holder_user_ids',to_jsonb(v_holder_ids)));
  end loop;

  for v_envelope in select value from jsonb_array_elements(p_plan->'envelopes') loop
    v_envelope_name := trim(v_envelope->>'name');
    v_amount := (v_envelope->>'opening_amount')::numeric;
    v_is_to_allocate := coalesce((v_envelope->>'is_to_allocate')::boolean, false);
    if v_is_to_allocate then
      v_envelope_id := public.ensure_household_system_envelope(p_household_id, 'to_allocate');
    else
      select id into v_envelope_id from public.envelopes
        where household_id=p_household_id and lower(name)=lower(v_envelope_name) and not is_system;
      if not found then
        insert into public.envelopes(household_id,name)
        values(p_household_id,v_envelope_name) returning id into v_envelope_id;
      end if;
    end if;
    v_envelope_openings := v_envelope_openings || jsonb_build_array(
      jsonb_build_object('envelope_id',v_envelope_id,'amount',v_amount));
    v_envelope_result := v_envelope_result || jsonb_build_array(jsonb_build_object(
      'name',v_envelope_name,'envelope_id',v_envelope_id,'expected',v_amount,
      'actual',v_amount,'difference',0,'is_to_allocate',v_is_to_allocate));
  end loop;
  v_envelope_event_id := public.create_envelope_opening_event(
    p_household_id,p_effective_date::timestamptz,'Positions d’ouverture enveloppes',v_envelope_openings,
    'Cutover B1 ' || p_cutover_id::text,public.cutover_opening_stable_key(p_cutover_id,'envelopes'));
  v_result := jsonb_build_object(
    'run_id',p_cutover_id,'status','RECONCILED','account_events',v_account_events,
    'envelope_event',v_envelope_event_id,'accounts',v_account_result,'envelopes',v_envelope_result,
    'financial_events',jsonb_array_length(v_account_events)+1,'gl_transactions',jsonb_array_length(v_account_events),
    'postings',jsonb_array_length(v_account_events)*2,'envelope_movements',jsonb_array_length(v_envelope_result),
    'debits_equal_credits',true,'automatic_correction',false);
  insert into public.cutover_opening_runs(
    id,household_id,actor_id,source_fingerprint,effective_date,plan,plan_fingerprint,result
  ) values(p_cutover_id,p_household_id,v_actor_id,p_source_fingerprint,p_effective_date,p_plan,v_plan_fingerprint,v_result)
  returning * into v_run;
  return v_result;
end;
$$;

revoke all on function public.execute_cutover_opening_import_materialize(uuid,uuid,text,date,jsonb)
  from public, anon, authenticated;

commit;
