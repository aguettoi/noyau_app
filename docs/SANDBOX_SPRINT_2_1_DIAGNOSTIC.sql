-- Sprint 2.1 -- diagnostic read-only before replaying the migration.
-- Run this script as a whole in the noyau-app-sandbox SQL Editor and share its result.
-- It is safe whether the prior migration was rolled back, partially applied, or absent.

with expected_columns(table_name, column_name) as (
  values
    ('accounts', 'is_system'),
    ('financial_transactions', 'currency_code'),
    ('financial_transactions', 'source_account_id'),
    ('financial_transactions', 'destination_account_id'),
    ('financial_transactions', 'category_id'),
    ('financial_transactions', 'description'),
    ('financial_transactions', 'amount'),
    ('financial_transactions', 'notes'),
    ('financial_transactions', 'updated_at'),
    ('financial_transactions', 'archived_at'),
    ('financial_transactions', 'validated_at'),
    ('financial_transaction_lines', 'debit'),
    ('financial_transaction_lines', 'credit'),
    ('financial_transaction_lines', 'occurred_at')
),
existing_columns as (
  select table_name, column_name
  from information_schema.columns
  where table_schema = 'public'
),
expected_functions(routine_name) as (
  values
    ('create_ledger_transaction'),
    ('ensure_household_ledger_system_account'),
    ('assert_financial_transaction_balanced')
),
expected_constraints(constraint_name) as (
  values
    ('accounts_kind_check'),
    ('accounts_system_kind_check'),
    ('financial_transactions_type_check'),
    ('financial_transaction_lines_debit_credit_check')
)
select
  (select count(*) = (select count(*) from expected_columns)
   from expected_columns
   join existing_columns using (table_name, column_name)) as expected_columns_exist,
  (select count(*) = (select count(*) from expected_functions)
   from expected_functions
   join pg_proc procedures on procedures.proname = expected_functions.routine_name
   join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
   where namespaces.nspname = 'public') as expected_functions_exist,
  exists (
    select 1
    from pg_views
    where schemaname = 'public' and viewname = 'account_ledger_balances'
  ) as account_ledger_balances_view_exists,
  (select count(*) = (select count(*) from expected_constraints)
   from expected_constraints
   join pg_constraint constraints_catalog
     on constraints_catalog.conname = expected_constraints.constraint_name
   join pg_class relation on relation.oid = constraints_catalog.conrelid
   join pg_namespace namespaces on namespaces.oid = relation.relnamespace
   where namespaces.nspname = 'public') as expected_constraints_exist,
  exists (
    select 1
    from information_schema.triggers
    where trigger_schema = 'public'
      and event_object_table = 'financial_transaction_lines'
  ) as financial_transaction_lines_trigger_exists,
  exists (
    select 1
    from pg_policies
    where schemaname = 'public' and tablename = 'accounts'
  ) as accounts_policy_exists,
  exists (
    select 1
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and routine_name in (
        'create_ledger_transaction',
        'ensure_household_ledger_system_account'
      )
      and grantee = 'authenticated'
      and privilege_type = 'EXECUTE'
  ) as authenticated_execute_exists,
  (select count(*) = 3
   from existing_columns
   where table_name = 'financial_transaction_lines'
     and column_name in ('debit', 'credit', 'occurred_at'))
    as financial_transaction_lines_analysis_possible;

select
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'accounts' and column_name = 'is_system')
    or (table_name = 'financial_transactions' and column_name in (
      'currency_code', 'source_account_id', 'destination_account_id',
      'category_id', 'description', 'amount', 'notes', 'updated_at',
      'archived_at', 'validated_at'
    ))
    or (table_name = 'financial_transaction_lines' and column_name in (
      'debit', 'credit', 'occurred_at'
    ))
  )
order by table_name, ordinal_position;

select
  procedures.proname as routine_name,
  pg_get_function_identity_arguments(procedures.oid) as arguments,
  procedures.prosecdef as security_definer,
  procedures.proconfig as configuration
from pg_proc procedures
join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
where namespaces.nspname = 'public'
  and procedures.proname in (
    'create_ledger_transaction',
    'ensure_household_ledger_system_account',
    'assert_financial_transaction_balanced'
  )
order by procedures.proname;

select viewname, definition
from pg_views
where schemaname = 'public' and viewname = 'account_ledger_balances';

select
  relation.relname as table_name,
  constraints_catalog.conname,
  pg_get_constraintdef(constraints_catalog.oid) as definition
from pg_constraint constraints_catalog
join pg_class relation on relation.oid = constraints_catalog.conrelid
join pg_namespace namespace on namespace.oid = relation.relnamespace
where namespace.nspname = 'public'
  and relation.relname in ('accounts', 'financial_transactions', 'financial_transaction_lines')
  and constraints_catalog.conname in (
    'accounts_kind_check',
    'accounts_system_kind_check',
    'financial_transactions_type_check',
    'financial_transaction_lines_debit_credit_check'
  )
order by table_name, constraints_catalog.conname;

select
  event_object_table as table_name,
  trigger_name,
  action_timing,
  event_manipulation,
  action_condition,
  action_statement
from information_schema.triggers
where trigger_schema = 'public'
  and event_object_table = 'financial_transaction_lines';

select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'accounts'
order by policyname;

select
  routine_privileges.routine_name,
  grantee,
  privilege_type
from information_schema.routine_privileges routine_privileges
where routine_privileges.routine_schema = 'public'
  and routine_privileges.routine_name in (
    'create_ledger_transaction',
    'ensure_household_ledger_system_account'
  )
order by routine_privileges.routine_name, grantee;

-- This script intentionally does not inspect posting values directly.  When
-- debit, credit, or occurred_at are absent, any direct query would fail before
-- reporting the schema state.  The first result reports whether that analysis
-- becomes possible after the migration is present.
