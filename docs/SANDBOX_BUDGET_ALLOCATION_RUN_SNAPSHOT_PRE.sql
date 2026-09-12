-- READ ONLY. Execute before 202608100004_budget_allocation_run_snapshot.sql.
-- One row only; no DDL and no DML.
with expected_tables(table_name) as (
  values
    ('budget_periods'),
    ('budget_scenarios'),
    ('budget_scenario_rules'),
    ('budget_allocation_runs'),
    ('budget_allocation_run_lines'),
    ('envelopes')
),
table_checks as (
  select
    expected_tables.table_name,
    exists (
      select 1
      from pg_class relation
      join pg_namespace schema_namespace on schema_namespace.oid = relation.relnamespace
      where schema_namespace.nspname = 'public'
        and relation.relname = expected_tables.table_name
        and relation.relkind = 'r'
    ) as exists
  from expected_tables
),
expected_columns(table_name, column_name, expected_type) as (
  values
    ('budget_periods', 'id', 'uuid'), ('budget_periods', 'household_id', 'uuid'),
    ('budget_periods', 'starts_on', 'date'), ('budget_periods', 'ends_on', 'date'),
    ('budget_scenarios', 'id', 'uuid'), ('budget_scenarios', 'household_id', 'uuid'),
    ('budget_allocation_runs', 'id', 'uuid'), ('budget_allocation_runs', 'household_id', 'uuid'),
    ('budget_allocation_runs', 'budget_period_id', 'uuid'), ('budget_allocation_runs', 'scenario_id', 'uuid'),
    ('budget_allocation_runs', 'status', 'text'), ('budget_allocation_runs', 'available_resources', 'numeric'),
    ('budget_allocation_runs', 'calculated_total', 'numeric'), ('budget_allocation_runs', 'remaining_unallocated', 'numeric'),
    ('budget_allocation_run_lines', 'run_id', 'uuid'), ('budget_allocation_run_lines', 'household_id', 'uuid'),
    ('budget_allocation_run_lines', 'envelope_id', 'uuid'), ('budget_allocation_run_lines', 'planned_allocation', 'numeric'),
    ('budget_allocation_run_lines', 'resulting_available', 'numeric')
),
column_checks as (
  select
    expected_columns.table_name,
    expected_columns.column_name,
    exists (
      select 1
      from information_schema.columns column_information
      where column_information.table_schema = 'public'
        and column_information.table_name = expected_columns.table_name
        and column_information.column_name = expected_columns.column_name
        and column_information.data_type = expected_columns.expected_type
    ) as exists
  from expected_columns
),
rpc_checks as (
  select
    to_regprocedure('public.approve_budget_allocation_run(uuid,uuid)') is not null as approve_exists,
    to_regprocedure('public.apply_budget_allocation_run(uuid,uuid,uuid,uuid)') is not null as apply_exists,
    exists (
      select 1
      from pg_proc procedure
      join pg_namespace schema_namespace on schema_namespace.oid = procedure.pronamespace
      where schema_namespace.nspname = 'public'
        and procedure.proname = 'allocate_budget_event'
    ) as allocate_exists
),
constraint_checks as (
  select
    exists (
      select 1 from pg_constraint constraint_information
      where constraint_information.conrelid = to_regclass('public.budget_allocation_runs')
        and constraint_information.contype = 'f'
        and pg_get_constraintdef(constraint_information.oid) like '%budget_periods%'
    ) as run_period_fk,
    exists (
      select 1 from pg_constraint constraint_information
      where constraint_information.conrelid = to_regclass('public.budget_allocation_runs')
        and constraint_information.contype = 'f'
        and pg_get_constraintdef(constraint_information.oid) like '%budget_scenarios%'
    ) as run_scenario_fk,
    exists (
      select 1 from pg_constraint constraint_information
      where constraint_information.conrelid = to_regclass('public.budget_allocation_run_lines')
        and constraint_information.contype = 'f'
        and pg_get_constraintdef(constraint_information.oid) like '%budget_allocation_runs%'
    ) as line_run_fk,
    exists (
      select 1 from pg_constraint constraint_information
      where constraint_information.conrelid = to_regclass('public.budget_allocation_run_lines')
        and constraint_information.contype in ('u', 'p')
        and pg_get_constraintdef(constraint_information.oid) like '%run_id, envelope_id%'
    ) as line_unique
),
rls_checks as (
  select coalesce(bool_and(relation.relrowsecurity), false) as enabled,
         coalesce(bool_and(policy_counts.policy_count > 0), false) as policies_present
  from pg_class relation
  join pg_namespace schema_namespace on schema_namespace.oid = relation.relnamespace
  join lateral (
    select count(*) as policy_count
    from pg_policies policy_information
    where policy_information.schemaname = 'public'
      and policy_information.tablename = relation.relname
  ) policy_counts on true
  where schema_namespace.nspname = 'public'
    and relation.relname in ('budget_allocation_runs', 'budget_allocation_run_lines')
),
summary as (
  select
    (select bool_and(exists) from table_checks) as required_tables_ready,
    (select bool_and(exists) from column_checks) as required_columns_ready,
    (select approve_exists and apply_exists and allocate_exists from rpc_checks) as required_rpcs_ready,
    (select count(*) = 2 from information_schema.columns column_information
      where column_information.table_schema = 'public'
        and column_information.table_name = 'budget_periods'
        and column_information.column_name in ('starts_on', 'ends_on')
        and column_information.data_type = 'date') as period_model_ready,
    (select run_period_fk and run_scenario_fk and line_run_fk and line_unique from constraint_checks) as constraints_ready,
    (select enabled and policies_present from rls_checks) as rls_ready
)
select
  required_tables_ready
    and required_columns_ready
    and required_rpcs_ready
    and period_model_ready
    and constraints_ready
    and rls_ready as pre_migration_ready,
  required_tables_ready,
  required_columns_ready,
  required_rpcs_ready,
  period_model_ready,
  constraints_ready,
  rls_ready,
  concat_ws('; ',
    case when not required_tables_ready then 'required Budget tables are missing' end,
    case when not required_columns_ready then 'required Budget columns are missing' end,
    case when not required_rpcs_ready then 'approval, application, or allocation RPC is missing' end,
    case when not period_model_ready then 'budget_periods must expose starts_on and ends_on' end,
    case when not constraints_ready then 'Budget run foreign key or uniqueness constraint is missing' end,
    case when not rls_ready then 'Budget run RLS or policies are missing' end
  ) as blocking_details
from summary;
