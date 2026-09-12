-- READ ONLY: preflight for 202608100005_budget_household_contribution_model.sql.
with checks as (
  select
    to_regclass('public.budget_scenarios') is not null as scenarios_ready,
    to_regclass('public.budget_scenario_rules') is not null as rules_ready,
    to_regclass('public.household_members') is not null as members_ready,
    exists (select 1 from information_schema.columns where table_schema='public' and table_name='budget_scenario_rules' and column_name='household_id') as household_key_ready
)
select scenarios_ready and rules_ready and members_ready and household_key_ready as pre_migration_ready,
       scenarios_ready, rules_ready, members_ready, household_key_ready,
       concat_ws('; ', case when not scenarios_ready then 'budget_scenarios missing' end, case when not rules_ready then 'budget_scenario_rules missing' end, case when not members_ready then 'household_members missing' end, case when not household_key_ready then 'rule household key missing' end) as blocking_details
from checks;
