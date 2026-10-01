-- C4C: append-only analytical history. This migration deliberately does not
-- populate historical rows and does not touch any financial ledger.
create table public.historical_analytic_lines (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  import_sheet_run_id uuid not null references public.import_sheet_runs(id) on delete restrict,
  source_fingerprint text not null check (source_fingerprint ~ '^[0-9a-f]{64}$'),
  source_sheet_name text not null check (btrim(source_sheet_name) <> ''),
  source_row_number integer not null check (source_row_number > 0),
  source_content_hash text not null check (source_content_hash ~ '^[0-9a-f]{64}$'),
  occurred_on date not null,
  period_month date not null check (extract(day from period_month) = 1),
  source_envelope_label text not null check (btrim(source_envelope_label) <> ''),
  envelope_id uuid references public.envelopes(id) on delete restrict,
  source_amount numeric(14,2) not null check (source_amount <> 0),
  proposed_classification text not null check (proposed_classification in (
    'expense', 'budget_funding', 'internal_transfer', 'ambiguous_positive',
    'technical_adjustment', 'ignored', 'validated_income'
  )),
  analytical_amount numeric(14,2) not null check (analytical_amount >= 0),
  detail text not null check (btrim(detail) <> ''),
  confidence text not null check (confidence in ('high', 'medium', 'low')),
  proposal_reason text not null check (btrim(proposal_reason) <> ''),
  transfer_group_key text,
  duplicate_candidate_key text,
  created_by uuid not null references auth.users(id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  unique (household_id, source_fingerprint, source_sheet_name, source_row_number),
  unique (import_sheet_run_id, source_row_number),
  check (period_month = date_trunc('month', occurred_on)::date),
  check ((proposed_classification = 'ignored' and analytical_amount = 0)
      or proposed_classification <> 'ignored'),
  check ((proposed_classification = 'internal_transfer' and transfer_group_key is not null)
      or proposed_classification <> 'internal_transfer')
);

create table public.historical_analytic_decisions (
  id uuid primary key default gen_random_uuid(),
  historical_line_id uuid not null references public.historical_analytic_lines(id) on delete restrict,
  decision text not null check (decision in ('accept', 'reclassify', 'ignore')),
  classification text not null check (classification in (
    'expense', 'budget_funding', 'internal_transfer', 'ambiguous_positive',
    'technical_adjustment', 'ignored', 'validated_income'
  )),
  analytical_amount numeric(14,2) not null check (analytical_amount >= 0),
  reason text not null check (btrim(reason) <> ''),
  decided_by uuid not null references auth.users(id) on delete restrict default auth.uid(),
  decided_at timestamptz not null default now(),
  check ((decision = 'ignore' and classification = 'ignored' and analytical_amount = 0)
      or (decision <> 'ignore' and classification <> 'ignored'))
);

create index historical_analytic_lines_household_date_idx
  on public.historical_analytic_lines(household_id, occurred_on, source_row_number);
create index historical_analytic_decisions_line_date_idx
  on public.historical_analytic_decisions(historical_line_id, decided_at desc, id desc);

alter table public.historical_analytic_lines enable row level security;
alter table public.historical_analytic_decisions enable row level security;

create policy "members read historical analytical lines"
on public.historical_analytic_lines for select to authenticated
using (public.is_household_member(household_id));

create policy "members read historical analytical decisions"
on public.historical_analytic_decisions for select to authenticated
using (exists (
  select 1 from public.historical_analytic_lines line
  where line.id = historical_line_id
    and public.is_household_member(line.household_id)
));

revoke all on public.historical_analytic_lines from anon, authenticated;
revoke all on public.historical_analytic_decisions from anon, authenticated;
grant select on public.historical_analytic_lines to authenticated;
grant select on public.historical_analytic_decisions to authenticated;

create or replace function public.prevent_historical_analytic_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'Historical analytical records are append-only';
end;
$$;

create trigger historical_analytic_lines_append_only
before update or delete on public.historical_analytic_lines
for each row execute function public.prevent_historical_analytic_mutation();
create trigger historical_analytic_decisions_append_only
before update or delete on public.historical_analytic_decisions
for each row execute function public.prevent_historical_analytic_mutation();

create or replace view public.historical_analytic_line_status
with (security_invoker = true) as
select line.*,
       decision.id as latest_decision_id,
       decision.decision,
       decision.classification as current_classification,
       decision.analytical_amount as current_analytical_amount,
       decision.reason as decision_reason,
       decision.decided_by,
       decision.decided_at
from public.historical_analytic_lines line
left join lateral (
  select d.* from public.historical_analytic_decisions d
  where d.historical_line_id = line.id
  order by d.decided_at desc, d.id desc limit 1
) decision on true;

revoke all on public.historical_analytic_line_status from anon, authenticated;
grant select on public.historical_analytic_line_status to authenticated;

create or replace function public.commit_historical_analytic_import(
  p_household_id uuid,
  p_import_sheet_run_id uuid,
  p_source_fingerprint text,
  p_source_sheet_name text,
  p_lines jsonb
) returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_item jsonb;
  v_existing public.historical_analytic_lines%rowtype;
  v_line_id uuid;
  v_inserted integer := 0;
  v_replayed integer := 0;
  v_envelope uuid;
begin
  if v_actor is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_source_fingerprint !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Invalid analytical import payload';
  end if;
  if not exists (
    select 1 from public.import_sheet_runs run
    join public.import_sessions session on session.id = run.import_session_id
    where run.id = p_import_sheet_run_id
      and session.household_id = p_household_id
      and session.source_fingerprint = p_source_fingerprint
      and run.source_sheet_name = p_source_sheet_name
  ) then
    raise exception 'Import sheet run does not match household/source';
  end if;

  for v_item in select value from jsonb_array_elements(p_lines) loop
    v_envelope := nullif(v_item->>'envelope_id', '')::uuid;
    if v_envelope is not null and not exists (
      select 1 from public.envelopes e where e.id = v_envelope and e.household_id = p_household_id
    ) then raise exception 'Envelope does not belong to household'; end if;

    select * into v_existing from public.historical_analytic_lines
    where household_id = p_household_id
      and source_fingerprint = p_source_fingerprint
      and source_sheet_name = p_source_sheet_name
      and source_row_number = (v_item->>'source_row_number')::integer;
    if found then
      if v_existing.source_content_hash <> v_item->>'source_content_hash' then
        raise exception 'Historical source identity conflict at row %', v_item->>'source_row_number';
      end if;
      v_replayed := v_replayed + 1;
      continue;
    end if;

    insert into public.historical_analytic_lines(
      household_id, import_sheet_run_id, source_fingerprint, source_sheet_name,
      source_row_number, source_content_hash, occurred_on, period_month,
      source_envelope_label, envelope_id, source_amount, proposed_classification,
      analytical_amount, detail, confidence, proposal_reason, transfer_group_key,
      duplicate_candidate_key, created_by
    ) values (
      p_household_id, p_import_sheet_run_id, p_source_fingerprint, p_source_sheet_name,
      (v_item->>'source_row_number')::integer, v_item->>'source_content_hash',
      (v_item->>'occurred_on')::date, date_trunc('month', (v_item->>'occurred_on')::date)::date,
      v_item->>'source_envelope_label', v_envelope, (v_item->>'source_amount')::numeric,
      v_item->>'classification', (v_item->>'analytical_amount')::numeric,
      v_item->>'detail', v_item->>'confidence', v_item->>'proposal_reason',
      nullif(v_item->>'transfer_group_key', ''), nullif(v_item->>'duplicate_candidate_key', ''), v_actor
    ) returning id into v_line_id;
    insert into public.historical_analytic_decisions(
      historical_line_id, decision, classification, analytical_amount, reason, decided_by
    ) values (
      v_line_id, 'accept', v_item->>'classification', (v_item->>'analytical_amount')::numeric,
      'Proposition initiale acceptée lors de la reprise analytique', v_actor
    );
    v_inserted := v_inserted + 1;
  end loop;
  return jsonb_build_object('inserted', v_inserted, 'replayed', v_replayed);
end;
$$;

create or replace function public.append_historical_analytic_decision(
  p_household_id uuid,
  p_historical_line_id uuid,
  p_decision text,
  p_classification text,
  p_analytical_amount numeric,
  p_reason text
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if not exists (select 1 from public.historical_analytic_lines where id = p_historical_line_id and household_id = p_household_id) then
    raise exception 'Historical line not found in household';
  end if;
  insert into public.historical_analytic_decisions(
    historical_line_id, decision, classification, analytical_amount, reason, decided_by
  ) values (p_historical_line_id, p_decision, p_classification, p_analytical_amount, p_reason, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.commit_historical_analytic_import(uuid,uuid,text,text,jsonb) from public, anon;
grant execute on function public.commit_historical_analytic_import(uuid,uuid,text,text,jsonb) to authenticated;
revoke all on function public.append_historical_analytic_decision(uuid,uuid,text,text,numeric,text) from public, anon;
grant execute on function public.append_historical_analytic_decision(uuid,uuid,text,text,numeric,text) to authenticated;
