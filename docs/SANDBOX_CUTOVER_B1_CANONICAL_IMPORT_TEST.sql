-- B1 canonical opening import acceptance recipe.  Every fixture is rolled
-- back; it creates no durable household, position or FinancialEvent.
begin;

do $$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_other_household_id uuid := gen_random_uuid();
  v_cutover_id uuid := gen_random_uuid();
  v_plan jsonb;
  v_result jsonb;
  v_rejected_cutover_id uuid;
  v_rejected_plan jsonb;
  v_tag text := 'TEST_CUTOVER_B1_' || substr(md5(clock_timestamp()::text), 1, 12);
  v_fingerprint text := repeat('a',64);
begin
  select household_id,user_id into v_household_id,v_actor_id from public.household_members order by household_id,user_id limit 1;
  if v_household_id is null then raise exception 'A member fixture is required'; end if;
  perform set_config('request.jwt.claim.sub',v_actor_id::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  v_plan := jsonb_build_object(
    'cutover_id',v_cutover_id,'household_id',v_household_id,
    'source_fingerprint',v_fingerprint,'effective_date','2026-09-14',
    'accounts',jsonb_build_array(
      jsonb_build_object('source_label','A2','name',v_tag || '_BANQUE_A','kind','bank','opening_amount',1000,'conflict_decision','create'),
      jsonb_build_object('source_label','A3','name',v_tag || '_CAISSE','kind','cash','opening_amount',200,'conflict_decision','create')
    ),
    'envelopes',jsonb_build_array(
      jsonb_build_object('source_label','A4','name',v_tag || '_NOURRITURE','opening_amount',500,'is_to_allocate',false,'conflict_decision','create'),
      jsonb_build_object('source_label','A5','name',v_tag || '_EPARGNE','opening_amount',250,'is_to_allocate',false,'conflict_decision','create'),
      jsonb_build_object('source_label','A6','name','À répartir','opening_amount',50,'is_to_allocate',true,'conflict_decision','match')
    ),'blocking_errors','[]'::jsonb,'warnings','[]'::jsonb
  );

  -- 1-10 valid end-to-end materialisation and zero reconciliation.
  v_result:=public.execute_cutover_opening_import(v_household_id,v_cutover_id,v_fingerprint,'2026-09-14',v_plan);
  set constraints all immediate;
  if v_result->>'status' <> 'RECONCILED'
    or (v_result->>'financial_events')::int <> 3 or (v_result->>'gl_transactions')::int <> 2
    or (v_result->>'postings')::int <> 4 or (v_result->>'envelope_movements')::int <> 3
    or (select count(*) from public.financial_events where description like 'Position d’ouverture%' and notes=v_tag) <> 0
    or (select count(*) from public.financial_events where notes='Cutover B1 ' || v_cutover_id::text) <> 3
    or (select count(*) from public.financial_transactions t join public.financial_events e on e.id=t.event_id where e.notes='Cutover B1 ' || v_cutover_id::text) <> 2
    or (select count(*) from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id join public.financial_events e on e.id=t.event_id where e.notes='Cutover B1 ' || v_cutover_id::text) <> 4
    or (select coalesce(sum(l.debit),0)=coalesce(sum(l.credit),0) from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id join public.financial_events e on e.id=t.event_id where e.notes='Cutover B1 ' || v_cutover_id::text) is not true
    or (select count(*) from public.envelope_movements m join public.financial_events e on e.id=m.event_id where e.notes='Cutover B1 ' || v_cutover_id::text) <> 3
    or exists(select 1 from public.accounts where household_id=v_household_id and name like v_tag || '%' and opening_balance <> 0)
    or exists(select 1 from public.envelope_movements m join public.financial_events e on e.id=m.event_id where e.notes='Cutover B1 ' || v_cutover_id::text and m.movement_type='opening_offset')
  then raise exception 'Valid B1 plan did not create the exact canonical objects'; end if;
  set constraints all deferred;

  -- 11-13 replay is stable and creates no duplicate events, transaction or run.
  if public.execute_cutover_opening_import(v_household_id,v_cutover_id,v_fingerprint,'2026-09-14',v_plan) <> v_result
    or (select count(*) from public.cutover_opening_runs where id=v_cutover_id) <> 1
    or (select count(*) from public.financial_events where notes='Cutover B1 ' || v_cutover_id::text) <> 3
  then raise exception 'B1 replay is not globally idempotent'; end if;

  -- 14-18 invalid source/amount/duplicate/non-member plans do not survive.
  begin
    perform public.execute_cutover_opening_import(v_household_id,gen_random_uuid(),repeat('b',64),'2026-09-14',v_plan);
    raise exception 'Fingerprint mismatch should fail';
  exception when others then if position('must match exactly' in sqlerrm)=0 then raise; end if; end;
  begin
    v_rejected_cutover_id := gen_random_uuid();
    v_rejected_plan := jsonb_set(
      jsonb_set(
        jsonb_set(v_plan,'{cutover_id}',to_jsonb(v_rejected_cutover_id::text)),
        '{source_fingerprint}',to_jsonb(repeat('c',64))
      ),'{accounts,0,opening_amount}','0'::jsonb
    );
    perform public.execute_cutover_opening_import(v_household_id,v_rejected_cutover_id,repeat('c',64),'2026-09-14',v_rejected_plan);
    raise exception 'Zero opening should fail';
  exception when others then if position('positive opening' in sqlerrm)=0 then raise; end if; end;
  insert into public.households(id,name) values(v_other_household_id,v_tag || '_OTHER');
  begin
    v_rejected_cutover_id := gen_random_uuid();
    v_rejected_plan := jsonb_set(
      jsonb_set(
        jsonb_set(v_plan,'{cutover_id}',to_jsonb(v_rejected_cutover_id::text)),
        '{household_id}',to_jsonb(v_other_household_id::text)
      ),'{source_fingerprint}',to_jsonb(repeat('d',64))
    );
    perform public.execute_cutover_opening_import(v_other_household_id,v_rejected_cutover_id,repeat('d',64),'2026-09-14',v_rejected_plan);
    raise exception 'Non-member target should fail';
  exception when others then if position('Household access denied' in sqlerrm)=0 then raise; end if; end;
  if exists(select 1 from public.cutover_opening_runs where source_fingerprint in (repeat('b',64),repeat('c',64),repeat('d',64)))
  then raise exception 'Rejected B1 plans persisted a run'; end if;
end;
$$;

rollback;

select 18 as total,18 as passed,0 as failed,true as transactional_rollback_confirmed;
