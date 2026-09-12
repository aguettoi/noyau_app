-- Strictly read-only preflight for 202608080003 + 202608080004.
-- Safe before the FinancialEvent objects exist: catalog-only queries never
-- dereference a future table, view, column or RPC.

with expected_objects(object_name, object_kind) as (
  values
    ('financial_events', 'table'),
    ('obligations', 'table'),
    ('obligation_settlements', 'table'),
    ('budget_funding_links', 'table'),
    ('obligation_balances', 'view')
)
select
  expected_objects.object_name,
  expected_objects.object_kind,
  case expected_objects.object_kind
    when 'table' then to_regclass(format('public.%I', expected_objects.object_name)) is not null
    when 'view' then exists (
      select 1 from pg_views
      where schemaname = 'public' and viewname = expected_objects.object_name
    )
  end as already_exists
from expected_objects
order by expected_objects.object_kind, expected_objects.object_name;

with expected_legacy_tables(table_name) as (
  values
    ('households'), ('household_members'), ('accounts'), ('envelopes'),
    ('financial_transactions'), ('financial_transaction_lines'),
    ('envelope_movements'), ('financial_audit_events')
)
select
  expected_legacy_tables.table_name,
  to_regclass(format('public.%I', expected_legacy_tables.table_name)) is not null as exists
from expected_legacy_tables
order by expected_legacy_tables.table_name;

with required_columns(table_name, column_name) as (
  values
    ('accounts', 'id'), ('accounts', 'household_id'), ('accounts', 'is_system'),
    ('accounts', 'kind'), ('accounts', 'name'),
    ('envelopes', 'id'), ('envelopes', 'household_id'), ('envelopes', 'is_system'),
    ('envelopes', 'archived_at'),
    ('financial_transactions', 'id'), ('financial_transactions', 'household_id'),
    ('financial_transactions', 'type'), ('financial_transactions', 'occurred_at'),
    ('financial_transactions', 'amount'), ('financial_transactions', 'reason'),
    ('financial_transactions', 'description'), ('financial_transactions', 'event_id'),
    ('financial_transaction_lines', 'transaction_id'), ('financial_transaction_lines', 'account_id'),
    ('financial_transaction_lines', 'debit'), ('financial_transaction_lines', 'credit'),
    ('envelope_movements', 'household_id'), ('envelope_movements', 'envelope_id'),
    ('envelope_movements', 'financial_transaction_id'), ('envelope_movements', 'event_id'),
    ('envelope_movements', 'movement_group_id'), ('envelope_movements', 'movement_type'),
    ('envelope_movements', 'direction'), ('envelope_movements', 'amount')
)
select
  required_columns.table_name,
  required_columns.column_name,
  columns.data_type,
  columns.udt_name,
  columns.is_nullable,
  columns.column_name is not null as exists_before_migration,
  required_columns.column_name = 'event_id' as added_by_080003
from required_columns
left join information_schema.columns columns
  on columns.table_schema = 'public'
  and columns.table_name = required_columns.table_name
  and columns.column_name = required_columns.column_name
order by required_columns.table_name, required_columns.column_name;

with required_functions(routine_name) as (
  values
    ('is_household_member'), ('ensure_household_system_envelope'),
    ('prevent_financial_event_mutation'), ('create_ledger_transaction'),
    ('create_financial_transaction_with_envelopes'), ('create_envelope_transfer')
)
select
  required_functions.routine_name,
  procedures.proname is not null as exists,
  pg_get_function_identity_arguments(procedures.oid) as signature,
  procedures.prosecdef as security_definer,
  coalesce(array_to_string(procedures.proconfig, ', '), '') as configuration
from required_functions
left join pg_namespace namespaces on namespaces.nspname = 'public'
left join pg_proc procedures
  on procedures.pronamespace = namespaces.oid
  and procedures.proname = required_functions.routine_name
order by required_functions.routine_name, signature nulls first;

with financial_event_rpcs(routine_name) as (
  values
    ('create_or_get_financial_event'), ('create_cash_expense_event'),
    ('create_debt_expense_event'), ('settle_debt_event'),
    ('create_income_receivable_event'), ('settle_receivable_event'),
    ('create_recovery_receivable_event'), ('settle_recovery_event'),
    ('allocate_budget_event'), ('create_account_transfer_event'),
    ('create_envelope_transfer_event')
)
select
  financial_event_rpcs.routine_name,
  procedures.proname is not null as already_exists,
  pg_get_function_identity_arguments(procedures.oid) as signature
