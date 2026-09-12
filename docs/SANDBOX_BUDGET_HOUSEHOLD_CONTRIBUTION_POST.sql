-- READ ONLY: postcheck for 202608100005_budget_household_contribution_model.sql.
with checks as (
  select
    to_regclass('public.budget_scenario_member_incomes') is not null as incomes_table_exists,
    (select count(*) = 3 from information_schema.columns where table_schema='public' and table_name='budget_scenario_rules' and column_name in ('funding_mode','funding_member_user_id','funding_definition')) as rule_columns_exist,
    exists (select 1 from pg_class relation join pg_namespace schema_namespace on schema_namespace.oid=relation.relnamespace where schema_namespace.nspname='public' and relation.relname='budget_scenario_member_incomes' and relation.relrowsecurity) as rls_enabled
    ,to_regprocedure('public.save_budget_allocation_run_with_contributions(uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb,jsonb)') is not null as snapshot_rpc_exists
)
select incomes_table_exists and rule_columns_exist and rls_enabled and snapshot_rpc_exists as post_migration_ready,
       incomes_table_exists, rule_columns_exist, rls_enabled, snapshot_rpc_exists,
       concat_ws('; ', case when not incomes_table_exists then 'income table missing' end, case when not rule_columns_exist then 'funding rule columns missing' end, case when not rls_enabled then 'income RLS missing' end, case when not snapshot_rpc_exists then 'contribution snapshot RPC missing' end) as blocking_details
from checks;
