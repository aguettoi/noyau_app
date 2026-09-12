-- Sprint 2.2 / Lot 1 -- validation post-migration, strictement en lecture seule.
-- Aucun appel de RPC d'écriture, aucune DDL et aucune DML.

-- 1. Table, RLS et colonnes attendues du journal des enveloppes.
select
  classes.relname as table_name,
  classes.relrowsecurity as rls_enabled,
  classes.relforcerowsecurity as rls_forced
from pg_class classes
join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public'
  and classes.relname = 'envelope_movements';

select
  columns.column_name,
  columns.data_type,
  columns.numeric_precision,
  columns.numeric_scale,
  columns.is_nullable,
  columns.column_default
from information_schema.columns columns
where columns.table_schema = 'public'
  and columns.table_name = 'envelope_movements'
order by columns.ordinal_position;

-- 2. CHECK, clés primaires, clés étrangères et clés composites de foyer.
select
  constraints.conname as constraint_name,
  constraints.contype as constraint_type,
  pg_get_constraintdef(constraints.oid) as definition
from pg_constraint constraints
join pg_class classes on classes.oid = constraints.conrelid
join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public'
  and classes.relname = 'envelope_movements'
order by constraints.contype, constraints.conname;

select
  constraints.conname as composite_household_constraint,
  pg_get_constraintdef(constraints.oid) as definition
from pg_constraint constraints
join pg_class classes on classes.oid = constraints.conrelid
join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public'
  and (
    (classes.relname = 'envelope_movements'
      and constraints.conname in (
        'envelope_movements_envelope_household_fk',
        'envelope_movements_transaction_household_fk',
        'envelope_movements_creator_household_fk',
        'envelope_movements_reversal_household_fk',
        'envelope_movements_id_household_unique'
      ))
    or constraints.conname in (
      'envelopes_id_household_unique',
      'financial_transactions_id_household_unique'
    )
  )
order by constraints.conname;

-- 3. Fonctions, signatures, SECURITY DEFINER et search_path effectif.
select
  procedures.proname as function_name,
  pg_get_function_identity_arguments(procedures.oid) as identity_arguments,
  pg_get_function_result(procedures.oid) as result_type,
  procedures.prosecdef as security_definer,
  coalesce(array_to_string(procedures.proconfig, ', '), '') as configuration
from pg_proc procedures
join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
where namespaces.nspname = 'public'
  and procedures.proname in (
    'prevent_envelope_movement_mutation',
    'protect_system_envelope',
    'ensure_household_system_envelope',
    'assert_envelope_movement_group',
    'assert_envelope_movement_group_trigger',
    'create_envelope_transfer'
  )
order by procedures.proname, pg_get_function_identity_arguments(procedures.oid);

-- Signatures attendues de l'API publique et des contrôles internes.
with expected_signatures(function_name, identity_arguments, result_type) as (
  values
    ('create_envelope_transfer',
      'p_household_id uuid, p_source_envelope_id uuid, p_destination_envelope_id uuid, p_amount numeric, p_occurred_at timestamp with time zone, p_description text',
      'uuid'),
    ('ensure_household_system_envelope',
      'p_household_id uuid, p_system_code text',
      'uuid'),
    ('assert_envelope_movement_group',
      'p_movement_group_id uuid',
      'void')
), actual_signatures as (
  select
    procedures.proname as function_name,
    pg_get_function_identity_arguments(procedures.oid) as identity_arguments,
    pg_get_function_result(procedures.oid) as result_type,
    procedures.prosecdef as security_definer,
    coalesce(array_to_string(procedures.proconfig, ', '), '') as configuration
  from pg_proc procedures
  join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
  where namespaces.nspname = 'public'
)
select
  expected_signatures.function_name,
  expected_signatures.identity_arguments as expected_arguments,
  actual_signatures.identity_arguments as actual_arguments,
  expected_signatures.result_type as expected_result,
  actual_signatures.result_type as actual_result,
  actual_signatures.security_definer,
  actual_signatures.configuration,
  actual_signatures.identity_arguments = expected_signatures.identity_arguments
    and actual_signatures.result_type = expected_signatures.result_type
    and actual_signatures.security_definer
    and actual_signatures.configuration like '%search_path=public%'
    as matches_expected_contract
