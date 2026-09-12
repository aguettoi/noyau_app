-- Sprint 2.2 / Lot 1 -- diagnostic après échec, strictement en lecture seule.
-- Il est sûr si l'ensemble de la transaction a été rollbacké comme si certains
-- objets existent déjà. Aucune table métier n'est lue directement.

-- Résumé des objets attendus.
with expected_objects(object_kind, object_name) as (
  values
    ('table', 'envelope_movements'),
    ('view', 'envelope_ledger_balances'),
    ('function', 'create_envelope_transfer'),
    ('function', 'ensure_household_system_envelope'),
    ('function', 'assert_envelope_movement_group'),
    ('function', 'prevent_envelope_movement_mutation'),
    ('trigger', 'envelope_movements_immutable'),
    ('trigger', 'envelope_movements_group_valid'),
    ('trigger', 'envelopes_protect_system'),
    ('policy', 'members read envelope movements')
)
select
  expected_objects.object_kind,
  expected_objects.object_name,
  case expected_objects.object_kind
    when 'table' then exists (
      select 1 from information_schema.tables tables
      where tables.table_schema = 'public'
        and tables.table_name = expected_objects.object_name
    )
    when 'view' then exists (
      select 1 from information_schema.views views
      where views.table_schema = 'public'
        and views.table_name = expected_objects.object_name
    )
    when 'function' then exists (
      select 1 from information_schema.routines routines
      where routines.specific_schema = 'public'
        and routines.routine_name = expected_objects.object_name
    )
    when 'trigger' then exists (
      select 1 from information_schema.triggers triggers
      where triggers.trigger_schema = 'public'
        and triggers.trigger_name = expected_objects.object_name
    )
    when 'policy' then exists (
      select 1 from pg_policies policies
      where policies.schemaname = 'public'
        and policies.policyname = expected_objects.object_name
    )
  end as exists_after_attempt
from expected_objects
order by expected_objects.object_kind, expected_objects.object_name;

-- Colonnes qui auraient été ajoutées, sans jamais référencer une colonne absente.
select
  columns.table_name,
  columns.column_name,
  columns.data_type,
  columns.is_nullable,
  columns.column_default
from information_schema.columns columns
where columns.table_schema = 'public'
  and (
    (columns.table_name = 'envelopes'
      and columns.column_name in ('is_system', 'system_code'))
    or columns.table_name = 'envelope_movements'
  )
order by columns.table_name, columns.ordinal_position;

-- Contraintes et index spécifiques au Lot 1, y compris les références composées.
select
  classes.relname as table_name,
  constraints.conname as constraint_name,
  constraints.contype as constraint_type,
  pg_get_constraintdef(constraints.oid) as definition
from pg_constraint constraints
join pg_class classes on classes.oid = constraints.conrelid
join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public'
  and (
    classes.relname = 'envelope_movements'
    or constraints.conname in (
      'envelopes_id_household_unique',
      'envelopes_system_code_check',
      'financial_transactions_id_household_unique'
    )
  )
order by classes.relname, constraints.conname;

select
  index_classes.relname as table_name,
  indexes.relname as index_name,
  pg_get_indexdef(indexes.oid) as definition
from pg_class indexes
join pg_index index_metadata on index_metadata.indexrelid = indexes.oid
join pg_class index_classes on index_classes.oid = index_metadata.indrelid
join pg_namespace namespaces on namespaces.oid = index_classes.relnamespace
where namespaces.nspname = 'public'
  and indexes.relname in (
    'envelopes_household_system_code_unique',
    'envelope_movements_household_occurred_idx',
    'envelope_movements_envelope_occurred_idx',
    'envelope_movements_transaction_idx',
    'envelope_movements_group_idx',
    'envelope_movements_single_reversal_idx'
  )
order by indexes.relname;

-- Triggers, policy RLS et privilèges attendus. Toutes ces vues catalogue sont sûres
-- lorsque la table ou la fonction n'existe pas.
select
  triggers.trigger_name,
  triggers.event_object_table as table_name,
  triggers.action_timing,
  triggers.event_manipulation,
  triggers.action_statement
from information_schema.triggers triggers
where triggers.trigger_schema = 'public'
  and triggers.trigger_name in (
    'envelope_movements_immutable',
    'envelope_movements_group_valid',
    'envelopes_protect_system'
  )
order by triggers.trigger_name, triggers.event_manipulation;

select
  policies.tablename,
  policies.policyname,
  policies.cmd,
  policies.qual,
  policies.with_check
from pg_policies policies
where policies.schemaname = 'public'
  and policies.tablename = 'envelope_movements'
order by policies.policyname;

select
  privileges.grantee,
  privileges.privilege_type
from information_schema.role_table_grants privileges
where privileges.table_schema = 'public'
  and privileges.table_name = 'envelope_movements'
order by privileges.grantee, privileges.privilege_type;

select
  privileges.routine_name,
  privileges.grantee,
  privileges.privilege_type
from information_schema.routine_privileges privileges
where privileges.routine_schema = 'public'
  and privileges.routine_name in (
    'create_envelope_transfer',
    'ensure_household_system_envelope'
  )
order by privileges.routine_name, privileges.grantee;
