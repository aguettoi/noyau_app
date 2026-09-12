-- Read-only audit for the manual +100 MAD envelope-opening test.
-- No data is changed. Replace nothing: it targets the most recent opening group.
with latest_opening as (
  select movements.movement_group_id
  from public.envelope_movements movements
  where movements.movement_type = 'opening'
  order by movements.created_at desc
  limit 1
), opening_group as (
  select movements.household_id, movements.movement_group_id,
    movements.movement_type, movements.direction, movements.amount,
    envelopes.id as envelope_id, envelopes.name as envelope_name,
    envelopes.is_system, envelopes.system_code,
    movements.financial_transaction_id
  from public.envelope_movements movements
  join latest_opening on latest_opening.movement_group_id = movements.movement_group_id
  join public.envelopes on envelopes.id = movements.envelope_id
)
select
  household_id,
  movement_group_id,
  count(*) filter (where movement_type = 'opening') as opening_count,
  count(*) filter (where movement_type = 'opening_offset') as opening_offset_count,
  max(amount) filter (where movement_type = 'opening') as opening_amount,
  max(amount) filter (where movement_type = 'opening_offset') as opening_offset_amount,
  bool_and(financial_transaction_id is null) as no_financial_transaction,
  jsonb_agg(jsonb_build_object(
    'envelope', envelope_name,
    'is_system', is_system,
    'system_code', system_code,
    'type', movement_type,
    'direction', direction,
    'amount', amount
  ) order by movement_type) as movements
from opening_group
group by household_id, movement_group_id;

select count(*) as account_ledger_rows_linked_to_opening
from public.financial_transaction_lines lines
join public.financial_transactions transactions on transactions.id = lines.financial_transaction_id
where transactions.id in (
  select financial_transaction_id
  from public.envelope_movements
  where movement_type in ('opening', 'opening_offset')
    and financial_transaction_id is not null
);