from expected_signatures
left join actual_signatures
  on actual_signatures.function_name = expected_signatures.function_name
order by expected_signatures.function_name;

-- 4. Triggers d'immutabilité et de contrôle différé des groupes.
select
  triggers.trigger_name,
  triggers.event_object_table as table_name,
  triggers.action_timing,
  triggers.event_manipulation,
  triggers.action_orientation,
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
  triggers.tgname as trigger_name,
  pg_get_triggerdef(triggers.oid) as trigger_definition
from pg_trigger triggers
join pg_class classes on classes.oid = triggers.tgrelid
join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public'
  and triggers.tgname in (
    'envelope_movements_immutable',
    'envelope_movements_group_valid',
    'envelopes_protect_system'
  )
  and not triggers.tgisinternal
order by triggers.tgname;

-- 5. Policies RLS et privilèges. Il ne doit exister aucune permission DML
-- directe pour authenticated sur envelope_movements.
select
  policies.policyname,
  policies.cmd,
  policies.roles,
  policies.qual,
  policies.with_check
from pg_policies policies
where policies.schemaname = 'public'
  and policies.tablename = 'envelope_movements'
order by policies.policyname;

select
  privileges.grantee,
  privileges.privilege_type,
  privileges.is_grantable
from information_schema.role_table_grants privileges
where privileges.table_schema = 'public'
  and privileges.table_name = 'envelope_movements'
  and privileges.grantee in ('authenticated', 'anon', 'PUBLIC')
order by privileges.grantee, privileges.privilege_type;

select
  procedures.proname as function_name,
  pg_get_function_identity_arguments(procedures.oid) as identity_arguments,
  privileges.grantee,
  privileges.privilege_type
from information_schema.routine_privileges privileges
join pg_proc procedures
  on procedures.proname = privileges.routine_name
join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
where privileges.routine_schema = 'public'
  and namespaces.nspname = 'public'
  and procedures.proname in (
    'create_envelope_transfer',
    'ensure_household_system_envelope'
  )
order by procedures.proname, privileges.grantee;

-- 6. Vue calculée et formule inflow - outflow.
select
  views.table_name as view_name,
  views.view_definition
from information_schema.views views
where views.table_schema = 'public'
  and views.table_name = 'envelope_ledger_balances';

select
  columns.column_name,
  columns.data_type,
  columns.is_nullable
from information_schema.columns columns
where columns.table_schema = 'public'
  and columns.table_name = 'envelope_ledger_balances'
order by columns.ordinal_position;

-- 7. Enveloppes système : colonnes, index unique et données potentiellement dupliquées.
select
  columns.column_name,
  columns.data_type,
  columns.is_nullable,
  columns.column_default
from information_schema.columns columns
where columns.table_schema = 'public'
  and columns.table_name = 'envelopes'
  and columns.column_name in ('is_system', 'system_code')
order by columns.column_name;

select
  indexes.indexname,
  indexes.indexdef
from pg_indexes indexes
where indexes.schemaname = 'public'
  and indexes.tablename = 'envelopes'
  and indexes.indexname = 'envelopes_household_system_code_unique';

select
  envelopes.household_id,
  envelopes.system_code,
  count(*) as duplicate_count
from public.envelopes envelopes
where envelopes.system_code = 'to_allocate'
group by envelopes.household_id, envelopes.system_code
having count(*) > 1
order by envelopes.household_id;

-- 8. Compatibilité avec les enveloppes et le Grand Livre historiques.
select
  envelopes.household_id,
  count(*) as historical_envelope_count,
  count(*) filter (where envelopes.is_system) as system_envelope_count,
  count(*) filter (where not envelopes.is_system) as ordinary_envelope_count,
  count(*) filter (where envelopes.archived_at is not null) as archived_envelope_count
from public.envelopes envelopes
group by envelopes.household_id
order by envelopes.household_id;

