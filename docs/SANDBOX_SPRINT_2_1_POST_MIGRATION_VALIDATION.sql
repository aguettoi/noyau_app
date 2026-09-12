-- Sprint 2.1 -- validation post-migration, lecture seule.
-- Exécuter le fichier complet dans le SQL Editor du Sandbox.
-- Toute requête de détail qui ne retourne aucune ligne est conforme.

-- 1. Résumé unique : schéma, sécurité et possibilité des contrôles de données.
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
    ('assert_financial_transaction_balanced'),
    ('create_financial_transaction'),
    ('create_ledger_transaction'),
    ('ensure_household_ledger_system_account')
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
    from pg_trigger triggers_catalog
    join pg_class relation on relation.oid = triggers_catalog.tgrelid
    join pg_namespace namespaces on namespaces.oid = relation.relnamespace
    where namespaces.nspname = 'public'
      and relation.relname = 'financial_transaction_lines'
      and triggers_catalog.tgname = 'financial_transaction_lines_balanced'
      and not triggers_catalog.tgisinternal
  ) as balanced_lines_trigger_exists,
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'members read ordinary accounts'
      and cmd = 'SELECT'
  ) as accounts_read_policy_exists,
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
  ) as accounts_have_no_direct_write_policy,
  (select count(*) = 3
   from pg_class relation
   join pg_namespace namespaces on namespaces.oid = relation.relnamespace
   where namespaces.nspname = 'public'
     and relation.relname in (
       'financial_transactions',
       'financial_transaction_lines',
       'financial_audit_events'
     )
     and relation.relrowsecurity) as ledger_tables_rls_enabled,
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'financial_transactions',
        'financial_transaction_lines',
        'financial_audit_events'
      )
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
  ) as ledger_tables_have_no_direct_write_policy,
  exists (
    select 1
    from information_schema.routine_privileges routine_privileges
    where routine_privileges.routine_schema = 'public'
      and routine_privileges.routine_name = 'create_ledger_transaction'
      and routine_privileges.grantee = 'authenticated'
      and routine_privileges.privilege_type = 'EXECUTE'
  ) as authenticated_can_execute_ledger_rpc,
  not exists (
    select 1
    from information_schema.routine_privileges routine_privileges
    where routine_privileges.routine_schema = 'public'
      and routine_privileges.routine_name in (
        'create_financial_transaction',
        'create_ledger_transaction',
        'ensure_household_ledger_system_account'
      )
      and routine_privileges.grantee in ('anon', 'PUBLIC')
      and routine_privileges.privilege_type = 'EXECUTE'
  ) as public_and_anon_cannot_execute_ledger_rpcs,
  (select count(*) = 3
   from existing_columns
   where table_name = 'financial_transaction_lines'
     and column_name in ('debit', 'credit', 'occurred_at'))
    as line_balance_analysis_possible;

-- 2. Colonnes effectivement présentes et leurs propriétés.
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

-- 3. Contraintes CHECK attendues.
select
  relation.relname as table_name,
  constraints_catalog.conname as constraint_name,
  pg_get_constraintdef(constraints_catalog.oid) as definition
from pg_constraint constraints_catalog
join pg_class relation on relation.oid = constraints_catalog.conrelid
join pg_namespace namespaces on namespaces.oid = relation.relnamespace
where namespaces.nspname = 'public'
  and constraints_catalog.conname in (
    'accounts_kind_check',
    'accounts_system_kind_check',
    'financial_transactions_type_check',
    'financial_transaction_lines_debit_credit_check'
  )
order by relation.relname, constraints_catalog.conname;

-- 4. Trigger de contrôle de la double écriture.
select
  relation.relname as table_name,
  triggers_catalog.tgname as trigger_name,
  pg_get_triggerdef(triggers_catalog.oid) as definition
from pg_trigger triggers_catalog
join pg_class relation on relation.oid = triggers_catalog.tgrelid
join pg_namespace namespaces on namespaces.oid = relation.relnamespace
where namespaces.nspname = 'public'
  and relation.relname = 'financial_transaction_lines'
  and not triggers_catalog.tgisinternal
order by triggers_catalog.tgname;

-- 5. Fonctions et RPC : signature, mode SECURITY DEFINER et search_path.
select
  procedures.proname as routine_name,
  pg_get_function_identity_arguments(procedures.oid) as arguments,
  procedures.prosecdef as security_definer,
  procedures.proconfig as configuration
