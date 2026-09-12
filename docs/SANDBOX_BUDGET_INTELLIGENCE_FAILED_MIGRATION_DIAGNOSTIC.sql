-- Read-only: a failed transactional application must leave no new objects.
with expected(object_name, object_kind) as (
  values
    ('budget_scenarios', 'table'), ('budget_scenario_rules', 'table'),
    ('budget_allocation_runs', 'table'), ('budget_allocation_run_lines', 'table'),
    ('budget_goals', 'table'), ('budget_envelope_reporting', 'view')
), found as (
  select expected.object_name, expected.object_kind,
    case when expected.object_kind = 'table' then exists(
      select 1 from information_schema.tables t where t.table_schema = 'public' and t.table_name = expected.object_name
    ) else exists(
      select 1 from information_schema.views v where v.table_schema = 'public' and v.table_name = expected.object_name
    ) end as present
  from expected
), payload as (
  select coalesce(jsonb_agg(jsonb_build_object('object', object_name, 'kind', object_kind) order by object_name) filter (where present), '[]'::jsonb) as objects_found
  from found
)
select (payload.objects_found = '[]'::jsonb) as failed_migration_clean,
  payload.objects_found,
  case when payload.objects_found = '[]'::jsonb then '[]'::jsonb else jsonb_build_array('New Budget Intelligence objects remain after the failed transaction.') end as blocking_details
from payload;
