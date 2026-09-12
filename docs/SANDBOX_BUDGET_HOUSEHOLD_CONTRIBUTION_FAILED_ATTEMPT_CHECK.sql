-- READ ONLY: post-failure state check for 202608100005.
-- This script intentionally reads PostgreSQL catalogs only and returns one row.
with observed as (
  select
    to_regclass('public.budget_scenario_member_incomes') is not null
      as member_incomes_table_exists,
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'budget_scenario_rules'
        and column_name = 'funding_mode'
    ) as funding_mode_exists,
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'budget_scenario_rules'
        and column_name = 'funding_member_user_id'
    ) as funding_member_user_id_exists,
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'budget_scenario_rules'
        and column_name = 'funding_definition'
    ) as funding_definition_exists,
    to_regprocedure(
      'public.save_budget_allocation_run_with_contributions(uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb,jsonb)'
    ) is not null as save_contributions_rpc_exists,
    exists (
      select 1 from pg_constraint constraint_info
      where constraint_info.conrelid = to_regclass('public.budget_scenario_rules')
        and constraint_info.conname = 'budget_scenario_rules_funding_member_household_fk'
    ) as funding_member_fk_exists,
    exists (
      select 1 from pg_constraint constraint_info
      where constraint_info.conrelid = to_regclass('public.budget_scenario_rules')
        and constraint_info.conname = 'budget_scenario_rules_personal_member_check'
    ) as personal_member_check_exists,
    exists (
      select 1 from pg_policies policy_info
      where policy_info.schemaname = 'public'
        and policy_info.tablename = 'budget_scenario_member_incomes'
        and policy_info.policyname = 'members manage budget scenario incomes'
    ) as member_incomes_policy_exists,
    coalesce((
      select class_info.relrowsecurity
      from pg_class class_info
      where class_info.oid = to_regclass('public.budget_scenario_member_incomes')
    ), false) as member_incomes_rls_enabled,
    case
      when to_regclass('public.budget_scenario_member_incomes') is null then false
      else has_table_privilege(
        'authenticated',
        'public.budget_scenario_member_incomes',
        'SELECT, INSERT, UPDATE'
      )
    end as member_incomes_authenticated_grants,
    coalesce(
      has_function_privilege(
        'authenticated',
        to_regprocedure(
          'public.save_budget_allocation_run_with_contributions(uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb,jsonb)'
        ),
        'EXECUTE'
      ),
      false
    ) as save_contributions_authenticated_execute
), summary as (
  select
    *,
    not member_incomes_table_exists
      and not funding_mode_exists
      and not funding_member_user_id_exists
      and not funding_definition_exists
      and not save_contributions_rpc_exists
      and not funding_member_fk_exists
      and not personal_member_check_exists
      and not member_incomes_policy_exists
      and not member_incomes_rls_enabled as migration_fully_absent
  from observed
)
select
  migration_fully_absent,
  member_incomes_table_exists,
  funding_mode_exists,
  funding_member_user_id_exists,
  funding_definition_exists,
  save_contributions_rpc_exists,
  funding_member_fk_exists,
  personal_member_check_exists,
  member_incomes_policy_exists,
  member_incomes_rls_enabled,
  member_incomes_authenticated_grants,
  save_contributions_authenticated_execute,
  not migration_fully_absent as partial_state_detected,
  migration_fully_absent as safe_to_retry,
  concat_ws(
    '; ',
    case when not migration_fully_absent then
      '080005 left one or more objects; do not retry until the state is reviewed'
    end,
    case when member_incomes_table_exists and not member_incomes_rls_enabled then
      'member income table exists without RLS'
    end,
    case when member_incomes_table_exists and not member_incomes_policy_exists then
      'member income policy is missing'
    end,
    case when save_contributions_rpc_exists and not save_contributions_authenticated_execute then
      'authenticated execute grant is missing on the contribution snapshot RPC'
    end
  ) as blocking_details
from summary;
