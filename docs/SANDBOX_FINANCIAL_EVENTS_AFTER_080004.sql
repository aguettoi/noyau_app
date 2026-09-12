-- Strictly read-only checkpoint after 080003 + 080004.
-- One CSV-exportable row; it never changes Sandbox data.
with
expected_rpcs(routine_name, arg_types, arg_names) as (
  values
    ('create_cash_expense_event', array['uuid','timestamptz','text','numeric','uuid','jsonb','text','uuid']::regtype[], array['p_household_id','p_occurred_at','p_description','p_amount','p_source_account_id','p_envelope_allocations','p_notes','p_idempotency_key']),
    ('create_debt_expense_event', array['uuid','timestamptz','text','numeric','jsonb','text','date','text','uuid']::regtype[], array['p_household_id','p_occurred_at','p_description','p_amount','p_envelope_allocations','p_creditor_name','p_due_at','p_notes','p_idempotency_key']),
    ('settle_debt_event', array['uuid','uuid','timestamptz','text','numeric','uuid','text','uuid']::regtype[], array['p_household_id','p_obligation_id','p_occurred_at','p_description','p_amount','p_source_account_id','p_notes','p_idempotency_key']),
    ('create_income_receivable_event', array['uuid','timestamptz','text','numeric','text','date','text','uuid']::regtype[], array['p_household_id','p_occurred_at','p_description','p_amount','p_debtor_name','p_due_at','p_notes','p_idempotency_key']),
    ('settle_receivable_event', array['uuid','uuid','timestamptz','text','numeric','uuid','text','uuid']::regtype[], array['p_household_id','p_obligation_id','p_occurred_at','p_description','p_amount','p_destination_account_id','p_notes','p_idempotency_key']),
    ('create_recovery_receivable_event', array['uuid','uuid','uuid','timestamptz','text','numeric','text','date','text','uuid']::regtype[], array['p_household_id','p_source_event_id','p_source_envelope_id','p_occurred_at','p_description','p_amount','p_debtor_name','p_due_at','p_notes','p_idempotency_key']),
    ('settle_recovery_event', array['uuid','uuid','timestamptz','text','numeric','uuid','boolean','text','uuid']::regtype[], array['p_household_id','p_obligation_id','p_occurred_at','p_description','p_amount','p_destination_account_id','p_refund_source_envelope','p_notes','p_idempotency_key']),
    ('allocate_budget_event', array['uuid','timestamptz','text','numeric','uuid','uuid','text','uuid']::regtype[], array['p_household_id','p_occurred_at','p_description','p_amount','p_source_account_id','p_destination_envelope_id','p_notes','p_idempotency_key']),
    ('create_account_transfer_event', array['uuid','timestamptz','text','numeric','uuid','uuid','text','uuid']::regtype[], array['p_household_id','p_occurred_at','p_description','p_amount','p_source_account_id','p_destination_account_id','p_notes','p_idempotency_key']),
    ('create_envelope_transfer_event', array['uuid','timestamptz','text','numeric','uuid','uuid','text','uuid']::regtype[], array['p_household_id','p_occurred_at','p_description','p_amount','p_source_envelope_id','p_destination_envelope_id','p_notes','p_idempotency_key'])
),
rpc_state as (
  select expected_rpcs.routine_name, procedures.oid is not null as exists_now,
    array(select unnest(procedures.proargtypes::oid[])) = expected_rpcs.arg_types::oid[]
      and procedures.proargnames = expected_rpcs.arg_names
      and procedures.prorettype = 'uuid'::regtype as exact_signature,
    procedures.prosecdef as security_definer,
    coalesce(array_to_string(procedures.proconfig, ', '), '') like '%search_path=public%' as safe_search_path,
    pg_get_function_identity_arguments(procedures.oid) as actual_signature,
    has_function_privilege('authenticated', procedures.oid, 'execute') as authenticated_execute,
    not has_function_privilege('anon', procedures.oid, 'execute') as anon_blocked
  from expected_rpcs
  left join pg_namespace namespaces on namespaces.nspname = 'public'
  left join pg_proc procedures on procedures.pronamespace = namespaces.oid and procedures.proname = expected_rpcs.routine_name
),
objects as (
  select
    to_regclass('public.financial_events') is not null as financial_events_exists,
    to_regclass('public.obligations') is not null as obligations_exists,
    to_regclass('public.obligation_settlements') is not null as obligation_settlements_exists,
    to_regclass('public.budget_funding_links') is not null as budget_funding_links_exists,
    exists (select 1 from pg_views where schemaname = 'public' and viewname = 'obligation_balances') as obligation_balances_exists,
    exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'financial_transactions' and column_name = 'event_id' and udt_name = 'uuid') as financial_transactions_event_id_exists,
    exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'envelope_movements' and column_name = 'event_id' and udt_name = 'uuid') as envelope_movements_event_id_exists
),
foundation as (
  select
    exists (select 1 from pg_constraint where conname = 'financial_transactions_event_household_fk') and exists (select 1 from pg_constraint where conname = 'envelope_movements_event_household_fk') as foreign_keys_ready,
    exists (select 1 from pg_constraint constraints join pg_class classes on classes.oid = constraints.conrelid where classes.relname = 'financial_events' and pg_get_constraintdef(constraints.oid) like '%UNIQUE NULLS NOT DISTINCT (household_id, idempotency_key)%') as idempotency_ready,
    exists (select 1 from pg_constraint constraints join pg_class classes on classes.oid = constraints.conrelid where classes.relname = 'obligations' and constraints.contype = 'c' and pg_get_constraintdef(constraints.oid) like '%debt%' and pg_get_constraintdef(constraints.oid) like '%receivable%') and exists (select 1 from pg_constraint constraints join pg_class classes on classes.oid = constraints.conrelid where classes.relname = 'obligations' and constraints.contype = 'c' and pg_get_constraintdef(constraints.oid) like '%receivable_kind%' and pg_get_constraintdef(constraints.oid) like '%income%' and pg_get_constraintdef(constraints.oid) like '%recovery%') as obligations_ready,
    exists (select 1 from pg_trigger where tgname = 'financial_events_immutable' and not tgisinternal) and exists (select 1 from pg_trigger where tgname = 'obligations_immutable' and not tgisinternal) and exists (select 1 from pg_trigger where tgname = 'obligation_settlements_immutable' and not tgisinternal) and exists (select 1 from pg_trigger where tgname = 'budget_funding_links_immutable' and not tgisinternal) as immutability_ready,
    (select count(*) from pg_policies where schemaname = 'public' and tablename in ('financial_events','obligations','obligation_settlements','budget_funding_links') and cmd = 'SELECT') = 4 as rls_ready,
    exists (select 1 from pg_proc where proname = 'create_financial_transaction_with_envelopes') and exists (select 1 from pg_proc where proname = 'create_envelope_transfer') and exists (select 1 from pg_proc where proname = 'ensure_household_system_envelope') as legacy_rpc_compatibility_ready
),
data_state as (
  select (select count(*) from public.financial_transactions where event_id is null) as legacy_transaction_null_event_count,
    (select count(*) from public.envelope_movements where event_id is null) as legacy_movement_null_event_count
),
diagnostics as (
  select 'FinancialEvent objects or event_id columns are missing' as detail from objects where not (financial_events_exists and obligations_exists and obligation_settlements_exists and budget_funding_links_exists and obligation_balances_exists and financial_transactions_event_id_exists and envelope_movements_event_id_exists)
  union all select 'FinancialEvent foreign keys, constraints, RLS, or immutability are incomplete' from foundation where not (foreign_keys_ready and idempotency_ready and obligations_ready and rls_ready and immutability_ready)
  union all select routine_name || ' is absent, signature/security/rights differ' from rpc_state where not (exists_now and exact_signature and security_definer and safe_search_path and authenticated_execute and anon_blocked)
)
select
  not exists (select 1 from diagnostics) as after_080004_ready,
  not exists (select 1 from diagnostics) as ready_for_business_tests,
  count(diagnostics.detail) as blocking_issue_count,
  case when data_state.legacy_transaction_null_event_count > 0 or data_state.legacy_movement_null_event_count > 0 then 1 else 0 end as warning_count,
  objects.financial_events_exists, objects.obligations_exists, objects.obligation_settlements_exists, objects.budget_funding_links_exists, objects.obligation_balances_exists, objects.financial_transactions_event_id_exists, objects.envelope_movements_event_id_exists,
  (select jsonb_object_agg(routine_name, jsonb_build_object('exists', exists_now, 'exact_signature', exact_signature, 'actual_signature', actual_signature, 'authenticated_execute', authenticated_execute, 'anon_blocked', anon_blocked)) from rpc_state) as rpc_checks,
  foundation.foreign_keys_ready, foundation.idempotency_ready, foundation.obligations_ready, foundation.rls_ready, foundation.immutability_ready, foundation.legacy_rpc_compatibility_ready,
  data_state.legacy_transaction_null_event_count, data_state.legacy_movement_null_event_count,
  coalesce(jsonb_agg(diagnostics.detail order by diagnostics.detail) filter (where diagnostics.detail is not null), '[]'::jsonb) as blocking_details,
  case when data_state.legacy_transaction_null_event_count > 0 or data_state.legacy_movement_null_event_count > 0 then jsonb_build_array('legacy rows with NULL event_id are preserved') else '[]'::jsonb end as warnings,
  jsonb_build_object('phase', 'structure complete; no business operation executed') as information
from objects cross join foundation cross join data_state left join diagnostics on true
group by objects.financial_events_exists, objects.obligations_exists, objects.obligation_settlements_exists, objects.budget_funding_links_exists, objects.obligation_balances_exists, objects.financial_transactions_event_id_exists, objects.envelope_movements_event_id_exists, foundation.foreign_keys_ready, foundation.idempotency_ready, foundation.obligations_ready, foundation.rls_ready, foundation.immutability_ready, foundation.legacy_rpc_compatibility_ready, data_state.legacy_transaction_null_event_count, data_state.legacy_movement_null_event_count;
