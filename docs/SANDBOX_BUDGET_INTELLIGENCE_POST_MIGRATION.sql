-- Read-only validation checkpoint for 202608100002_budget_intelligence_foundation.sql.
with expected(name) as (values ('budget_scenarios'), ('budget_periods'), ('budget_scenario_rules'), ('budget_allocation_runs'), ('budget_allocation_run_lines'), ('budget_goals')),
objects as (
  select name, exists(select 1 from information_schema.tables t where t.table_schema = 'public' and t.table_name = expected.name) as exists
  from expected
), reporting as (
  select exists(select 1 from information_schema.views v where v.table_schema = 'public' and v.table_name = 'budget_envelope_reporting') as exists
), rls as (
  select count(*) = 6 as ready from pg_tables t where t.schemaname = 'public' and t.tablename in ('budget_scenarios','budget_periods','budget_scenario_rules','budget_allocation_runs','budget_allocation_run_lines','budget_goals') and t.rowsecurity
), period_columns as (
  select count(*) = 4 as ready from information_schema.columns
  where table_schema = 'public' and table_name = 'budget_periods' and column_name in ('starts_on', 'ends_on', 'scenario_id', 'opened_at')
)
select bool_and(objects.exists) and (select reporting.exists from reporting) and (select rls.ready from rls) and (select ready from period_columns) as post_migration_ready,
  jsonb_object_agg(objects.name, objects.exists) as tables,
  (select reporting.exists from reporting) as reporting_view_exists,
  (select rls.ready from rls) as rls_ready,
  (select ready from period_columns) as period_model_ready
from objects;
