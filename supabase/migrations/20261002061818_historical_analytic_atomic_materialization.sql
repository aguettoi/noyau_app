-- C4B.5B: one atomic, idempotent boundary for the analytical history only.
-- This migration performs no backfill and never touches a financial ledger.
alter table public.historical_analytic_lines
  add column if not exists repetition_kind text
  check (repetition_kind in ('strict_source', 'business_similarity'));

create table public.historical_analytic_import_batches (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  import_sheet_run_id uuid not null references public.import_sheet_runs(id) on delete restrict,
  source_fingerprint text not null check (source_fingerprint ~ '^[0-9a-f]{64}$'),
  source_sheet_name text not null check (btrim(source_sheet_name) <> ''),
  period_start date not null,
  period_end date not null check (period_end >= period_start),
  expected_line_count integer not null check (expected_line_count > 0),
  line_count integer not null check (line_count = expected_line_count),
  decision_count integer not null check (decision_count >= 0),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users(id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  unique (household_id, idempotency_key)
);

create index historical_analytic_batches_household_created_idx
  on public.historical_analytic_import_batches(household_id, created_at desc);

alter table public.historical_analytic_import_batches enable row level security;
create policy "members read historical analytical batches"
on public.historical_analytic_import_batches for select to authenticated
using (public.is_household_member(household_id));
revoke all on public.historical_analytic_import_batches from public, anon, authenticated;
grant select on public.historical_analytic_import_batches to authenticated;

create trigger historical_analytic_batches_append_only
before update or delete on public.historical_analytic_import_batches
for each row execute function public.prevent_historical_analytic_mutation();

create or replace view public.historical_analytic_line_status
with (security_invoker = true) as
select line.id, line.household_id, line.import_sheet_run_id, line.source_fingerprint,
       line.source_sheet_name, line.source_row_number, line.source_content_hash,
       line.occurred_on, line.period_month, line.source_envelope_label, line.envelope_id,
       line.source_amount, line.proposed_classification, line.analytical_amount,
       line.detail, line.confidence, line.proposal_reason, line.transfer_group_key,
       line.duplicate_candidate_key, line.created_by, line.created_at,
       decision.id as latest_decision_id,
       decision.decision,
       coalesce(decision.classification, line.proposed_classification) as current_classification,
       coalesce(decision.analytical_amount, line.analytical_amount) as current_analytical_amount,
       decision.reason as decision_reason,
       decision.decided_by,
       decision.decided_at,
       line.repetition_kind,
       line.proposed_classification as initial_classification,
       coalesce(decision.classification, line.proposed_classification) as final_classification,
       case when decision.id is null then 'proposal' else 'human' end as decision_origin
from public.historical_analytic_lines line
left join lateral (
  select d.* from public.historical_analytic_decisions d
  where d.historical_line_id = line.id
  order by d.decided_at desc, d.id desc limit 1
) decision on true;

revoke all on public.historical_analytic_line_status from anon, authenticated;
grant select on public.historical_analytic_line_status to authenticated;

create or replace function public.materialize_historical_analytic_import(
  p_household_id uuid,
  p_source_file_name text,
  p_source_fingerprint text,
  p_source_sheet_name text,
  p_period_start date,
  p_period_end date,
  p_expected_line_count integer,
  p_idempotency_key text,
  p_lines jsonb,
  p_human_decisions jsonb
) returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_payload_hash text;
  v_existing public.historical_analytic_import_batches%rowtype;
  v_session_id uuid;
  v_run_id uuid;
  v_batch_id uuid;
  v_item jsonb;
  v_decision jsonb;
  v_line_id uuid;
  v_row integer;
  v_initial text;
  v_final text;
  v_amount numeric;
  v_decisions integer;
  v_allowed constant text[] := array[
    'expense','budget_funding','internal_transfer','ambiguous_positive',
    'technical_adjustment','ignored','validated_income'
  ];
begin
  if v_actor is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_source_fingerprint is null or p_source_fingerprint !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_source_sheet_name, '')) = ''
     or btrim(coalesce(p_source_file_name, '')) = ''
     or btrim(coalesce(p_idempotency_key, '')) = ''
     or p_period_start is null or p_period_end is null or p_period_end < p_period_start
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_typeof(p_human_decisions) is distinct from 'array'
     or p_expected_line_count is null or p_expected_line_count <= 0 then
    raise exception 'Invalid historical analytical batch';
  end if;
  if jsonb_array_length(p_lines) <> p_expected_line_count then
    raise exception 'Historical analytical line count mismatch';
  end if;
  v_decisions := jsonb_array_length(p_human_decisions);
  if exists (
    select 1 from jsonb_array_elements(p_lines) item
    group by (item->>'source_row_number')::integer having count(*) > 1
  ) or exists (
    select 1 from jsonb_array_elements(p_human_decisions) item
    group by (item->>'source_row_number')::integer having count(*) > 1
  ) then
    raise exception 'Duplicate source identity in payload';
  end if;

  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'household_id', p_household_id, 'source_file_name', p_source_file_name,
    'source_fingerprint', p_source_fingerprint, 'source_sheet_name', p_source_sheet_name,
    'period_start', p_period_start, 'period_end', p_period_end,
    'expected_line_count', p_expected_line_count, 'lines', p_lines,
    'human_decisions', p_human_decisions
  )::text, 'utf8'), 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(p_household_id::text || ':' || p_idempotency_key, 0));
  select * into v_existing from public.historical_analytic_import_batches
  where household_id = p_household_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.payload_hash <> v_payload_hash then
      raise exception 'Historical analytical idempotency conflict';
    end if;
    return jsonb_build_object(
      'batch_id', v_existing.id, 'inserted_lines', 0,
      'inserted_decisions', 0, 'replayed', true
    );
  end if;

  -- Validate every row and every human decision before the first insert.
  for v_item in select value from jsonb_array_elements(p_lines) loop
    v_row := nullif(v_item->>'source_row_number', '')::integer;
    v_initial := v_item->>'initial_classification';
    if v_row is null or v_row <= 0
       or (v_item->>'source_content_hash') !~ '^[0-9a-f]{64}$'
       or v_initial is null or not (v_initial = any(v_allowed))
       or (v_item->>'occurred_on')::date not between p_period_start and p_period_end
       or btrim(coalesce(v_item->>'source_envelope_label', '')) = ''
       or btrim(coalesce(v_item->>'detail', '')) = ''
       or (v_item->>'analytical_amount')::numeric < 0 then
      raise exception 'Invalid historical line at row %', v_row;
    end if;
    if nullif(v_item->>'envelope_id', '') is not null and not exists (
      select 1 from public.envelopes e
      where e.id = (v_item->>'envelope_id')::uuid and e.household_id = p_household_id
    ) then raise exception 'Envelope does not belong to household at row %', v_row; end if;
  end loop;

  for v_decision in select value from jsonb_array_elements(p_human_decisions) loop
    v_row := nullif(v_decision->>'source_row_number', '')::integer;
    v_initial := v_decision->>'initial_classification';
    v_final := v_decision->>'final_classification';
    if v_decision->>'decision_origin' is distinct from 'human'
       or v_decision->>'source_sha256' is distinct from p_source_fingerprint
       or v_decision->>'sheet_name' is distinct from p_source_sheet_name
       or v_initial is null or not (v_initial = any(v_allowed))
       or v_final is null or not (v_final = any(v_allowed))
       or v_final = 'ambiguous_positive'
       or not exists (
         select 1 from jsonb_array_elements(p_lines) line
         where (line->>'source_row_number')::integer = v_row
           and line->>'source_content_hash' = v_decision->>'source_content_hash'
           and line->>'initial_classification' = v_initial
       ) then raise exception 'Invalid human decision at row %', v_row; end if;
  end loop;
  if exists (
    select 1 from jsonb_array_elements(p_lines) line
    where line->>'initial_classification' = 'ambiguous_positive'
      and not exists (
        select 1 from jsonb_array_elements(p_human_decisions) decision
        where (decision->>'source_row_number')::integer = (line->>'source_row_number')::integer
          and decision->>'final_classification' <> 'ambiguous_positive'
      )
  ) then raise exception 'Unresolved ambiguous positive remains'; end if;

  insert into public.import_sessions(
    household_id, source_file_name, source_fingerprint, status, created_by,
    confirmed_by, confirmed_at, completed_at
  ) values (
    p_household_id, btrim(p_source_file_name), p_source_fingerprint, 'completed',
    v_actor, v_actor, now(), now()
  ) returning id into v_session_id;
  insert into public.import_sheet_runs(
    import_session_id, importer_id, source_sheet_name, status, detected_records, preview
  ) values (
    v_session_id, 'historical_analytics_c4b', p_source_sheet_name, 'completed',
    p_expected_line_count, jsonb_build_object('period_start', p_period_start, 'period_end', p_period_end)
  ) returning id into v_run_id;
  insert into public.historical_analytic_import_batches(
    household_id, import_sheet_run_id, source_fingerprint, source_sheet_name,
    period_start, period_end, expected_line_count, line_count, decision_count,
    idempotency_key, payload_hash, created_by
  ) values (
    p_household_id, v_run_id, p_source_fingerprint, p_source_sheet_name,
    p_period_start, p_period_end, p_expected_line_count, p_expected_line_count,
    v_decisions, p_idempotency_key, v_payload_hash, v_actor
  ) returning id into v_batch_id;

  for v_item in select value from jsonb_array_elements(p_lines) loop
    insert into public.historical_analytic_lines(
      household_id, import_sheet_run_id, source_fingerprint, source_sheet_name,
      source_row_number, source_content_hash, occurred_on, period_month,
      source_envelope_label, envelope_id, source_amount, proposed_classification,
      analytical_amount, detail, confidence, proposal_reason, transfer_group_key,
      duplicate_candidate_key, repetition_kind, created_by
    ) values (
      p_household_id, v_run_id, p_source_fingerprint, p_source_sheet_name,
      (v_item->>'source_row_number')::integer, v_item->>'source_content_hash',
      (v_item->>'occurred_on')::date, date_trunc('month', (v_item->>'occurred_on')::date)::date,
      v_item->>'source_envelope_label', nullif(v_item->>'envelope_id', '')::uuid,
      (v_item->>'source_amount')::numeric, v_item->>'initial_classification',
      (v_item->>'analytical_amount')::numeric, v_item->>'detail',
      v_item->>'confidence', v_item->>'proposal_reason',
      nullif(v_item->>'transfer_group_key', ''), nullif(v_item->>'duplicate_candidate_key', ''),
      nullif(v_item->>'repetition_kind', ''), v_actor
    );
  end loop;

  for v_decision in select value from jsonb_array_elements(p_human_decisions) loop
    select id, analytical_amount into v_line_id, v_amount
    from public.historical_analytic_lines
    where household_id = p_household_id and source_fingerprint = p_source_fingerprint
      and source_sheet_name = p_source_sheet_name
      and source_row_number = (v_decision->>'source_row_number')::integer;
    v_final := v_decision->>'final_classification';
    insert into public.historical_analytic_decisions(
      historical_line_id, decision, classification, analytical_amount, reason, decided_by
    ) values (
      v_line_id, case when v_final = 'ignored' then 'ignore' else 'reclassify' end,
      v_final, case when v_final = 'ignored' then 0 else v_amount end,
      'Décision humaine restaurée depuis la sauvegarde certifiée', v_actor
    );
  end loop;

  return jsonb_build_object(
    'batch_id', v_batch_id, 'inserted_lines', p_expected_line_count,
    'inserted_decisions', v_decisions, 'replayed', false
  );
end;
$$;

revoke all on function public.materialize_historical_analytic_import(
  uuid,text,text,text,date,date,integer,text,jsonb,jsonb
) from public, anon;
grant execute on function public.materialize_historical_analytic_import(
  uuid,text,text,text,date,date,integer,text,jsonb,jsonb
) to authenticated;
