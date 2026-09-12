-- Sprint 2.1 -- validation fonctionnelle post-saisie, lecture seule.
-- Exécuter ce script avant puis après les quatre saisies afin de comparer les
-- soldes affichés. Aucun résultat dans les requêtes « anomalie » est conforme.

-- 1. Les quatre libellés doivent être présents une fois chacun après le test.
with expected_labels(description) as (
  values
    ('TEST S2 DEPENSE'),
    ('TEST S2 REVENU'),
    ('TEST S2 VIREMENT'),
    ('TEST S2 AJUSTEMENT')
),
test_transactions as (
  select id, description
  from public.financial_transactions
  where description in (select description from expected_labels)
)
select
  expected_labels.description,
  count(test_transactions.id) as transaction_count
from expected_labels
left join test_transactions using (description)
group by expected_labels.description
order by expected_labels.description;

-- 2. Transactions créées, comptes ordinaires référencés et montants.
select
  transactions.id as transaction_id,
  transactions.description,
  transactions.type,
  transactions.occurred_at,
  transactions.amount,
  source_accounts.name as source_account,
  source_accounts.is_system as source_is_system,
  destination_accounts.name as destination_account,
  destination_accounts.is_system as destination_is_system
from public.financial_transactions transactions
left join public.accounts source_accounts
  on source_accounts.id = transactions.source_account_id
left join public.accounts destination_accounts
  on destination_accounts.id = transactions.destination_account_id
where transactions.description in (
  'TEST S2 DEPENSE',
  'TEST S2 REVENU',
  'TEST S2 VIREMENT',
  'TEST S2 AJUSTEMENT'
)
order by transactions.occurred_at, transactions.id;

-- 3. Lignes du Grand Livre associées aux quatre transactions.
select
  transactions.id as transaction_id,
  transactions.description,
  lines.id as line_id,
  accounts.name as account_name,
  accounts.is_system,
  lines.amount,
  lines.debit,
  lines.credit,
  lines.occurred_at
from public.financial_transactions transactions
join public.financial_transaction_lines lines
  on lines.transaction_id = transactions.id
join public.accounts accounts on accounts.id = lines.account_id
where transactions.description in (
  'TEST S2 DEPENSE',
  'TEST S2 REVENU',
  'TEST S2 VIREMENT',
  'TEST S2 AJUSTEMENT'
)
order by transactions.occurred_at, transactions.id, lines.created_at, lines.id;

-- 4. Aucun résultat attendu : transaction partielle, déséquilibrée ou ligne
--    invalide parmi les quatre scénarios.
select
  transactions.id as transaction_id,
  transactions.description,
  count(lines.id) as line_count,
  coalesce(sum(lines.debit), 0) as total_debit,
  coalesce(sum(lines.credit), 0) as total_credit,
  bool_or(lines.amount <> lines.debit - lines.credit) as signed_amount_mismatch,
  bool_or(
    lines.debit < 0
    or lines.credit < 0
    or (lines.debit > 0 and lines.credit > 0)
    or (lines.debit = 0 and lines.credit = 0)
  ) as invalid_posting_shape,
  bool_or(lines.occurred_at is null) as missing_occurred_at
from public.financial_transactions transactions
left join public.financial_transaction_lines lines
  on lines.transaction_id = transactions.id
where transactions.description in (
  'TEST S2 DEPENSE',
  'TEST S2 REVENU',
  'TEST S2 VIREMENT',
  'TEST S2 AJUSTEMENT'
)
group by transactions.id, transactions.description
having count(lines.id) <> 2
   or coalesce(sum(lines.debit), 0) <> coalesce(sum(lines.credit), 0)
   or bool_or(lines.amount <> lines.debit - lines.credit)
   or bool_or(
     lines.debit < 0
     or lines.credit < 0
     or (lines.debit > 0 and lines.credit > 0)
     or (lines.debit = 0 and lines.credit = 0)
   )
   or bool_or(lines.occurred_at is null)
order by transactions.description;

-- 5. Aucun résultat attendu : un compte système utilisé comme compte source ou
--    destination visible de la saisie utilisateur.
select
  transactions.id as transaction_id,
  transactions.description,
  source_accounts.name as system_source_account,
  destination_accounts.name as system_destination_account
from public.financial_transactions transactions
left join public.accounts source_accounts
  on source_accounts.id = transactions.source_account_id
left join public.accounts destination_accounts
  on destination_accounts.id = transactions.destination_account_id
where transactions.description in (
  'TEST S2 DEPENSE',
  'TEST S2 REVENU',
  'TEST S2 VIREMENT',
  'TEST S2 AJUSTEMENT'
)
  and (coalesce(source_accounts.is_system, false)
    or coalesce(destination_accounts.is_system, false));

-- 6. Soldes actuellement dérivés par la vue pour les comptes ordinaires
--    impliqués. Comparer cette sortie avant et après les saisies.
with involved_account_ids(account_id) as (
  select source_account_id
  from public.financial_transactions
  where description in (
    'TEST S2 DEPENSE',
    'TEST S2 REVENU',
    'TEST S2 VIREMENT',
    'TEST S2 AJUSTEMENT'
  )
  union
  select destination_account_id
  from public.financial_transactions
  where description in (
    'TEST S2 DEPENSE',
    'TEST S2 REVENU',
    'TEST S2 VIREMENT',
    'TEST S2 AJUSTEMENT'
  )
)
select
  accounts.id as account_id,
  accounts.name,
  balances.opening_balance,
  balances.ledger_balance,
  balances.theoretical_balance
from involved_account_ids
join public.accounts accounts on accounts.id = involved_account_ids.account_id
join public.account_ledger_balances balances on balances.account_id = accounts.id
where not accounts.is_system
order by accounts.name;

-- 7. Aucun résultat attendu : divergence entre la vue et le calcul direct des
--    lignes pour les comptes touchés par les scénarios de test.
with involved_account_ids(account_id) as (
  select source_account_id
  from public.financial_transactions
  where description in (
    'TEST S2 DEPENSE',
    'TEST S2 REVENU',
    'TEST S2 VIREMENT',
    'TEST S2 AJUSTEMENT'
  )
  union
  select destination_account_id
  from public.financial_transactions
  where description in (
    'TEST S2 DEPENSE',
    'TEST S2 REVENU',
    'TEST S2 VIREMENT',
    'TEST S2 AJUSTEMENT'
  )
),
direct_balances as (
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
  from involved_account_ids
  join public.accounts accounts on accounts.id = involved_account_ids.account_id
  left join public.financial_transaction_lines lines
    on lines.account_id = accounts.id
  group by accounts.id, accounts.opening_balance, accounts.kind
)
select
  balances.account_id,
  balances.ledger_balance,
  direct_balances.expected_ledger_balance,
  balances.theoretical_balance,
  direct_balances.expected_theoretical_balance
from public.account_ledger_balances balances
join direct_balances on direct_balances.account_id = balances.account_id
where balances.ledger_balance <> direct_balances.expected_ledger_balance
   or balances.theoretical_balance <> direct_balances.expected_theoretical_balance
order by balances.account_id;