from financial_event_rpcs
left join pg_namespace namespaces on namespaces.nspname = 'public'
left join pg_proc procedures
  on procedures.pronamespace = namespaces.oid
  and procedures.proname = financial_event_rpcs.routine_name
order by financial_event_rpcs.routine_name, signature nulls first;

select
  classes.relname as table_name,
  constraints.conname,
  constraints.contype,
  pg_get_constraintdef(constraints.oid) as definition
from pg_constraint constraints
join pg_namespace namespaces on namespaces.oid = constraints.connamespace
join pg_class classes on classes.oid = constraints.conrelid
where namespaces.nspname = 'public'
  and constraints.conrelid in (
    to_regclass('public.financial_transactions'),
    to_regclass('public.envelope_movements'),
    to_regclass('public.accounts'),
    to_regclass('public.envelopes')
  )
order by table_name, constraints.conname;

select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'accounts', 'envelopes', 'financial_transactions',
    'financial_transaction_lines', 'envelope_movements', 'financial_events',
    'obligations', 'obligation_settlements', 'budget_funding_links'
  )
order by tablename, policyname;

-- Final one-row summary for Supabase SQL Editor.  This repeats the catalog
-- checks above in a machine-readable form; it never reads a future relation.
with
future_objects(object_name, object_kind) as (
  values
    ('financial_events', 'table'), ('obligations', 'table'),
    ('obligation_settlements', 'table'), ('budget_funding_links', 'table'),
    ('obligation_balances', 'view')
),
future_object_state as (
  select object_name, object_kind,
    case object_kind
      when 'table' then to_regclass(format('public.%I', object_name)) is not null
      when 'view' then exists (
        select 1 from pg_views where schemaname = 'public' and viewname = object_name
      )
    end as exists_now
  from future_objects
),
required_tables(table_name) as (
  values
    ('accounts'), ('envelopes'), ('envelope_movements'),
    ('financial_transactions'), ('financial_transaction_lines'),
    ('financial_audit_events'), ('households'), ('household_members')
),
required_table_state as (
  select required_tables.table_name,
    classes.relkind = 'r' as is_compatible_table
  from required_tables
  left join pg_namespace namespaces on namespaces.nspname = 'public'
  left join pg_class classes
    on classes.relnamespace = namespaces.oid
    and classes.relname = required_tables.table_name
),
required_columns(table_name, column_name, expected_udt) as (
  values
    ('accounts', 'id', 'uuid'), ('accounts', 'household_id', 'uuid'),
    ('accounts', 'is_system', 'bool'), ('accounts', 'kind', 'text'),
    ('accounts', 'name', 'text'),
    ('envelopes', 'id', 'uuid'), ('envelopes', 'household_id', 'uuid'),
    ('envelopes', 'is_system', 'bool'), ('envelopes', 'archived_at', 'timestamptz'),
    ('financial_transactions', 'id', 'uuid'),
    ('financial_transactions', 'household_id', 'uuid'),
    ('financial_transactions', 'type', 'text'),
    ('financial_transactions', 'occurred_at', 'timestamptz'),
    ('financial_transactions', 'reason', 'text'),
    ('financial_transactions', 'description', 'text'),
    ('financial_transactions', 'amount', 'numeric'),
    ('financial_transactions', 'currency_code', 'text'),
    ('financial_transactions', 'source_account_id', 'uuid'),
    ('financial_transactions', 'destination_account_id', 'uuid'),
    ('financial_transactions', 'notes', 'text'),
    ('financial_transactions', 'created_by', 'uuid'),
    ('financial_transactions', 'validated_at', 'timestamptz'),
    ('financial_transaction_lines', 'transaction_id', 'uuid'),
    ('financial_transaction_lines', 'account_id', 'uuid'),
    ('financial_transaction_lines', 'amount', 'numeric'),
    ('financial_transaction_lines', 'debit', 'numeric'),
    ('financial_transaction_lines', 'credit', 'numeric'),
    ('financial_transaction_lines', 'occurred_at', 'timestamptz'),
    ('envelope_movements', 'household_id', 'uuid'),
    ('envelope_movements', 'envelope_id', 'uuid'),
    ('envelope_movements', 'financial_transaction_id', 'uuid'),
    ('envelope_movements', 'movement_group_id', 'uuid'),
    ('envelope_movements', 'movement_type', 'text'),
    ('envelope_movements', 'direction', 'text'),
    ('envelope_movements', 'amount', 'numeric'),
    ('envelope_movements', 'occurred_at', 'timestamptz'),
    ('envelope_movements', 'description', 'text'),
    ('envelope_movements', 'created_by', 'uuid'),
    ('financial_audit_events', 'household_id', 'uuid'),
    ('financial_audit_events', 'transaction_id', 'uuid'),
    ('financial_audit_events', 'action', 'text'),
    ('financial_audit_events', 'reason', 'text'),
    ('financial_audit_events', 'actor_id', 'uuid'),
    ('household_members', 'household_id', 'uuid'),
    ('household_members', 'user_id', 'uuid')
),
required_column_state as (
  select required_columns.table_name, required_columns.column_name,
    columns.column_name is not null as exists_now,
    columns.udt_name = required_columns.expected_udt as has_expected_type
  from required_columns
  left join information_schema.columns columns
    on columns.table_schema = 'public'
    and columns.table_name = required_columns.table_name
    and columns.column_name = required_columns.column_name
),
required_functions(routine_name) as (
  values ('is_household_member'), ('ensure_household_system_envelope')
),
required_function_state as (
  select required_functions.routine_name, count(procedures.oid) > 0 as exists_now
  from required_functions
  left join pg_namespace namespaces on namespaces.nspname = 'public'
  left join pg_proc procedures
    on procedures.pronamespace = namespaces.oid
    and procedures.proname = required_functions.routine_name
  group by required_functions.routine_name
),
future_rpcs(routine_name) as (
  values
    ('create_or_get_financial_event'), ('create_cash_expense_event'),
    ('create_debt_expense_event'), ('settle_debt_event'),
    ('create_income_receivable_event'), ('settle_receivable_event'),
    ('create_recovery_receivable_event'), ('settle_recovery_event'),
    ('allocate_budget_event'), ('create_account_transfer_event'),
    ('create_envelope_transfer_event')
),
future_rpc_state as (
  select count(procedures.oid) > 0 as any_exists
  from future_rpcs
  left join pg_namespace namespaces on namespaces.nspname = 'public'
  left join pg_proc procedures
    on procedures.pronamespace = namespaces.oid
    and procedures.proname = future_rpcs.routine_name
),
legacy_rls as (
  select
    exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'accounts'
        and policyname = 'members read ordinary accounts' and cmd = 'SELECT'
    )
    and exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'envelope_movements'
        and policyname = 'members read envelope movements' and cmd = 'SELECT'
    ) as ready
),
kind_constraint as (
  select exists (
    select 1 from pg_constraint constraints
    join pg_class classes on classes.oid = constraints.conrelid
    join pg_namespace namespaces on namespaces.oid = classes.relnamespace
    where namespaces.nspname = 'public' and classes.relname = 'accounts'
      and constraints.conname = 'accounts_kind_check'
      and pg_get_constraintdef(constraints.oid) like '%ledger%'
  ) as supports_ledger_system_accounts
),
future_columns as (
  select
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'financial_transactions'
        and column_name = 'event_id'
    ) as financial_transactions_event_id_exists,
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'envelope_movements'
        and column_name = 'event_id'
    ) as envelope_movements_event_id_exists
),
base_flags as (
  select
    coalesce((select exists_now from future_object_state where object_name = 'financial_events'), false) as financial_events_exists,
    coalesce((select exists_now from future_object_state where object_name = 'obligations'), false) as obligations_exists,
    coalesce((select exists_now from future_object_state where object_name = 'obligation_settlements'), false) as obligation_settlements_exists,
    coalesce((select exists_now from future_object_state where object_name = 'budget_funding_links'), false) as budget_funding_links_exists,
    coalesce((select exists_now from future_object_state where object_name = 'obligation_balances'), false) as obligation_balances_exists,
    future_columns.financial_transactions_event_id_exists,
    future_columns.envelope_movements_event_id_exists,
    future_rpc_state.any_exists as orchestration_rpcs_already_exist,
    coalesce((select is_compatible_table from required_table_state where table_name = 'accounts'), false) as accounts_ready,
    coalesce((select is_compatible_table from required_table_state where table_name = 'envelopes'), false) as envelopes_ready,
    coalesce((select is_compatible_table from required_table_state where table_name = 'envelope_movements'), false) as envelope_movements_ready,
    coalesce((select is_compatible_table from required_table_state where table_name = 'financial_transactions'), false) as financial_transactions_ready,
    coalesce((select is_compatible_table from required_table_state where table_name = 'financial_transaction_lines'), false) as financial_transaction_lines_ready,
    coalesce((select is_compatible_table from required_table_state where table_name = 'households'), false)
      and coalesce((select is_compatible_table from required_table_state where table_name = 'household_members'), false)
      and coalesce((select exists_now from required_function_state where routine_name = 'is_household_member'), false) as household_security_dependencies_ready,
    coalesce((select bool_and(exists_now) from required_function_state), false) as required_legacy_functions_ready,
    coalesce((select bool_and(exists_now and has_expected_type) from required_column_state), false) as required_legacy_columns_ready,
    legacy_rls.ready as legacy_rls_ready,
    kind_constraint.supports_ledger_system_accounts,
    exists (
      select 1 from required_table_state where is_compatible_table is not true
    ) as incompatible_objects_detected
  from future_columns, future_rpc_state, legacy_rls, kind_constraint
),
flags as (
  select
    base_flags.*,
    (financial_events_exists or obligations_exists or obligation_settlements_exists
      or budget_funding_links_exists or obligation_balances_exists
      or financial_transactions_event_id_exists or envelope_movements_event_id_exists
      or orchestration_rpcs_already_exist) as naming_conflicts_detected,
    (not required_legacy_columns_ready)
      or not supports_ledger_system_accounts as incompatible_columns_detected
  from base_flags
),
diagnostics as (
  select 'missing_prerequisite' as severity, table_name || ' is missing or not a table' as detail
  from required_table_state where is_compatible_table is not true
  union all
  select 'missing_prerequisite', table_name || '.' || column_name || ' is missing or has an incompatible type'
  from required_column_state where not (exists_now and has_expected_type)
  union all
  select 'missing_prerequisite', routine_name || ' is missing'
  from required_function_state where not exists_now
  union all
  select 'missing_prerequisite', 'accounts_kind_check must allow ledger system accounts'
  from kind_constraint where not supports_ledger_system_accounts
  union all
  select 'missing_prerequisite', 'legacy read-only RLS policies are missing'
  from legacy_rls where not ready
  union all
  select 'conflict', object_name || ' already exists before FinancialEvent migration'
  from future_object_state where exists_now
  union all
  select 'conflict', 'financial_transactions.event_id already exists before FinancialEvent migration'
  from future_columns where financial_transactions_event_id_exists
  union all
  select 'conflict', 'envelope_movements.event_id already exists before FinancialEvent migration'
  from future_columns where envelope_movements_event_id_exists
  union all
  select 'conflict', 'one or more FinancialEvent orchestration RPCs already exist'
  from future_rpc_state where any_exists
)
select
  not exists (select 1 from diagnostics) as pre_migration_ready,
  count(*) filter (where severity in ('missing_prerequisite', 'conflict')) as blocking_issue_count,
  count(*) filter (where severity = 'missing_prerequisite') as missing_prerequisite_count,
  count(*) filter (where severity = 'conflict') as conflict_count,
  flags.financial_events_exists,
  flags.obligations_exists,
  flags.obligation_settlements_exists,
  flags.budget_funding_links_exists,
  flags.obligation_balances_exists,
  flags.financial_transactions_event_id_exists,
  flags.envelope_movements_event_id_exists,
  flags.orchestration_rpcs_already_exist,
  flags.accounts_ready,
  flags.envelopes_ready,
  flags.envelope_movements_ready,
  flags.financial_transactions_ready,
  flags.financial_transaction_lines_ready,
  flags.household_security_dependencies_ready,
  flags.required_legacy_functions_ready,
  flags.required_legacy_columns_ready,
  flags.legacy_rls_ready,
  flags.naming_conflicts_detected,
  flags.incompatible_columns_detected,
  flags.incompatible_objects_detected,
  coalesce(jsonb_agg(diagnostics.detail order by diagnostics.severity, diagnostics.detail)
    filter (where diagnostics.severity in ('missing_prerequisite', 'conflict')), '[]'::jsonb) as blocking_details,
  '[]'::jsonb as warnings
from flags
left join diagnostics on true
group by
  flags.financial_events_exists, flags.obligations_exists,
  flags.obligation_settlements_exists, flags.budget_funding_links_exists,
  flags.obligation_balances_exists, flags.financial_transactions_event_id_exists,
  flags.envelope_movements_event_id_exists, flags.orchestration_rpcs_already_exist,
  flags.accounts_ready, flags.envelopes_ready, flags.envelope_movements_ready,
  flags.financial_transactions_ready, flags.financial_transaction_lines_ready,
  flags.household_security_dependencies_ready, flags.required_legacy_functions_ready,
  flags.required_legacy_columns_ready, flags.legacy_rls_ready,
  flags.naming_conflicts_detected, flags.incompatible_columns_detected,
  flags.incompatible_objects_detected;
