-- Strictly read-only checkpoint after 202608080003 and before 202608080004.
-- One final row is returned for direct CSV export from Supabase SQL Editor.
with
required_objects(object_name, object_kind) as (
  values
    ('financial_events', 'table'), ('obligations', 'table'),
    ('obligation_settlements', 'table'), ('budget_funding_links', 'table'),
    ('obligation_balances', 'view')
),
object_state as (
  select object_name,
    case object_kind
      when 'table' then to_regclass(format('public.%I', object_name)) is not null
      when 'view' then exists (
        select 1 from pg_views where schemaname = 'public' and viewname = object_name
      )
    end as exists_now
  from required_objects
),
event_columns as (
  select
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'financial_transactions'
        and column_name = 'event_id' and udt_name = 'uuid' and is_nullable = 'YES'
    ) as financial_transactions_event_id_exists,
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'envelope_movements'
        and column_name = 'event_id' and udt_name = 'uuid' and is_nullable = 'YES'
    ) as envelope_movements_event_id_exists
),
constraint_state as (
  select
    exists (select 1 from pg_constraint where conname = 'financial_transactions_event_household_fk') as financial_transactions_event_fk,
    exists (select 1 from pg_constraint where conname = 'envelope_movements_event_household_fk') as envelope_movements_event_fk,
    exists (
      select 1 from pg_constraint constraints
      join pg_class classes on classes.oid = constraints.conrelid
      join pg_namespace namespaces on namespaces.oid = classes.relnamespace
      where namespaces.nspname = 'public' and classes.relname = 'financial_events'
        and constraints.contype = 'u'
        and pg_get_constraintdef(constraints.oid) like '%UNIQUE NULLS NOT DISTINCT (household_id, idempotency_key)%'
    ) as idempotency_unique,
    exists (
      select 1 from pg_constraint constraints
      join pg_class classes on classes.oid = constraints.conrelid
      join pg_namespace namespaces on namespaces.oid = classes.relnamespace
      where namespaces.nspname = 'public' and classes.relname = 'obligations'
        and constraints.contype = 'c'
        and pg_get_constraintdef(constraints.oid) like '%debt%'
        and pg_get_constraintdef(constraints.oid) like '%receivable%'
    ) as obligation_kind_check,
    exists (
      select 1 from pg_constraint constraints
      join pg_class classes on classes.oid = constraints.conrelid
      join pg_namespace namespaces on namespaces.oid = classes.relnamespace
      where namespaces.nspname = 'public' and classes.relname = 'obligations'
        and constraints.contype = 'c'
        and pg_get_constraintdef(constraints.oid) like '%receivable_kind%'
        and pg_get_constraintdef(constraints.oid) like '%income%'
        and pg_get_constraintdef(constraints.oid) like '%recovery%'
    ) as receivable_kind_check,
    exists (
      select 1 from pg_constraint constraints
      join pg_class classes on classes.oid = constraints.conrelid
      join pg_namespace namespaces on namespaces.oid = classes.relnamespace
      where namespaces.nspname = 'public' and classes.relname = 'obligation_settlements'
        and constraints.contype = 'f'
        and pg_get_constraintdef(constraints.oid) like '%obligations%'
    ) as settlement_obligation_fk,
    exists (
      select 1 from pg_constraint constraints
      join pg_class classes on classes.oid = constraints.conrelid
      join pg_namespace namespaces on namespaces.oid = classes.relnamespace
      where namespaces.nspname = 'public' and classes.relname = 'budget_funding_links'
        and constraints.contype = 'f'
        and pg_get_constraintdef(constraints.oid) like '%accounts%'
    ) and exists (
      select 1 from pg_constraint constraints
      join pg_class classes on classes.oid = constraints.conrelid
      join pg_namespace namespaces on namespaces.oid = classes.relnamespace
      where namespaces.nspname = 'public' and classes.relname = 'budget_funding_links'
        and constraints.contype = 'f'
        and pg_get_constraintdef(constraints.oid) like '%envelopes%'
    ) as budget_funding_fks
),
immutability_state as (
  select
    exists (select 1 from pg_proc where proname = 'prevent_financial_event_mutation')
    and exists (select 1 from pg_trigger where tgname = 'financial_events_immutable' and not tgisinternal)
    and exists (select 1 from pg_trigger where tgname = 'obligations_immutable' and not tgisinternal)
    and exists (select 1 from pg_trigger where tgname = 'obligation_settlements_immutable' and not tgisinternal)
    and exists (select 1 from pg_trigger where tgname = 'budget_funding_links_immutable' and not tgisinternal)
    and exists (select 1 from pg_trigger where tgname = 'obligation_settlements_limit' and tgconstraint <> 0)
      as ready
),
rls_state as (
  select
    (select relrowsecurity from pg_class where oid = to_regclass('public.financial_events'))
    and (select relrowsecurity from pg_class where oid = to_regclass('public.obligations'))
    and (select relrowsecurity from pg_class where oid = to_regclass('public.obligation_settlements'))
    and (select relrowsecurity from pg_class where oid = to_regclass('public.budget_funding_links'))
    and (select count(*) from pg_policies where schemaname = 'public'
      and tablename in ('financial_events', 'obligations', 'obligation_settlements', 'budget_funding_links')
      and cmd = 'SELECT') = 4 as ready
),
permission_state as (
  select
    has_table_privilege('authenticated', 'public.financial_events', 'select')
    and has_table_privilege('authenticated', 'public.obligations', 'select')
    and has_table_privilege('authenticated', 'public.obligation_settlements', 'select')
    and has_table_privilege('authenticated', 'public.budget_funding_links', 'select')
    and not has_table_privilege('authenticated', 'public.financial_events', 'insert')
    and not has_table_privilege('authenticated', 'public.obligations', 'insert')
    and not has_table_privilege('authenticated', 'public.obligation_settlements', 'insert')
    and not has_table_privilege('authenticated', 'public.budget_funding_links', 'insert') as ready
),
dependencies_080004 as (
  select
    exists (select 1 from pg_proc where proname = 'is_household_member')
    and exists (select 1 from pg_proc where proname = 'ensure_household_system_envelope')
    and exists (
      select 1 from pg_constraint constraints
      join pg_class classes on classes.oid = constraints.conrelid
      where classes.relname = 'accounts' and constraints.conname = 'accounts_kind_check'
        and pg_get_constraintdef(constraints.oid) like '%ledger%'
    )
    and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'financial_transactions' and column_name = 'event_id')
    and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'envelope_movements' and column_name = 'event_id') as ready
),
data_state as (
  select
    (select count(*) from public.financial_events) as financial_events_count,
    (select count(*) from public.obligations) as obligations_count,
    (select count(*) from public.obligation_settlements) as obligation_settlements_count,
    (select count(*) from public.budget_funding_links) as budget_funding_links_count,
    (select count(*) from public.financial_transactions where event_id is null) as legacy_financial_transactions_event_id_null_count,
    (select count(*) from public.envelope_movements where event_id is null) as legacy_envelope_movements_event_id_null_count,
    (select count(*) from public.financial_transactions where event_id is not null) as linked_financial_transaction_count,
    (select count(*) from public.envelope_movements where event_id is not null) as linked_envelope_movement_count
),
flags as (
  select
    coalesce((select exists_now from object_state where object_name = 'financial_events'), false) as financial_events_exists,
    coalesce((select exists_now from object_state where object_name = 'obligations'), false) as obligations_exists,
    coalesce((select exists_now from object_state where object_name = 'obligation_settlements'), false) as obligation_settlements_exists,
    coalesce((select exists_now from object_state where object_name = 'budget_funding_links'), false) as budget_funding_links_exists,
    coalesce((select exists_now from object_state where object_name = 'obligation_balances'), false) as obligation_balances_exists,
    event_columns.financial_transactions_event_id_exists,
    event_columns.envelope_movements_event_id_exists,
    rls_state.ready as rls_ready,
    (constraint_state.financial_transactions_event_fk and constraint_state.envelope_movements_event_fk
      and constraint_state.settlement_obligation_fk and constraint_state.budget_funding_fks) as foreign_keys_ready,
    constraint_state.financial_transactions_event_fk and constraint_state.envelope_movements_event_fk
      and constraint_state.idempotency_unique and constraint_state.obligation_kind_check
      and constraint_state.receivable_kind_check
      and constraint_state.settlement_obligation_fk and constraint_state.budget_funding_fks as constraints_ready,
    immutability_state.ready as immutability_ready,
    constraint_state.idempotency_unique as idempotency_foundation_ready,
    constraint_state.obligation_kind_check and constraint_state.receivable_kind_check
      and constraint_state.settlement_obligation_fk as obligations_foundation_ready,
    constraint_state.budget_funding_fks as budget_funding_foundation_ready,
    dependencies_080004.ready as dependencies_for_080004_ready,
    permission_state.ready as permissions_ready,
    data_state.*
  from event_columns, constraint_state, immutability_state, rls_state,
    permission_state, dependencies_080004, data_state
),
diagnostics as (
  select 'blocker' as severity, object_name || ' is absent' as detail
  from object_state where not exists_now
  union all select 'blocker', 'financial_transactions.event_id is missing, not UUID, or not nullable'
  from flags where not financial_transactions_event_id_exists
  union all select 'blocker', 'envelope_movements.event_id is missing, not UUID, or not nullable'
  from flags where not envelope_movements_event_id_exists
  union all select 'blocker', 'expected FinancialEvent foreign keys or constraints are missing'
  from flags where not constraints_ready
  union all select 'blocker', 'FinancialEvent immutability trigger foundation is incomplete'
  from flags where not immutability_ready
  union all select 'blocker', 'FinancialEvent RLS policies are incomplete'
  from flags where not rls_ready
  union all select 'blocker', 'FinancialEvent direct-table permissions are incompatible'
  from flags where not permissions_ready
  union all select 'blocker', '080004 legacy dependencies are incomplete'
  from flags where not dependencies_for_080004_ready
),
warning_diagnostics as (
  select 'warning' as severity, 'FinancialEvent-native rows already exist before 080004' as detail
  from flags where linked_financial_transaction_count > 0 or linked_envelope_movement_count > 0
)
select
  not exists (select 1 from diagnostics) as after_080003_ready,
  not exists (select 1 from diagnostics) and flags.dependencies_for_080004_ready as ready_for_080004,
  count(diagnostics.detail) as blocking_issue_count,
  (select count(*) from warning_diagnostics) as warning_count,
  flags.financial_events_exists,
  flags.obligations_exists,
  flags.obligation_settlements_exists,
  flags.budget_funding_links_exists,
  flags.obligation_balances_exists,
  flags.financial_transactions_event_id_exists,
  flags.envelope_movements_event_id_exists,
  flags.legacy_financial_transactions_event_id_null_count,
  flags.legacy_envelope_movements_event_id_null_count,
  flags.rls_ready,
  flags.constraints_ready,
  flags.foreign_keys_ready,
  flags.immutability_ready,
  flags.idempotency_foundation_ready,
  flags.obligations_foundation_ready,
  flags.budget_funding_foundation_ready,
  flags.dependencies_for_080004_ready,
  coalesce(jsonb_agg(diagnostics.detail order by diagnostics.detail)
    filter (where diagnostics.detail is not null), '[]'::jsonb) as blocking_details,
  coalesce((select jsonb_agg(detail order by detail) from warning_diagnostics), '[]'::jsonb) as warnings
from flags
left join diagnostics on true
group by
  flags.financial_events_exists, flags.obligations_exists,
  flags.obligation_settlements_exists, flags.budget_funding_links_exists,
  flags.obligation_balances_exists, flags.financial_transactions_event_id_exists,
  flags.envelope_movements_event_id_exists,
  flags.legacy_financial_transactions_event_id_null_count,
  flags.legacy_envelope_movements_event_id_null_count, flags.rls_ready,
  flags.constraints_ready, flags.foreign_keys_ready, flags.immutability_ready,
  flags.idempotency_foundation_ready, flags.obligations_foundation_ready,
  flags.budget_funding_foundation_ready, flags.dependencies_for_080004_ready;
