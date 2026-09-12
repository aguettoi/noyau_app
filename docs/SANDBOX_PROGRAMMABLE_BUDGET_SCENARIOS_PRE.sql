-- READ ONLY preflight for 202608100006.
with checks as (
  select to_regclass('public.budget_scenarios') is not null as scenarios,
         to_regclass('public.budget_allocation_runs') is not null as runs,
         to_regclass('public.envelopes') is not null as envelopes,
         to_regclass('public.accounts') is not null as accounts,
         to_regclass('public.household_members') is not null as members
)
select scenarios and runs and envelopes and accounts and members as pre_migration_ready,
       scenarios, runs, envelopes, accounts, members,
       concat_ws('; ', case when not scenarios then 'budget_scenarios missing' end, case when not runs then 'budget_allocation_runs missing' end, case when not envelopes then 'envelopes missing' end, case when not accounts then 'accounts missing' end, case when not members then 'household_members missing' end) as blocking_details
from checks;
