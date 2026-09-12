-- Sprint 2.1 -- plan de correction inverse, lecture seule.
-- Ne crée ni ne supprime aucune donnée. Après revue humaine, saisir chaque
-- correction inverse depuis l'application afin de préserver le Grand Livre.

with test_transactions as (
  select
    transactions.id,
    transactions.description,
    transactions.type,
    transactions.amount,
    transactions.source_account_id,
    transactions.destination_account_id
  from public.financial_transactions transactions
  where transactions.description in (
    'TEST S2 DEPENSE',
    'TEST S2 REVENU',
    'TEST S2 VIREMENT',
    'TEST S2 AJUSTEMENT'
  )
),
adjustment_directions as (
  select
    test_transactions.id as transaction_id,
    case
      when bool_or(lines.account_id = test_transactions.source_account_id
        and lines.debit > 0) then 'decrease'
      else 'increase'
    end as inverse_direction
  from test_transactions
  join public.financial_transaction_lines lines
    on lines.transaction_id = test_transactions.id
  where test_transactions.type = 'adjustment'
  group by test_transactions.id, test_transactions.source_account_id
)
select
  test_transactions.id as original_transaction_id,
  test_transactions.description as original_description,
  test_transactions.amount as amount_to_reverse,
  case test_transactions.type
    when 'expense' then 'adjustment'
    when 'income' then 'adjustment'
    when 'transfer' then 'transfer'
    when 'adjustment' then 'adjustment'
  end as correction_type,
  case test_transactions.type
    when 'expense' then test_transactions.source_account_id
    when 'income' then test_transactions.destination_account_id
    when 'transfer' then test_transactions.destination_account_id
    when 'adjustment' then test_transactions.source_account_id
  end as correction_source_account_id,
  case when test_transactions.type = 'transfer'
    then test_transactions.source_account_id
  end as correction_destination_account_id,
  case test_transactions.type
    when 'expense' then 'increase'
    when 'income' then 'decrease'
    when 'transfer' then 'increase'
    when 'adjustment' then adjustment_directions.inverse_direction
  end as correction_direction,
  'ANNULATION ' || test_transactions.description as correction_description
from test_transactions
left join adjustment_directions
  on adjustment_directions.transaction_id = test_transactions.id
order by test_transactions.description;
