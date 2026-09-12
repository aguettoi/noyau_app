-- Read-only inventory of historical direct-budget allocations that incorrectly
-- consumed the system envelope À répartir. This script intentionally makes no
-- correction and never changes historical rows.
with to_allocate as (
  select id, household_id
  from public.envelopes
  where system_code = 'to_allocate'
), erroneous_movements as (
  select
    movements.id,
    movements.occurred_at,
    movements.amount,
    movements.description,
    movements.movement_type,
    movements.event_id,
    events.event_type,
    transactions.id as financial_transaction_id,
    transactions.type as financial_transaction_type,
    funding.run_id,
    case
      when events.description like 'TEST_%' then 'test'
      when funding.run_id is null then 'budget_allocation_legacy_without_gl_or_run'
      when transactions.id is null then 'budget_allocation_legacy_without_gl'
      else 'budget_allocation_with_gl'
    end as origin
  from public.envelope_movements movements
  join to_allocate system_envelope
    on system_envelope.id = movements.envelope_id
   and system_envelope.household_id = movements.household_id
  join public.financial_events events on events.id = movements.event_id
  left join public.financial_transactions transactions
    on transactions.id = movements.financial_transaction_id
  left join public.budget_allocation_run_funding_lines funding
    on funding.event_id = movements.event_id
  where movements.movement_type = 'transfer_out'
    and movements.direction = 'outflow'
    and events.event_type = 'budget_allocation'
), all_to_allocate_movements as (
  select
    movements.direction,
    movements.amount,
    movements.movement_type,
    movements.event_id,
    events.event_type
  from public.envelope_movements movements
  join to_allocate system_envelope
    on system_envelope.id = movements.envelope_id
   and system_envelope.household_id = movements.household_id
  left join public.financial_events events on events.id = movements.event_id
)
select jsonb_build_object(
  'read_only', true,
  'to_allocate_balance', coalesce((
    select sum(amount * case when direction = 'inflow' then 1 else -1 end)
    from all_to_allocate_movements
  ), 0),
  'erroneous_budget_allocation_outflow_total', coalesce((
    select sum(amount) from erroneous_movements
  ), 0),
  'by_origin', coalesce((
    select jsonb_agg(jsonb_build_object('origin', origin, 'amount', amount, 'movement_count', movement_count))
    from (
      select origin, sum(amount) as amount, count(*) as movement_count
      from erroneous_movements
      group by origin
      order by origin
    ) grouped
  ), '[]'::jsonb),
  'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'occurred_at', occurred_at,
      'amount', amount,
      'description', description,
      'movement_type', movement_type,
      'event_id', event_id,
      'event_type', event_type,
      'financial_transaction_id', financial_transaction_id,
      'financial_transaction_type', financial_transaction_type,
      'budget_run_id', run_id,
      'origin', origin
    ) order by occurred_at, id)
    from erroneous_movements
  ), '[]'::jsonb)
) as historical_budget_allocation_to_allocate_diagnostic;
