-- Allow Cutover opening plans to create zero-balance envelope references.
-- Zero balances are referential only: they never create FinancialEvents or
-- envelope movements. Positive openings continue to use Cutover A.
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
    extensions.digest(convert_to(p_plan::text, 'UTF8'), 'sha256'), 'hex'
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
    raise exception 'At least one envelope reference is required';
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
      into v_holder_ids from jsonb_array_elements_text(v_account->'holder_user_ids');
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
      if not exists (select 1 from public.household_members
        where household_id=p_household_id and user_id=v_holder_id) then
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
      if v_conflict <> 'match' then raise exception 'Existing account requires an explicit match decision'; end if;
      if not exists (select 1 from public.accounts
        where id=v_account_id and kind=v_kind and archived_at is null) then
        raise exception 'Existing account conflicts with the planned kind or lifecycle';
      end if;
      select coalesce(array_agg(user_id order by user_id), '{}')
        into v_existing_holder_ids from public.account_holders where account_id=v_account_id;
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
    v_conflict := coalesce(v_envelope->>'conflict_decision', 'create');
    v_key := lower(v_envelope_name);
    if v_envelope_name is null or v_amount is null or v_amount < 0
       or v_conflict not in ('create','match') then
      raise exception 'Each envelope requires name, non-negative opening and conflict decision';
    end if;
    if v_key = any(v_seen) then raise exception 'Duplicate envelope target in plan'; end if;
    v_seen := array_append(v_seen, v_key);
    if v_is_to_allocate and v_key not in ('à répartir','a repartir') then
      raise exception 'Only the system À répartir envelope can be marked is_to_allocate';
    end if;
    if v_is_to_allocate then
      select id into v_envelope_id from public.envelopes
      where household_id=p_household_id and system_code='to_allocate' for update;
      if found and v_conflict <> 'match' then
        raise exception 'Existing system envelope requires an explicit match decision';
      elsif not found and v_conflict <> 'create' then
        raise exception 'System envelope match target does not exist';
      end if;
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
      into v_holder_ids from jsonb_array_elements_text(v_account->'holder_user_ids');
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
    if v_amount > 0 then
      v_envelope_openings := v_envelope_openings || jsonb_build_array(
        jsonb_build_object('envelope_id',v_envelope_id,'amount',v_amount));
    end if;
    v_envelope_result := v_envelope_result || jsonb_build_array(jsonb_build_object(
      'name',v_envelope_name,'envelope_id',v_envelope_id,'expected',v_amount,
      'actual',v_amount,'difference',0,'is_to_allocate',v_is_to_allocate));
  end loop;

  if jsonb_array_length(v_envelope_openings) > 0 then
    v_envelope_event_id := public.create_envelope_opening_event(
      p_household_id,p_effective_date::timestamptz,'Positions d’ouverture enveloppes',v_envelope_openings,
      'Cutover B1 ' || p_cutover_id::text,public.cutover_opening_stable_key(p_cutover_id,'envelopes'));
  end if;

  v_result := jsonb_build_object(
    'run_id',p_cutover_id,'status','RECONCILED','account_events',v_account_events,
    'envelope_event',v_envelope_event_id,'accounts',v_account_result,'envelopes',v_envelope_result,
    'financial_events',jsonb_array_length(v_account_events) + case when v_envelope_event_id is null then 0 else 1 end,
    'gl_transactions',jsonb_array_length(v_account_events),
    'postings',jsonb_array_length(v_account_events)*2,
    'envelope_movements',jsonb_array_length(v_envelope_openings),
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

create or replace function public.reconcile_cutover_opening_run(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_run public.cutover_opening_runs%rowtype;
  v_account jsonb;
  v_envelope jsonb;
  v_accounts jsonb := '[]'::jsonb;
  v_envelopes jsonb := '[]'::jsonb;
  v_actual numeric;
  v_ledger_balance numeric;
  v_expected numeric;
  v_account_ok boolean := true;
  v_envelope_ok boolean := true;
  v_event_ids uuid[] := '{}';
  v_event_count int;
  v_transaction_count int;
  v_posting_count int;
  v_envelope_movement_count int;
  v_debits numeric;
  v_credits numeric;
  v_balanced boolean;
  v_status text;
  v_envelope_event_id uuid;
begin
  select * into v_run from public.cutover_opening_runs where id=p_run_id for update;
  if not found then raise exception 'Cutover run not found'; end if;
  perform public.assert_household_access(v_run.household_id);

  for v_account in select value from jsonb_array_elements(v_run.result->'accounts') loop
    v_expected := (v_account->>'expected')::numeric;
    select coalesce(sum(lines.debit-lines.credit),0) into v_actual
    from public.financial_transactions transactions
    join public.financial_transaction_lines lines on lines.transaction_id=transactions.id
    where transactions.event_id=(v_account->>'event_id')::uuid
      and lines.account_id=(v_account->>'account_id')::uuid;
    select ledger_balance into v_ledger_balance from public.account_ledger_balances
      where account_id=(v_account->>'account_id')::uuid;
    v_accounts := v_accounts || jsonb_build_array(v_account || jsonb_build_object(
      'actual',v_actual,'ledger_balance',coalesce(v_ledger_balance,0),'difference',v_actual-v_expected));
    v_account_ok := v_account_ok and v_actual=v_expected;
    v_event_ids := array_append(v_event_ids,(v_account->>'event_id')::uuid);
  end loop;

  v_envelope_event_id := nullif(v_run.result->>'envelope_event','')::uuid;
  if v_envelope_event_id is not null then
    v_event_ids := array_append(v_event_ids,v_envelope_event_id);
  end if;
  for v_envelope in select value from jsonb_array_elements(v_run.result->'envelopes') loop
    v_expected := (v_envelope->>'expected')::numeric;
    select coalesce(sum(case when direction='inflow' then amount else -amount end),0) into v_actual
    from public.envelope_movements
    where event_id=v_envelope_event_id and envelope_id=(v_envelope->>'envelope_id')::uuid;
    select balance into v_ledger_balance from public.envelope_ledger_balances
      where envelope_id=(v_envelope->>'envelope_id')::uuid;
    v_envelopes := v_envelopes || jsonb_build_array(v_envelope || jsonb_build_object(
      'actual',v_actual,'ledger_balance',coalesce(v_ledger_balance,0),'difference',v_actual-v_expected));
    v_envelope_ok := v_envelope_ok and v_actual=v_expected;
  end loop;

  select count(*) into v_event_count from public.financial_events where id=any(v_event_ids);
  select count(*) into v_transaction_count from public.financial_transactions where event_id=any(v_event_ids);
  select count(*),coalesce(sum(lines.debit),0),coalesce(sum(lines.credit),0)
    into v_posting_count,v_debits,v_credits
  from public.financial_transaction_lines lines
  join public.financial_transactions transactions on transactions.id=lines.transaction_id
  where transactions.event_id=any(v_event_ids);
  select count(*) into v_envelope_movement_count from public.envelope_movements
    where event_id=v_envelope_event_id;
  v_balanced := v_debits=v_credits;
  v_status := case when v_account_ok and v_envelope_ok
      and v_event_count=(v_run.result->>'financial_events')::int
      and v_transaction_count=(v_run.result->>'gl_transactions')::int
      and v_posting_count=(v_run.result->>'postings')::int
      and v_envelope_movement_count=(v_run.result->>'envelope_movements')::int
      and v_balanced then 'RECONCILED' else 'NOT_RECONCILED' end;
  return jsonb_build_object(
    'run_id',v_run.id,'status',v_status,
    'account_events',v_run.result->'account_events','envelope_event',v_envelope_event_id,
    'accounts',v_accounts,'envelopes',v_envelopes,
    'financial_events',v_event_count,'gl_transactions',v_transaction_count,
    'postings',v_posting_count,'envelope_movements',v_envelope_movement_count,
    'debits',v_debits,'credits',v_credits,'debits_equal_credits',v_balanced,
    'automatic_correction',false);
end;
$$;

revoke all on function public.reconcile_cutover_opening_run(uuid) from public, anon;

-- A missing system envelope is a valid explicit create decision for a new
-- household. Existing system envelopes remain explicit matches.
create or replace function public.execute_cutover_opening_import(
  p_household_id uuid,p_cutover_id uuid,p_source_fingerprint text,
  p_effective_date date,p_plan jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_account jsonb;
  v_envelope jsonb;
  v_expected_id uuid;
  v_materialized jsonb;
  v_run_id uuid;
  v_reconciled jsonb;
  v_is_to_allocate boolean;
  v_decision text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.assert_household_access(p_household_id);
  if exists (select 1 from public.cutover_opening_runs
    where household_id=p_household_id and source_fingerprint=p_source_fingerprint
      and effective_date=p_effective_date and scope='opening_positions') then
    v_materialized := public.execute_cutover_opening_import_materialize(
      p_household_id,p_cutover_id,p_source_fingerprint,p_effective_date,p_plan);
    v_run_id := (v_materialized->>'run_id')::uuid;
    v_reconciled := public.reconcile_cutover_opening_run(v_run_id);
    update public.cutover_opening_runs set result=v_reconciled where id=v_run_id;
    return v_reconciled;
  end if;

  for v_account in select value from jsonb_array_elements(p_plan->'accounts') loop
    if v_account->>'conflict_decision'='conflict' then
      raise exception 'A conflicting account reference cannot be materialized';
    elsif v_account->>'conflict_decision'='match' then
      v_expected_id := nullif(v_account->>'matched_account_id','')::uuid;
      if v_expected_id is null then raise exception 'An account match requires matched_account_id'; end if;
      if not exists (select 1 from public.accounts where id=v_expected_id
        and household_id=p_household_id and lower(name)=lower(v_account->>'name') and not is_system) then
        raise exception 'The confirmed matched_account_id is not the planned account';
      end if;
      if (select count(*) from public.accounts where household_id=p_household_id
        and lower(name)=lower(v_account->>'name') and not is_system)<>1 then
        raise exception 'The account name does not identify exactly one confirmed reference';
      end if;
      perform 1 from public.accounts where id=v_expected_id for update;
    elsif v_account ? 'matched_account_id' then
      raise exception 'An account create decision cannot carry matched_account_id';
    end if;
  end loop;

  for v_envelope in select value from jsonb_array_elements(p_plan->'envelopes') loop
    v_is_to_allocate := coalesce((v_envelope->>'is_to_allocate')::boolean,false);
    v_decision := coalesce(v_envelope->>'conflict_decision','create');
    if v_envelope->>'reference_conflict' is not null or v_decision='conflict' then
      raise exception 'A conflicting envelope reference cannot be materialized';
    elsif v_decision='match' then
      v_expected_id := nullif(v_envelope->>'matched_envelope_id','')::uuid;
      if v_expected_id is null then raise exception 'An envelope match requires matched_envelope_id'; end if;
      if not exists (select 1 from public.envelopes where id=v_expected_id
        and household_id=p_household_id and ((v_is_to_allocate and is_system and system_code='to_allocate')
          or (not v_is_to_allocate and not is_system and lower(name)=lower(v_envelope->>'name')))) then
        raise exception 'The confirmed matched_envelope_id is not the planned envelope';
      end if;
      if not v_is_to_allocate and (select count(*) from public.envelopes
        where household_id=p_household_id and not is_system
          and lower(name)=lower(v_envelope->>'name'))<>1 then
        raise exception 'The envelope name does not identify exactly one confirmed reference';
      end if;
      perform 1 from public.envelopes where id=v_expected_id for update;
    elsif v_envelope ? 'matched_envelope_id' then
      raise exception 'An envelope create decision cannot carry matched_envelope_id';
    end if;
  end loop;

  v_materialized := public.execute_cutover_opening_import_materialize(
    p_household_id,p_cutover_id,p_source_fingerprint,p_effective_date,p_plan);
  v_run_id := (v_materialized->>'run_id')::uuid;
  v_reconciled := public.reconcile_cutover_opening_run(v_run_id);
  update public.cutover_opening_runs set result=v_reconciled where id=v_run_id;
  return v_reconciled;
end;
$$;

revoke all on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)
  from public, anon;
grant execute on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)
  to authenticated;
grant execute on function public.reconcile_cutover_opening_run(uuid)
  to authenticated;

commit;
