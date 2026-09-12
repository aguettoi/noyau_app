-- Read-only diagnostic only. It identifies historical income-receivable
-- settlements that predate envelope routing. It performs no compensation.
with income_settlements as (
  select
    events.id as event_id,
    events.household_id,
    events.occurred_at,
    events.description,
    events.idempotency_key,
    settlements.id as settlement_id,
    settlements.amount as settlement_amount,
    obligations.id as obligation_id,
    obligations.description as receivable_description,
    obligations.counterparty_name as debtor_name,
    transactions.id as transaction_id
  from public.financial_events events
  join public.obligation_settlements settlements on settlements.event_id=events.id
  join public.obligations obligations on obligations.id=settlements.obligation_id
  join public.financial_transactions transactions on transactions.id=settlements.financial_transaction_id
  where events.event_type='receivable_settlement'
    and obligations.obligation_kind='receivable'
    and obligations.receivable_kind='income'
), candidate_compensations as (
  select settlements.*,
    count(movements.id) as envelope_movement_count,
    coalesce(sum(movements.amount),0)::numeric(14,2) as envelope_amount,
    case when count(movements.id)=0 then settlements.settlement_amount else 0 end::numeric(14,2) as proposed_to_allocate_compensation
  from income_settlements settlements
  left join public.envelope_movements movements on movements.event_id=settlements.event_id
  group by settlements.event_id,settlements.household_id,settlements.occurred_at,
    settlements.description,settlements.idempotency_key,settlements.settlement_id,
    settlements.settlement_amount,settlements.obligation_id,
    settlements.receivable_description,settlements.debtor_name,settlements.transaction_id
)
select
  event_id, occurred_at, description, receivable_description, debtor_name,
  settlement_amount, envelope_movement_count, envelope_amount,
  proposed_to_allocate_compensation,
  'READ-ONLY: review before any compensating FinancialEvent' as recommendation
from candidate_compensations
where envelope_movement_count=0
order by occurred_at, event_id;
