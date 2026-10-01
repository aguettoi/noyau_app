-- C4C hardening after the Sandbox advisor pass. Additive only: no data rewrite.
alter function public.prevent_historical_analytic_mutation()
  set search_path = public, pg_temp;

create index historical_analytic_lines_import_run_idx
  on public.historical_analytic_lines(import_sheet_run_id);
create index historical_analytic_lines_envelope_idx
  on public.historical_analytic_lines(envelope_id)
  where envelope_id is not null;
create index historical_analytic_lines_created_by_idx
  on public.historical_analytic_lines(created_by);
create index historical_analytic_decisions_decided_by_idx
  on public.historical_analytic_decisions(decided_by);
