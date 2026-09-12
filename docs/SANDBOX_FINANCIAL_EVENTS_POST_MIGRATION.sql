-- Strictly read-only postflight for 202608080003 + 202608080004.
-- Catalog-only: it reports partial/failed application as absent instead of
-- raising because a future relation or column is unavailable.

with expected_objects(object_name, object_kind) as (
  values
    ('financial_events', 'table'), ('obligations', 'table'),
    ('obligation_settlements', 'table'), ('budget_funding_links', 'table'),
    ('obligation_balances', 'view')
)
select expected_objects.object_name, expected_objects.object_kind,
  case expected_objects.object_kind
    when 'table' then to_regclass(format('public.%I', expected_objects.object_name)) is not null
    when 'view' then exists (select 1 from pg_views where schemaname = 'public' and viewname = expected_objects.object_name)
  end as exists_after_migration
from expected_objects
order by expected_objects.object_kind, expected_objects.object_name;

select columns.table_name, columns.column_name, columns.data_type,
       columns.udt_name, columns.is_nullable, columns.column_default
from information_schema.columns columns
where columns.table_schema = 'public'
  and columns.table_name in (
    'financial_events', 'obligations', 'obligation_settlements',
    'budget_funding_links', 'financial_transactions', 'envelope_movements'
  )
  and (
    columns.table_name in ('financial_events', 'obligations', 'obligation_settlements', 'budget_funding_links')
    or columns.column_name = 'event_id'
  )
order by columns.table_name, columns.ordinal_position;

select classes.relname as table_name,
       constraints.conname, constraints.contype,
       pg_get_constraintdef(constraints.oid) as definition
from pg_constraint constraints
join pg_namespace namespaces on namespaces.oid = constraints.connamespace
join pg_class classes on classes.oid = constraints.conrelid
where namespaces.nspname = 'public'
  and constraints.conname in (
    'financial_transactions_event_household_fk',
    'envelope_movements_event_household_fk'
  )
order by constraints.conname;

select indexes.tablename, indexes.indexname, indexes.indexdef
from pg_indexes indexes
where indexes.schemaname = 'public'
  and indexes.indexname in (
    'financial_transactions_event_idx', 'envelope_movements_event_idx',
    'obligations_household_open_idx', 'obligation_settlements_obligation_idx',
    'budget_funding_links_event_idx'
  )
order by indexes.indexname;

with expected_functions(routine_name, is_public_rpc) as (
  values
    ('create_or_get_financial_event', false), ('create_cash_expense_event', true),
    ('create_debt_expense_event', true), ('settle_debt_event', true),
    ('create_income_receivable_event', true), ('settle_receivable_event', true),
    ('create_recovery_receivable_event', true), ('settle_recovery_event', true),
    ('allocate_budget_event', true), ('create_account_transfer_event', true),
    ('create_envelope_transfer_event', true)
)
select expected_functions.routine_name, expected_functions.is_public_rpc,
       procedures.proname is not null as exists_after_migration,
       pg_get_function_identity_arguments(procedures.oid) as signature,
       procedures.prosecdef as security_definer,
       coalesce(array_to_string(procedures.proconfig, ', '), '') as configuration
from expected_functions
left join pg_namespace namespaces on namespaces.nspname = 'public'
left join pg_proc procedures
  on procedures.pronamespace = namespaces.oid
  and procedures.proname = expected_functions.routine_name
order by expected_functions.routine_name, signature nulls first;

select routines.routine_name, privileges.grantee, privileges.privilege_type
from information_schema.routines routines
left join information_schema.routine_privileges privileges
  on privileges.specific_schema = routines.specific_schema
  and privileges.specific_name = routines.specific_name
  and privileges.grantee in ('anon', 'authenticated', 'public')
where routines.routine_schema = 'public'
  and routines.routine_name in (
    'create_or_get_financial_event', 'create_cash_expense_event',
    'create_debt_expense_event', 'settle_debt_event',
    'create_income_receivable_event', 'settle_receivable_event',
    'create_recovery_receivable_event', 'settle_recovery_event',
    'allocate_budget_event', 'create_account_transfer_event',
    'create_envelope_transfer_event'
  )
order by routines.routine_name, privileges.grantee nulls first;

select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('financial_events', 'obligations', 'obligation_settlements', 'budget_funding_links')
order by tablename, policyname;

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('financial_events', 'obligations', 'obligation_settlements', 'budget_funding_links')
  and grantee in ('anon', 'authenticated', 'public')
order by table_name, grantee, privilege_type;

select viewname, definition
from pg_views
where schemaname = 'public' and viewname = 'obligation_balances';

select table_name,
       bool_or(column_name = 'event_id') as event_id_exists,
       max(data_type) filter (where column_name = 'event_id') as event_id_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('financial_transactions', 'envelope_movements')
group by table_name
order by table_name;
