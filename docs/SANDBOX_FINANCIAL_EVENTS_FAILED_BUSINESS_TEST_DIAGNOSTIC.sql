-- Strictly read-only rollback diagnostic for a failed TEST_FE_20260809 receipt.
with receipt_keys(idempotency_key) as (values
  ('00000000-0000-4000-8000-000000000101'::uuid),
  ('00000000-0000-4000-8000-000000000102'::uuid),
  ('00000000-0000-4000-8000-000000000103'::uuid),
  ('00000000-0000-4000-8000-000000000104'::uuid),
  ('00000000-0000-4000-8000-000000000105'::uuid),
  ('00000000-0000-4000-8000-000000000106'::uuid),
  ('00000000-0000-4000-8000-000000000107'::uuid),
  ('00000000-0000-4000-8000-000000000108'::uuid),
  ('00000000-0000-4000-8000-000000000109'::uuid),
  ('00000000-0000-4000-8000-000000000110'::uuid),
  ('00000000-0000-4000-8000-000000000111'::uuid),
  ('00000000-0000-4000-8000-000000000112'::uuid),
  ('00000000-0000-4000-8000-000000000113'::uuid),
  ('00000000-0000-4000-8000-000000000114'::uuid),
  ('00000000-0000-4000-8000-000000000115'::uuid),
  ('00000000-0000-4000-8000-000000000116'::uuid),
  ('00000000-0000-4000-8000-000000000117'::uuid),
  ('00000000-0000-4000-8000-000000000118'::uuid),
  ('00000000-0000-4000-8000-000000000119'::uuid)
), test_events as (
  select events.id from public.financial_events events
  where events.description like 'TEST_FE_20260809%'
     or events.idempotency_key in (select idempotency_key from receipt_keys)
), counts as (
  select
    (select count(*) from test_events) as financial_events_count,
    (select count(*) from public.financial_transactions transactions where transactions.event_id in (select id from test_events)) as financial_transactions_count,
    (select count(*) from public.financial_transaction_lines lines join public.financial_transactions transactions on transactions.id = lines.transaction_id where transactions.event_id in (select id from test_events)) as financial_transaction_lines_count,
    (select count(*) from public.envelope_movements movements where movements.event_id in (select id from test_events)) as envelope_movements_count,
    (select count(*) from public.obligations obligations where obligations.origin_event_id in (select id from test_events)) as obligations_count,
    (select count(*) from public.obligation_settlements settlements where settlements.event_id in (select id from test_events)) as obligation_settlements_count,
    (select count(*) from public.budget_funding_links links where links.event_id in (select id from test_events)) as budget_funding_links_count
)
select
  financial_events_count = 0
    and financial_transactions_count = 0
    and financial_transaction_lines_count = 0
    and envelope_movements_count = 0
    and obligations_count = 0
    and obligation_settlements_count = 0
    and budget_funding_links_count = 0 as failed_attempt_clean,
  financial_events_count as test_financial_events_count,
  financial_transactions_count as test_financial_transactions_count,
  financial_transaction_lines_count as test_financial_transaction_lines_count,
  envelope_movements_count as test_envelope_movements_count,
  obligations_count as test_obligations_count,
  obligation_settlements_count as test_obligation_settlements_count,
  budget_funding_links_count as test_budget_funding_links_count,
  case when financial_events_count = 0
      and financial_transactions_count = 0
      and financial_transaction_lines_count = 0
      and envelope_movements_count = 0
      and obligations_count = 0
      and obligation_settlements_count = 0
      and budget_funding_links_count = 0
    then '[]'::jsonb
    else jsonb_build_array('TEST_FE_20260809 rows persisted; do not rerun the receipt before investigating this result.')
  end as blocking_details
from counts;
