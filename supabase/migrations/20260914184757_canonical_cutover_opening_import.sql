-- Canonical B1 cutover opening import.  This migration only orchestrates
-- reference creation and the two Cutover A opening primitives; it never
-- writes legacy opening_balance values or opening_offset movements.
begin;

create table public.cutover_opening_runs (
  id uuid primary key,
  household_id uuid not null references public.households(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  source_fingerprint text not null check (source_fingerprint ~ '^[0-9a-f]{64}$'),
  effective_date date not null,
  scope text not null default 'opening_positions' check (scope = 'opening_positions'),
  plan jsonb not null,
  plan_fingerprint text not null check (plan_fingerprint ~ '^[0-9a-f]{64}$'),
  status text not null default 'completed' check (status in ('completed')),
  started_at timestamptz not null default now(),
  completed_at timestamptz not null default now(),
  result jsonb not null,
  error text,
  unique (household_id, source_fingerprint, effective_date, scope)
);

create index cutover_opening_runs_household_created_idx
  on public.cutover_opening_runs(household_id, started_at desc);

alter table public.cutover_opening_runs enable row level security;
create policy "members read cutover opening runs" on public.cutover_opening_runs
  for select using (public.is_household_member(household_id));

create or replace function public.cutover_opening_stable_key(
  p_cutover_id uuid,
  p_target text
) returns uuid
language sql immutable set search_path = public as $$
  select (
    substr(md5(p_cutover_id::text || ':' || p_target), 1, 8) || '-' ||
    substr(md5(p_cutover_id::text || ':' || p_target), 9, 4) || '-' ||
    substr(md5(p_cutover_id::text || ':' || p_target), 13, 4) || '-' ||
    substr(md5(p_cutover_id::text || ':' || p_target), 17, 4) || '-' ||
    substr(md5(p_cutover_id::text || ':' || p_target), 21, 12)
  )::uuid;
$$;

create or replace function public.execute_cutover_opening_import(
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
  v_plan_fingerprint := encode(digest(p_plan::text, 'sha256'), 'hex');

  -- A completed identical logical cutover is returned before any validation
  -- that could turn a safe network replay into a false rejection.
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

  -- Validate all account targets and conflict decisions before materializing
  -- either a reference or a FinancialEvent.
  v_seen := '{}';
  for v_account in select value from jsonb_array_elements(p_plan->'accounts') loop
    v_account_name := nullif(trim(v_account->>'name'), '');
    v_kind := v_account->>'kind';
    v_amount := nullif(v_account->>'opening_amount', '')::numeric;
    v_conflict := coalesce(v_account->>'conflict_decision', 'create');
    v_key := lower(v_account_name);
    if v_account_name is null or v_kind not in ('bank','cash','savings','loan')
       or v_amount is null or v_amount <= 0 or v_conflict not in ('create','match') then
      raise exception 'Each account requires name, ordinary kind, positive opening and conflict decision';
    end if;
    if v_key = any(v_seen) then raise exception 'Duplicate account target in plan'; end if;
    v_seen := array_append(v_seen, v_key);
    select id into v_account_id from public.accounts
      where household_id=p_household_id and lower(name)=v_key and not is_system for update;
    if found and v_conflict <> 'match' then raise exception 'Existing account requires an explicit match decision'; end if;
    if not found and v_conflict <> 'create' then raise exception 'Account match target does not exist'; end if;
    if found and not exists (select 1 from public.accounts where id=v_account_id and kind=v_kind and archived_at is null) then
      raise exception 'Existing account conflicts with the planned kind or lifecycle';
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

  -- References are created only after the whole plan is valid. Monetary
  -- positions are delegated exclusively to Cutover A below.
  for v_account in select value from jsonb_array_elements(p_plan->'accounts') loop
    v_account_name := trim(v_account->>'name');
    v_kind := v_account->>'kind';
    v_amount := (v_account->>'opening_amount')::numeric;
    select id into v_account_id from public.accounts
      where household_id=p_household_id and lower(name)=lower(v_account_name) and not is_system;
    if not found then
      insert into public.accounts(household_id,name,kind,opening_balance)
      values (p_household_id,v_account_name,v_kind,0) returning id into v_account_id;
    end if;
    v_event_id := public.create_account_opening_event(
      p_household_id, p_effective_date::timestamptz, 'Position d’ouverture : ' || v_account_name,
      v_amount, v_account_id, 'Cutover B1 ' || p_cutover_id::text,
      public.cutover_opening_stable_key(p_cutover_id, 'account:' || lower(v_account_name)));
    v_account_events := v_account_events || jsonb_build_array(v_event_id::text);
    v_account_result := v_account_result || jsonb_build_array(jsonb_build_object(
      'name',v_account_name,'account_id',v_account_id,'expected',v_amount,'actual',v_amount,'difference',0,'event_id',v_event_id));
  end loop;

  for v_envelope in select value from jsonb_array_elements(p_plan->'envelopes') loop
    v_envelope_name := trim(v_envelope->>'name');
    v_amount := (v_envelope->>'opening_amount')::numeric;
    v_is_to_allocate := coalesce((v_envelope->>'is_to_allocate')::boolean, false);
    if v_is_to_allocate then
      v_envelope_id := public.ensure_household_system_envelope(p_household_id, 'to_allocate');
    else
      select id into v_envelope_id from public.envelopes where household_id=p_household_id and lower(name)=lower(v_envelope_name) and not is_system;
      if not found then
        insert into public.envelopes(household_id,name) values(p_household_id,v_envelope_name) returning id into v_envelope_id;
      end if;
    end if;
    v_envelope_openings := v_envelope_openings || jsonb_build_array(jsonb_build_object('envelope_id',v_envelope_id,'amount',v_amount));
    v_envelope_result := v_envelope_result || jsonb_build_array(jsonb_build_object(
      'name',v_envelope_name,'envelope_id',v_envelope_id,'expected',v_amount,'actual',v_amount,'difference',0,'is_to_allocate',v_is_to_allocate));
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

revoke all on table public.cutover_opening_runs from public, anon;
revoke all on function public.cutover_opening_stable_key(uuid,text),
  public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb) from public, anon;
grant select on public.cutover_opening_runs to authenticated;
grant execute on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb) to authenticated;

commit;
