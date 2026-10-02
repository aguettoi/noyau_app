-- C4B.5B certification: every technical fixture and analytical write rolls back.
begin;
do $$
declare
  actor uuid; target uuid; other_target uuid;
  lines jsonb; decisions jsonb; bad jsonb; result jsonb;
  fingerprint text := repeat('a',64);
  failed boolean;
begin
  select user_id into actor from public.household_members order by created_at limit 1;
  perform set_config('request.jwt.claim.sub', actor::text, true);
  insert into public.households(name,classification)
    values ('SQL TEST C4B.5B rollback','technical') returning id into target;
  insert into public.household_members(household_id,user_id,role) values(target,actor,'owner');
  insert into public.households(name,classification)
    values ('SQL TEST C4B.5B unauthorized rollback','technical') returning id into other_target;
  select jsonb_agg(jsonb_build_object(
    'source_row_number',i,'source_content_hash',md5(i::text)||md5(i::text),
    'occurred_on','2026-05-01','source_envelope_label','Test analytique',
    'source_amount',case when i<=1366 then -10 else 10 end,
    'initial_classification',case when i<=1366 then 'expense'
      when i<=1408 then 'internal_transfer' when i<=1420 then 'technical_adjustment'
      when i<=1536 then 'budget_funding' else 'ambiguous_positive' end,
    'analytical_amount',10,'detail','Fixture rollback '||i,
    'confidence','high','proposal_reason','Test SQL transactionnel',
    'transfer_group_key',case when i between 1367 and 1408 then 'pair-test' end
  ) order by i) into lines from generate_series(1,1581) i;
  select jsonb_agg(jsonb_build_object(
    'source_sha256',fingerprint,'sheet_name','Journal','source_row_number',i,
    'source_content_hash',md5(i::text)||md5(i::text),'initial_classification','ambiguous_positive',
    'final_classification',case when i<=1562 then 'validated_income'
      when i<=1572 then 'internal_transfer' when i<=1579 then 'technical_adjustment'
      else 'budget_funding' end,'decision_origin','human'
  ) order by i) into decisions from generate_series(1537,1581) i;

  -- Failure occurs on INSERT number 800, after 799 inserts in the RPC transaction.
  bad := jsonb_set(lines,'{799,confidence}','"invalid"'::jsonb);
  failed := false;
  begin
    perform public.materialize_historical_analytic_import(target,'fixture.xlsx',fingerprint,
      'Journal','2026-05-01','2026-09-29',1581,'failure-middle',bad,decisions);
  exception when check_violation then failed := true; end;
  if not failed or exists(select 1 from public.historical_analytic_lines where household_id=target)
    or exists(select 1 from public.historical_analytic_import_batches where household_id=target)
    or exists(select 1 from public.import_sessions where household_id=target) then
    raise exception 'FAIL rollback 0/0';
  end if;

  result := public.materialize_historical_analytic_import(target,'fixture.xlsx',fingerprint,
    'Journal','2026-05-01','2026-09-29',1581,'success',lines,decisions);
  if (result->>'inserted_lines')::int<>1581 or (result->>'inserted_decisions')::int<>45 then
    raise exception 'FAIL success count'; end if;
  if (select count(*) from public.historical_analytic_lines where household_id=target)<>1581
    or (select count(*) from public.historical_analytic_decisions d join public.historical_analytic_lines l
      on l.id=d.historical_line_id where l.household_id=target)<>45 then raise exception 'FAIL persisted count'; end if;
  if (select count(*) from public.historical_analytic_line_status where household_id=target and current_classification='expense')<>1366
    or (select count(*) from public.historical_analytic_line_status where household_id=target and current_classification='validated_income')<>26
    or (select count(*) from public.historical_analytic_line_status where household_id=target and current_classification='internal_transfer')<>52
    or (select count(*) from public.historical_analytic_line_status where household_id=target and current_classification='technical_adjustment')<>19
    or (select count(*) from public.historical_analytic_line_status where household_id=target and current_classification='budget_funding')<>118
    then raise exception 'FAIL final ventilation'; end if;
  if (select count(*) from public.historical_analytic_line_status where household_id=target
      and initial_classification='ambiguous_positive' and decision_origin='human')<>45 then
    raise exception 'FAIL initial/human trace'; end if;

  result := public.materialize_historical_analytic_import(target,'fixture.xlsx',fingerprint,
    'Journal','2026-05-01','2026-09-29',1581,'success',lines,decisions);
  if result->>'replayed'<>'true' or (result->>'inserted_lines')::int<>0
    or (result->>'inserted_decisions')::int<>0 then raise exception 'FAIL replay'; end if;
  failed := false;
  begin
    perform public.materialize_historical_analytic_import(target,'fixture.xlsx',fingerprint,
      'Journal','2026-05-01','2026-09-29',1581,'success',jsonb_set(lines,'{0,detail}','"changed"'),decisions);
  exception when others then
    if sqlerrm <> 'Historical analytical idempotency conflict' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'FAIL conflict'; end if;
  failed := false;
  begin
    perform public.materialize_historical_analytic_import(other_target,'fixture.xlsx',fingerprint,
      'Journal','2026-05-01','2026-09-29',1581,'unauthorized',lines,decisions);
  exception when others then
    if sqlerrm <> 'Household access denied' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'FAIL household isolation'; end if;
  failed := false;
  begin
    update public.historical_analytic_lines set detail='rewrite' where household_id=target;
  exception when others then
    if sqlerrm <> 'Historical analytical records are append-only' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'FAIL append-only'; end if;
  failed := false;
  begin
    delete from public.historical_analytic_decisions where historical_line_id in
      (select id from public.historical_analytic_lines where household_id=target);
  exception when others then
    if sqlerrm <> 'Historical analytical records are append-only' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'FAIL decision append-only'; end if;
  if has_function_privilege('anon',
    'public.materialize_historical_analytic_import(uuid,text,text,text,date,date,integer,text,jsonb,jsonb)', 'EXECUTE') then
    raise exception 'FAIL anonymous RPC access'; end if;
  execute 'set local role authenticated';
  if (select count(*) from public.historical_analytic_line_status where household_id=target)<>1581 then
    raise exception 'FAIL member RLS read'; end if;
  if exists(select 1 from public.historical_analytic_import_batches where household_id=other_target) then
    raise exception 'FAIL cross household RLS'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  failed := false;
  begin
    perform public.materialize_historical_analytic_import(target,'fixture.xlsx',fingerprint,
      'Journal','2026-05-01','2026-09-29',1581,'no-auth',lines,decisions);
  exception when others then
    if sqlerrm <> 'Household access denied' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'FAIL auth required'; end if;
  if exists(select 1 from public.financial_events where household_id=target)
    or exists(select 1 from public.accounts where household_id=target)
    or exists(select 1 from public.envelopes where household_id=target)
    or exists(select 1 from public.obligations where household_id=target)
    or exists(select 1 from public.financial_transactions where household_id=target)
    or exists(select 1 from public.envelope_movements where household_id=target) then
    raise exception 'FAIL financial separation'; end if;
end;
$$;
select 'PASS: 1581/45, ventilation, middle failure 0/0, replay, conflict, isolation, append-only lines/decisions, RLS, auth/ACL, financial separation' as certification;
rollback;
