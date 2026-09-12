-- Sprint 2.2 / Lot 2. Read-only pre-application checks.
-- This script deliberately contains SELECT statements only.
with expected_objects(kind, name) as (
  values
    ('table', 'financial_transactions'),
    ('table', 'financial_transaction_lines'),
    ('table', 'envelope_movements'),
    ('table', 'envelopes'),
    ('view', 'account_ledger_balances'),
    ('view', 'envelope_ledger_balances'),
    ('function', 'create_ledger_transaction'),
    ('function', 'create_envelope_transfer'),
    ('function', 'ensure_household_system_envelope')
)
select expected_objects.kind, expected_objects.name,
       case expected_objects.kind
         when 'function' then exists (
           select 1 from pg_proc procedures
           join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
           where namespaces.nspname = 'public' and procedures.proname = expected_objects.name
         )
         else exists (
           select 1 from pg_class classes
           join pg_namespace namespaces on namespaces.oid = classes.relnamespace
           where namespaces.nspname = 'public' and classes.relname = expected_objects.name
         )
       end as exists
from expected_objects
order by expected_objects.kind, expected_objects.name;

select columns.table_name, columns.column_name, columns.data_type, columns.is_nullable
from information_schema.columns columns
where columns.table_schema = 'public'
  and columns.table_name in ('financial_transactions', 'financial_transaction_lines', 'envelope_movements', 'envelopes')
order by columns.table_name, columns.ordinal_position;

select procedures.proname as routine_name,
       pg_get_function_identity_arguments(procedures.oid) as identity_arguments,
       procedures.prosecdef as security_definer,
       coalesce(array_to_string(procedures.proconfig, ', '), '') as configuration
from pg_proc procedures
join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
where namespaces.nspname = 'public'
  and procedures.proname in ('create_ledger_transaction', 'create_envelope_transfer', 'ensure_household_system_envelope')
order by procedures.proname;

select classes.relname as relation_name, classes.relrowsecurity as rls_enabled
from pg_class classes
join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public'
  and classes.relname in ('financial_transactions', 'financial_transaction_lines', 'envelope_movements', 'accounts', 'envelopes')
order by classes.relname;
