-- Read-only prerequisite checkpoint for 202608100002_budget_intelligence_foundation.sql.
with required_tables(table_name) as (values ('households'), ('envelopes'), ('envelope_movements'), ('budget_periods')),
table_checks as (
  select table_name, exists(select 1 from information_schema.tables t where t.table_schema = 'public' and t.table_name = required_tables.table_name) as present
  from required_tables
), function_checks as (
  select exists(select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'is_household_member') as membership_function_present
), period_columns as (
  select count(*) = 2 as period_model_ready from information_schema.columns
  where table_schema = 'public' and table_name = 'budget_periods' and column_name in ('starts_on', 'ends_on')
)
select bool_and(present) and (select membership_function_present from function_checks) and (select period_model_ready from period_columns) as pre_migration_ready,
  jsonb_agg(jsonb_build_object('table', table_name, 'present', present)) as tables,
  (select membership_function_present from function_checks) as membership_function_present,
  (select period_model_ready from period_columns) as period_model_ready
from table_checks;