from pg_proc procedures
join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
where namespaces.nspname = 'public'
  and procedures.proname in (
    'assert_financial_transaction_balanced',
    'create_financial_transaction',
    'create_ledger_transaction',
    'ensure_household_ledger_system_account'
  )
order by procedures.proname;

-- 6. Privilèges EXECUTE effectifs des RPC.
select
  routine_privileges.routine_name,
  routine_privileges.grantee,
  routine_privileges.privilege_type
from information_schema.routine_privileges routine_privileges
where routine_privileges.routine_schema = 'public'
  and routine_privileges.routine_name in (
    'create_financial_transaction',
    'create_ledger_transaction',
    'ensure_household_ledger_system_account'
  )
order by routine_privileges.routine_name, routine_privileges.grantee;

-- 7. Politiques RLS des comptes et du Grand Livre.
select
  tablename,
  policyname,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'accounts',
    'financial_transactions',
    'financial_transaction_lines',
    'financial_audit_events'
  )
order by tablename, policyname;

-- 8. Définition de la vue des soldes calculés.
select
  viewname,
  definition
from pg_views
where schemaname = 'public'
  and viewname = 'account_ledger_balances';

-- 9. Comptes système existants. Une liste vide est normale avant la première
--    écriture nécessitant une contrepartie système.
select
  household_id,
  id as account_id,
  name,
  kind,
  is_system,
  opening_balance,
  archived_at,
  created_at
from public.accounts
where is_system
order by household_id, name;

-- 10. Aucun résultat attendu : doublons de comptes système par foyer et nom.
select
  household_id,
  name,
  count(*) as duplicate_count
from public.accounts
where is_system
group by household_id, name
having count(*) > 1
order by household_id, name;

-- 11. Aucun résultat attendu : lignes incompatibles avec le modèle débit/crédit
--     ou transactions non équilibrées.
select
  transaction_id,
  count(*) as line_count,
  sum(debit) as total_debit,
  sum(credit) as total_credit,
  bool_or(amount <> debit - credit) as signed_amount_mismatch,
  bool_or(debit < 0 or credit < 0 or (debit > 0 and credit > 0)
    or (debit = 0 and credit = 0)) as invalid_posting_shape,
  bool_or(occurred_at is null) as missing_occurred_at
from public.financial_transaction_lines
group by transaction_id
having sum(debit) <> sum(credit)
   or bool_or(amount <> debit - credit)
   or bool_or(debit < 0 or credit < 0 or (debit > 0 and credit > 0)
      or (debit = 0 and credit = 0))
   or bool_or(occurred_at is null)
order by transaction_id;

-- 12. Aucun résultat attendu : différence entre la vue et le calcul direct.
with line_balances as (
  select
    accounts.id as account_id,
    coalesce(sum(lines.debit - lines.credit), 0)::numeric(14, 2)
      as expected_ledger_balance,
    (
      accounts.opening_balance
      + case
        when accounts.kind = 'loan'
          then coalesce(sum(lines.credit - lines.debit), 0)
        else coalesce(sum(lines.debit - lines.credit), 0)
      end
    )::numeric(14, 2) as expected_theoretical_balance
  from public.accounts accounts
  left join public.financial_transaction_lines lines
    on lines.account_id = accounts.id
  group by accounts.id, accounts.opening_balance, accounts.kind
)
select
  balances.account_id,
  balances.ledger_balance,
  line_balances.expected_ledger_balance,
  balances.theoretical_balance,
  line_balances.expected_theoretical_balance
from public.account_ledger_balances balances
join line_balances on line_balances.account_id = balances.account_id
where balances.ledger_balance <> line_balances.expected_ledger_balance
   or balances.theoretical_balance <> line_balances.expected_theoretical_balance
order by balances.account_id;

-- 13. Aucun résultat attendu : transactions existantes incompatibles avec les
--     nouvelles colonnes obligatoires du Grand Livre.
select
  id as transaction_id,
  household_id,
  type,
  occurred_at,
  description,
  amount,
  validated_at
from public.financial_transactions
where description is null
   or char_length(trim(description)) not between 1 and 280
   or amount is null
   or validated_at is null
order by occurred_at, id;