select
  objects.object_name,
  objects.object_kind,
  objects.exists_in_catalog
from (
  select
    'financial_transactions'::text as object_name,
    'table'::text as object_kind,
    exists (
      select 1 from information_schema.tables tables
      where tables.table_schema = 'public'
        and tables.table_name = 'financial_transactions'
    ) as exists_in_catalog
  union all
  select 'financial_transaction_lines', 'table', exists (
    select 1 from information_schema.tables tables
    where tables.table_schema = 'public'
      and tables.table_name = 'financial_transaction_lines'
  )
  union all
  select 'account_ledger_balances', 'view', exists (
    select 1 from information_schema.views views
    where views.table_schema = 'public'
      and views.table_name = 'account_ledger_balances'
  )
  union all
  select 'create_ledger_transaction', 'function', exists (
    select 1 from information_schema.routines routines
    where routines.specific_schema = 'public'
      and routines.routine_name = 'create_ledger_transaction'
  )
) objects
order by objects.object_kind, objects.object_name;

-- 9. Diagnostics métier : toutes les requêtes suivantes doivent retourner zéro ligne.
-- Mouvements incomplets, amount non positif, type/direction invalides ou inter-foyers.
select
  movements.id,
  movements.movement_group_id,
  movements.household_id,
  movements.amount,
  movements.movement_type,
  movements.direction,
  movements.financial_transaction_id
from public.envelope_movements movements
left join public.envelopes envelopes on envelopes.id = movements.envelope_id
left join public.financial_transactions financial
  on financial.id = movements.financial_transaction_id
where movements.amount <= 0
   or (movements.movement_type in ('allocation', 'transfer_in', 'refund')
     and movements.direction <> 'inflow')
   or (movements.movement_type in ('consumption', 'transfer_out')
     and movements.direction <> 'outflow')
   or envelopes.household_id is distinct from movements.household_id
   or (movements.financial_transaction_id is not null
     and financial.household_id is distinct from movements.household_id)
order by movements.created_at, movements.id;

-- Transferts de groupe incohérents : deux lignes, une entrée, une sortie,
-- montants égaux, deux enveloppes distinctes et aucune transaction financière.
with transfer_groups as (
  select
    movements.movement_group_id,
    count(*) as movement_count,
    count(*) filter (where movements.movement_type = 'transfer_in') as transfer_in_count,
    count(*) filter (where movements.movement_type = 'transfer_out') as transfer_out_count,
    count(distinct movements.envelope_id) as envelope_count,
    sum(movements.amount) filter (where movements.direction = 'inflow') as inflow_total,
    sum(movements.amount) filter (where movements.direction = 'outflow') as outflow_total,
    count(*) filter (where movements.financial_transaction_id is not null) as linked_transaction_count,
    count(distinct movements.household_id) as household_count
  from public.envelope_movements movements
  where movements.movement_type in ('transfer_in', 'transfer_out')
  group by movements.movement_group_id
)
select *
from transfer_groups
where movement_count <> 2
   or transfer_in_count <> 1
   or transfer_out_count <> 1
   or envelope_count <> 2
   or inflow_total is distinct from outflow_total
   or linked_transaction_count <> 0
   or household_count <> 1
order by movement_group_id;

-- Tout groupe doit rester dans un foyer et ne peut mélanger des types que pour
-- la paire transfer_out / transfer_in.
with movement_groups as (
  select
    movements.movement_group_id,
    count(*) as movement_count,
    count(distinct movements.household_id) as household_count,
    count(*) filter (where movements.movement_type = 'transfer_in') as transfer_in_count,
    count(*) filter (where movements.movement_type = 'transfer_out') as transfer_out_count,
    count(*) filter (where movements.movement_type not in ('transfer_in', 'transfer_out'))
      as non_transfer_count,
    count(distinct movements.movement_type) as type_count
  from public.envelope_movements movements
  group by movements.movement_group_id
)
select *
from movement_groups
where household_count <> 1
   or (transfer_in_count + transfer_out_count > 0 and (
     movement_count <> 2
     or transfer_in_count <> 1
     or transfer_out_count <> 1
     or non_transfer_count <> 0
   ))
   or (transfer_in_count + transfer_out_count = 0 and type_count <> 1)
