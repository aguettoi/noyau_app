-- Read-only business-test precheck. Returns one row and creates no test data.
with members as (
  select household_id, user_id from public.household_members order by household_id, user_id
), candidates as (
  select members.household_id, members.user_id as actor_id
  from members
  where (select count(*) from public.accounts where accounts.household_id = members.household_id and not accounts.is_system) >= 2
    and (select count(*) from public.envelopes where envelopes.household_id = members.household_id and not envelopes.is_system and envelopes.archived_at is null) >= 2
  order by members.household_id, members.user_id
  limit 1
), baseline as (
  select candidates.household_id, candidates.actor_id,
    (select count(*) from public.accounts where household_id = candidates.household_id and not is_system) as ordinary_accounts,
    (select count(*) from public.envelopes where household_id = candidates.household_id and not is_system and archived_at is null) as active_envelopes,
    (select count(*) from public.financial_events where household_id = candidates.household_id) as financial_events_before,
    (select count(*) from public.financial_transactions where household_id = candidates.household_id) as transactions_before,
    (select count(*) from public.financial_transaction_lines lines join public.financial_transactions transactions on transactions.id = lines.transaction_id where transactions.household_id = candidates.household_id) as lines_before,
    (select count(*) from public.envelope_movements where household_id = candidates.household_id) as movements_before,
    (select count(*) from public.obligations where household_id = candidates.household_id) as obligations_before,
    (select count(*) from public.obligation_settlements where household_id = candidates.household_id) as settlements_before,
    (select count(*) from public.budget_funding_links where household_id = candidates.household_id) as funding_links_before
  from candidates
)
select
  exists(select 1 from baseline) as business_test_precheck_ready,
  case when exists(select 1 from baseline) then 0 else 1 end as blocking_issue_count,
  0 as warning_count,
  coalesce((select household_id from baseline)::text, '') as selected_household_id,
  coalesce((select actor_id from baseline)::text, '') as selected_actor_id,
  coalesce((select ordinary_accounts from baseline), 0) as ordinary_accounts,
  coalesce((select active_envelopes from baseline), 0) as active_envelopes,
  coalesce((select jsonb_build_object('financial_events',financial_events_before,'financial_transactions',transactions_before,'financial_transaction_lines',lines_before,'envelope_movements',movements_before,'obligations',obligations_before,'obligation_settlements',settlements_before,'budget_funding_links',funding_links_before) from baseline), '{}'::jsonb) as baseline_counts,
  case when exists(select 1 from baseline) then '[]'::jsonb else jsonb_build_array('No household has two ordinary accounts and two active ordinary envelopes.') end as blocking_details,
  '[]'::jsonb as warnings;
