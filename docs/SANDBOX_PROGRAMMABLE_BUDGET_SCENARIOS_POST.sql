-- READ ONLY postcheck for 202608100006.
with checks as (
  select to_regclass('public.budget_scenario_versions') is not null as versions,
         to_regclass('public.budget_scenario_sources') is not null as sources,
         to_regclass('public.budget_scenario_steps') is not null as steps,
         exists (select 1 from information_schema.columns where table_schema='public' and table_name='budget_allocation_runs' and column_name='scenario_version_id') as run_snapshot_version
)
select versions and sources and steps and run_snapshot_version as post_migration_ready,
       versions, sources, steps, run_snapshot_version,
       concat_ws('; ', case when not versions then 'budget_scenario_versions missing' end, case when not sources then 'budget_scenario_sources missing' end, case when not steps then 'budget_scenario_steps missing' end, case when not run_snapshot_version then 'run scenario version missing' end) as blocking_details
from checks;
