begin;

create or replace view public.recurring_financial_actual_candidates
with (security_invoker=true) as
select e.id financial_event_id,e.household_id,
  case when e.event_type='cash_income' then 'income'
       when e.event_type='cash_expense' then 'expense'
       when e.event_type='account_transfer' then 'account_transfer' end economic_type,
  e.occurred_at,e.description,t.amount,t.source_account_id,t.destination_account_id,
  case when count(distinct m.envelope_id)=1 then min(m.envelope_id::text)::uuid end envelope_id,
  case when count(distinct l.member_id)=1 then min(l.member_id::text)::uuid end member_id
from public.financial_events e
join public.financial_transactions t on t.event_id=e.id and t.household_id=e.household_id
left join public.envelope_movements m on m.event_id=e.id and m.household_id=e.household_id
left join public.financial_transaction_lines l on l.transaction_id=t.id
where e.event_type in ('cash_income','cash_expense','account_transfer')
  and t.reversed_by is null
group by e.id,e.household_id,e.event_type,e.occurred_at,e.description,t.amount,t.source_account_id,t.destination_account_id;

revoke all on public.recurring_financial_actual_candidates from public,anon;
grant select on public.recurring_financial_actual_candidates to authenticated;

comment on view public.recurring_financial_actual_candidates is
  'R3.1 read-only adapter over canonical FinancialEvents. It never duplicates or mutates actual transactions.';

commit;
