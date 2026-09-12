-- Sprint 2.2 / Lot 1 -- diagnostic préalable, lecture seule.
-- Exécutable tel quel dans Supabase SQL Editor avant 202608050002_envelope_ledger.sql.

-- 1. Prérequis de tables et colonnes utilisés par la migration.
select
  tables.table_name,
  columns.column_name,
  columns.data_type,
  columns.is_nullable
from information_schema.tables tables
left join information_schema.columns columns
  on columns.table_schema = tables.table_schema
 and columns.table_name = tables.table_name
where tables.table_schema = 'public'
  and tables.table_name in (
    'envelopes',
    'financial_transactions',
    'financial_transaction_lines',
    'households',
    'household_members',
    'envelope_movements'
  )
order by tables.table_name, columns.ordinal_position;

-- 2. Contraintes existantes susceptibles d'interagir avec envelopes ou le ledger.
select
  classes.relname as table_name,
  constraints.conname as constraint_name,
  constraints.contype as constraint_type,
  pg_get_constraintdef(constraints.oid) as definition
from pg_constraint constraints
join pg_class classes on classes.oid = constraints.conrelid
join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public'
  and classes.relname in (
    'envelopes',
    'financial_transactions',
    'financial_transaction_lines',
    'envelope_movements'
  )
order by classes.relname, constraints.conname;

-- 3. RLS et policies existantes : aucune politique d'écriture ne doit exister
-- pour envelope_movements après la migration.
select
  schemaname,
  tablename,
  policyname,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('envelopes', 'financial_transactions', 'envelope_movements')
order by tablename, policyname;

-- 4. Vues de reporting historiques à conserver pendant la transition.
select
  views.table_name as view_name,
  views.view_definition
from information_schema.views views
where views.table_schema = 'public'
  and views.table_name in (
    'envelope_balances',
    'envelope_monthly_movements',
    'envelope_ledger_balances'
  )
order by views.table_name;

-- 5. Fonctions et triggers déjà présents.
select
  routines.routine_name,
  routines.routine_type,
  routines.data_type
from information_schema.routines routines
where routines.specific_schema = 'public'
  and routines.routine_name in (
    'is_household_member',
    'create_financial_transaction',
    'create_ledger_transaction',
    'ensure_household_system_envelope',
    'create_envelope_transfer',
    'assert_envelope_movement_group'
  )
order by routines.routine_name;

select
  trigger_name,
  event_object_table as table_name,
  action_timing,
  event_manipulation,
  action_statement
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table in ('envelopes', 'envelope_movements')
order by event_object_table, trigger_name;

-- 6. Données historiques : aucun mouvement n'est créé ou déduit ici.
select
  envelopes.household_id,
  count(*) as envelope_count,
  count(*) filter (where envelopes.archived_at is null) as active_envelope_count,
  count(*) filter (where lower(trim(envelopes.name)) = lower('À répartir'))
    as to_allocate_name_collisions
from public.envelopes
group by envelopes.household_id
order by envelopes.household_id;

select
  transactions.household_id,
  count(*) as legacy_transaction_count,
  count(*) filter (where transactions.envelope_id is not null)
    as legacy_transactions_linked_to_envelope
from public.transactions transactions
group by transactions.household_id
order by transactions.household_id;

select
  financial.household_id,
  count(*) as financial_transaction_count,
  count(*) filter (where lines.envelope_id is not null)
    as financial_lines_linked_to_envelope
from public.financial_transactions financial
left join public.financial_transaction_lines lines
  on lines.transaction_id = financial.id
group by financial.household_id
order by financial.household_id;

-- 7. Détecte un résidu d'une tentative antérieure de cette migration.
select
  exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'envelope_movements'
  ) as envelope_movements_exists,
  exists (
    select 1 from information_schema.views
    where table_schema = 'public' and table_name = 'envelope_ledger_balances'
  ) as envelope_ledger_balances_exists,
  exists (
    select 1 from information_schema.routines
    where specific_schema = 'public' and routine_name = 'create_envelope_transfer'
  ) as transfer_rpc_exists;
