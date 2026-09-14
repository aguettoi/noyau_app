-- B1 P1 correction: canonical read-only reconciliation, logical-run lookup
-- and removal of the temporary public digest overload.
begin;

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)'::regprocedure
  ) into v_definition;
  v_definition := replace(
    v_definition,
    'digest(p_plan::text, ''sha256'')',
    'extensions.digest(convert_to(p_plan::text, ''UTF8''), ''sha256'')'
  );
  if v_definition not like '%extensions.digest(convert_to(p_plan::text, ''UTF8''), ''sha256'')%' then
    raise exception 'Cutover B1 digest replacement was not applied';
  end if;
  execute v_definition;
end;
$$;

alter function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)
  rename to execute_cutover_opening_import_materialize;
revoke all on function public.execute_cutover_opening_import_materialize(uuid,uuid,text,date,jsonb)
  from public, anon, authenticated;

create or replace function public.reconcile_cutover_opening_run(p_run_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
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
begin
  select * into v_run from public.cutover_opening_runs where id=p_run_id for update;
  if not found then raise exception 'Cutover run not found'; end if;
  perform public.assert_household_access(v_run.household_id);

  for v_account in select value from jsonb_array_elements(v_run.result->'accounts') loop
    v_expected := (v_account->>'expected')::numeric;
    select coalesce(sum(lines.debit - lines.credit),0) into v_actual
    from public.financial_transactions transactions
    join public.financial_transaction_lines lines on lines.transaction_id=transactions.id
    where transactions.event_id=(v_account->>'event_id')::uuid
      and lines.account_id=(v_account->>'account_id')::uuid;
    select ledger_balance into v_ledger_balance
    from public.account_ledger_balances
    where account_id=(v_account->>'account_id')::uuid;
    v_accounts := v_accounts || jsonb_build_array(v_account || jsonb_build_object(
      'actual',v_actual,'ledger_balance',coalesce(v_ledger_balance,0),
      'difference',v_actual-v_expected));
    v_account_ok := v_account_ok and v_actual=v_expected;
    v_event_ids := array_append(v_event_ids,(v_account->>'event_id')::uuid);
  end loop;
  v_event_ids := array_append(v_event_ids,(v_run.result->>'envelope_event')::uuid);

  for v_envelope in select value from jsonb_array_elements(v_run.result->'envelopes') loop
    v_expected := (v_envelope->>'expected')::numeric;
    select coalesce(sum(case when direction='inflow' then amount else -amount end),0) into v_actual
    from public.envelope_movements
    where event_id=(v_run.result->>'envelope_event')::uuid
      and envelope_id=(v_envelope->>'envelope_id')::uuid;
    select balance into v_ledger_balance
    from public.envelope_ledger_balances
    where envelope_id=(v_envelope->>'envelope_id')::uuid;
    v_envelopes := v_envelopes || jsonb_build_array(v_envelope || jsonb_build_object(
      'actual',v_actual,'ledger_balance',coalesce(v_ledger_balance,0),
      'difference',v_actual-v_expected));
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
    where event_id=(v_run.result->>'envelope_event')::uuid;
  v_balanced := v_debits=v_credits;
  v_status := case when v_account_ok and v_envelope_ok
      and v_event_count=(v_run.result->>'financial_events')::int
      and v_transaction_count=(v_run.result->>'gl_transactions')::int
      and v_posting_count=(v_run.result->>'postings')::int
      and v_envelope_movement_count=(v_run.result->>'envelope_movements')::int
      and v_balanced then 'RECONCILED' else 'NOT_RECONCILED' end;
  return jsonb_build_object(
    'run_id',v_run.id,'status',v_status,
    'account_events',v_run.result->'account_events','envelope_event',v_run.result->'envelope_event',
    'accounts',v_accounts,'envelopes',v_envelopes,
    'financial_events',v_event_count,'gl_transactions',v_transaction_count,
    'postings',v_posting_count,'envelope_movements',v_envelope_movement_count,
    'debits',v_debits,'credits',v_credits,'debits_equal_credits',v_balanced,
    'automatic_correction',false
  );
end;
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
  v_materialized jsonb;
  v_run_id uuid;
  v_reconciled jsonb;
begin
  v_materialized := public.execute_cutover_opening_import_materialize(
    p_household_id,p_cutover_id,p_source_fingerprint,p_effective_date,p_plan);
  v_run_id := (v_materialized->>'run_id')::uuid;
  v_reconciled := public.reconcile_cutover_opening_run(v_run_id);
  update public.cutover_opening_runs set result=v_reconciled where id=v_run_id;
  return v_reconciled;
end;
$$;

create or replace function public.get_cutover_opening_run(
  p_household_id uuid,
  p_source_fingerprint text,
  p_effective_date date
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_run public.cutover_opening_runs%rowtype;
begin
  perform public.assert_household_access(p_household_id);
  select * into v_run from public.cutover_opening_runs
    where household_id=p_household_id and source_fingerprint=p_source_fingerprint
      and effective_date=p_effective_date and scope='opening_positions';
  if not found then return null; end if;
  return jsonb_build_object('id',v_run.id,'status',v_run.status,'plan',v_run.plan,
    'result',v_run.result,'started_at',v_run.started_at,'completed_at',v_run.completed_at);
end;
$$;

drop function public.digest(text,text);
revoke all on function public.reconcile_cutover_opening_run(uuid) from public, anon;
revoke all on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb),
  public.get_cutover_opening_run(uuid,text,date) from public, anon;
grant execute on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb),
  public.get_cutover_opening_run(uuid,text,date) to authenticated;

commit;