order by movement_group_id;

-- Splits de dépense incohérents : même transaction expense et total exact.
with consumption_groups as (
  select
    movements.movement_group_id,
    (array_agg(movements.household_id))[1] as household_id,
    (array_agg(movements.financial_transaction_id))[1] as financial_transaction_id,
    count(distinct movements.financial_transaction_id) as transaction_count,
    count(distinct movements.household_id) as household_count,
    sum(movements.amount) as envelope_total,
    count(*) filter (where movements.direction <> 'outflow') as invalid_direction_count
  from public.envelope_movements movements
  where movements.movement_type = 'consumption'
  group by movements.movement_group_id
)
select
  groups.movement_group_id,
  groups.envelope_total,
  financial.amount as transaction_amount,
  financial.type as transaction_type,
  groups.transaction_count,
  groups.household_count,
  groups.invalid_direction_count
from consumption_groups groups
left join public.financial_transactions financial
  on financial.id = groups.financial_transaction_id
 and financial.household_id = groups.household_id
where groups.transaction_count <> 1
   or groups.household_count <> 1
   or groups.invalid_direction_count <> 0
   or financial.id is null
   or financial.type <> 'expense'
   or groups.envelope_total <> financial.amount
order by groups.movement_group_id;

-- Revenus : une allocation unique, complète, vers À répartir.
with allocation_groups as (
  select
    movements.movement_group_id,
    (array_agg(movements.household_id))[1] as household_id,
    (array_agg(movements.financial_transaction_id))[1] as financial_transaction_id,
    count(*) as movement_count,
    count(distinct movements.financial_transaction_id) as transaction_count,
    count(distinct movements.household_id) as household_count,
    sum(movements.amount) as allocation_total,
    bool_and(envelopes.system_code = 'to_allocate') as only_to_allocate,
    count(*) filter (where movements.direction <> 'inflow') as invalid_direction_count
  from public.envelope_movements movements
  join public.envelopes envelopes on envelopes.id = movements.envelope_id
  where movements.movement_type = 'allocation'
  group by movements.movement_group_id
)
select
  groups.movement_group_id,
  groups.allocation_total,
  financial.amount as transaction_amount,
  financial.type as transaction_type,
  groups.movement_count,
  groups.transaction_count,
  groups.household_count,
  groups.only_to_allocate,
  groups.invalid_direction_count
from allocation_groups groups
left join public.financial_transactions financial
  on financial.id = groups.financial_transaction_id
 and financial.household_id = groups.household_id
where groups.movement_count <> 1
   or groups.transaction_count <> 1
   or groups.household_count <> 1
   or groups.invalid_direction_count <> 0
   or not coalesce(groups.only_to_allocate, false)
   or financial.id is null
   or financial.type <> 'income'
   or groups.allocation_total <> financial.amount
order by groups.movement_group_id;

-- Contrepassations invalides : original absent, autre foyer, montant ou sens non inversé.
select
  reversals.id as reversal_id,
  reversals.reversal_of,
  reversals.household_id as reversal_household_id,
  originals.household_id as original_household_id,
  reversals.amount as reversal_amount,
  originals.amount as original_amount,
  reversals.direction as reversal_direction,
  originals.direction as original_direction
from public.envelope_movements reversals
left join public.envelope_movements originals on originals.id = reversals.reversal_of
where reversals.movement_type = 'reversal'
  and (
    originals.id is null
    or reversals.household_id <> originals.household_id
    or reversals.amount <> originals.amount
    or reversals.direction = originals.direction
  )
order by reversals.created_at, reversals.id;

-- Une vue de contrôle des soldes calculés : aucune ligne ne doit présenter
-- une divergence entre inflows - outflows et balance.
select
  balances.household_id,
  balances.envelope_id,
  balances.inflows,
  balances.outflows,
  balances.balance
from public.envelope_ledger_balances balances
where balances.balance <> balances.inflows - balances.outflows
order by balances.household_id, balances.envelope_id;
