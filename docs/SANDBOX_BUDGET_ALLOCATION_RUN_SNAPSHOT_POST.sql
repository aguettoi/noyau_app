-- READ ONLY. Execute after 202608100004_budget_allocation_run_snapshot.sql.
-- One row only; no DDL and no DML.
with functions as (
  select
    to_regprocedure('public.save_budget_allocation_run(uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb)') is not null as save_snapshot_rpc_exists,
    exists (
      select 1 from pg_proc procedure
      join pg_namespace schema_namespace on schema_namespace.oid = procedure.pronamespace
      where schema_namespace.nspname = 'public'
        and procedure.proname = 'save_budget_allocation_run'
        and procedure.prosecdef
        and pg_get_function_identity_arguments(procedure.oid) =
          'p_household_id uuid, p_run_id uuid, p_budget_period_id uuid, p_scenario_id uuid, p_available_resources numeric, p_calculated_total numeric, p_remaining_unallocated numeric, p_lines jsonb'
    ) as save_snapshot_signature_and_security_ready,
    to_regprocedure('public.approve_budget_allocation_run(uuid,uuid)') is not null as approve_rpc_preserved,
    to_regprocedure('public.apply_budget_allocation_run(uuid,uuid,uuid,uuid)') is not null as apply_rpc_preserved
),
triggers as (
  select
    exists (
      select 1 from pg_trigger trigger_information
      where trigger_information.tgrelid = to_regclass('public.budget_allocation_runs')
        and trigger_information.tgname = 'protect_budget_allocation_run_snapshot'
        and not trigger_information.tgisinternal
    ) as run_snapshot_trigger_exists,
    exists (
      select 1 from pg_trigger trigger_information
      where trigger_information.tgrelid = to_regclass('public.budget_allocation_run_lines')
        and trigger_information.tgname = 'protect_budget_allocation_run_line_snapshot'
        and not trigger_information.tgisinternal
    ) as line_snapshot_trigger_exists
),
grants as (
  select
    has_function_privilege(
      'authenticated',
      'public.save_budget_allocation_run(uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb)',
      'EXECUTE'
    ) as authenticated_execute,
    not has_table_privilege('authenticated', 'public.budget_allocation_runs', 'INSERT')
      and not has_table_privilege('authenticated', 'public.budget_allocation_runs', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.budget_allocation_run_lines', 'INSERT')
      and not has_table_privilege('authenticated', 'public.budget_allocation_run_lines', 'UPDATE') as direct_snapshot_writes_revoked
),
constraints as (
  select
    exists (
      select 1 from pg_constraint constraint_information
      where constraint_information.conrelid = to_regclass('public.budget_allocation_run_lines')
        and constraint_information.contype in ('u', 'p')
        and pg_get_constraintdef(constraint_information.oid) like '%run_id, envelope_id%'
    ) as line_uniqueness_preserved,
    exists (
      select 1 from pg_constraint constraint_information
      where constraint_information.conrelid = to_regclass('public.budget_allocation_runs')
        and constraint_information.contype = 'f'
        and pg_get_constraintdef(constraint_information.oid) like '%budget_periods%'
    ) as period_foreign_key_preserved
),
rls as (
  select coalesce(bool_and(relation.relrowsecurity), false) as rls_preserved
  from pg_class relation
  join pg_namespace schema_namespace on schema_namespace.oid = relation.relnamespace
  where schema_namespace.nspname = 'public'
    and relation.relname in ('budget_allocation_runs', 'budget_allocation_run_lines')
),
summary as (
  select
    functions.save_snapshot_rpc_exists,
    functions.save_snapshot_signature_and_security_ready,
    functions.approve_rpc_preserved,
    functions.apply_rpc_preserved,
    triggers.run_snapshot_trigger_exists,
    triggers.line_snapshot_trigger_exists,
    grants.authenticated_execute,
    grants.direct_snapshot_writes_revoked,
    constraints.line_uniqueness_preserved,
    constraints.period_foreign_key_preserved,
    rls.rls_preserved
  from functions, triggers, grants, constraints, rls
)
select
  save_snapshot_rpc_exists
    and save_snapshot_signature_and_security_ready
    and approve_rpc_preserved
    and apply_rpc_preserved
    and run_snapshot_trigger_exists
    and line_snapshot_trigger_exists
    and authenticated_execute
    and direct_snapshot_writes_revoked
    and line_uniqueness_preserved
    and period_foreign_key_preserved
    and rls_preserved as post_migration_ready,
  jsonb_build_object(
    'save_snapshot_rpc_exists', save_snapshot_rpc_exists,
    'save_snapshot_signature_and_security_ready', save_snapshot_signature_and_security_ready,
    'approve_rpc_preserved', approve_rpc_preserved,
    'apply_rpc_preserved', apply_rpc_preserved,
    'run_snapshot_trigger_exists', run_snapshot_trigger_exists,
    'line_snapshot_trigger_exists', line_snapshot_trigger_exists,
    'authenticated_execute', authenticated_execute,
    'direct_snapshot_writes_revoked', direct_snapshot_writes_revoked,
    'line_uniqueness_preserved', line_uniqueness_preserved,
    'period_foreign_key_preserved', period_foreign_key_preserved,
    'rls_preserved', rls_preserved
  ) as checks_detailed,
  concat_ws('; ',
    case when not save_snapshot_rpc_exists then 'save_budget_allocation_run RPC is missing' end,
    case when not save_snapshot_signature_and_security_ready then 'snapshot RPC signature or SECURITY DEFINER is incorrect' end,
    case when not approve_rpc_preserved or not apply_rpc_preserved then 'existing approval/application RPC was altered' end,
    case when not run_snapshot_trigger_exists or not line_snapshot_trigger_exists then 'snapshot immutability trigger is missing' end,
    case when not authenticated_execute then 'authenticated execute grant is missing' end,
    case when not direct_snapshot_writes_revoked then 'direct snapshot writes remain granted' end,
    case when not line_uniqueness_preserved or not period_foreign_key_preserved then 'existing Budget constraints are missing' end,
    case when not rls_preserved then 'Budget run RLS is disabled' end
  ) as blocking_details
from summary;
