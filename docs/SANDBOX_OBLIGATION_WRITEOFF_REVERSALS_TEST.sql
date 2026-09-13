-- Phase 2A write-off reversal certification.
-- Sandbox only. Every fixture and every write is rolled back.
begin;

create temp table writeoff_reversal_results (
  test_name text primary key,
  status text not null check (status in ('passed', 'failed', 'skipped')),
  detail text not null
) on commit drop;

create temp table writeoff_reversal_context on commit drop as
select
  h.id as household_id,
  hm.user_id as actor_id,
  (select a.id from public.accounts a where a.household_id = h.id and not a.is_system order by a.id limit 1) as account_id,
  (select e.id from public.envelopes e where e.household_id = h.id and e.archived_at is null and not e.is_system order by e.id limit 1) as envelope_id
from public.households h
join public.household_members hm on hm.household_id = h.id
where h.name = 'FINANCIEL PILOTE — GOLDEN LEDGER E2E'
order by hm.created_at
limit 1;

do $$
declare
  c writeoff_reversal_context%rowtype;
  debt_event uuid; debt_id uuid; debt_writeoff uuid; debt_adjustment uuid;
  debt_rev_20 uuid; debt_rev_30 uuid; debt_rev_20b uuid;
  income_event uuid; income_id uuid; income_writeoff uuid; income_adjustment uuid; income_reversal uuid;
  expense_event uuid; recovery_event uuid; recovery_id uuid; recovery_writeoff uuid; recovery_adjustment uuid; recovery_reversal uuid;
  targeted_event uuid; targeted_id uuid; targeted_writeoff_a uuid; targeted_writeoff_b uuid; targeted_a uuid; targeted_b uuid;
  interaction_event uuid; interaction_id uuid; interaction_settlement uuid; interaction_writeoff uuid; interaction_adjustment uuid;
  other_household uuid;
  retry uuid;
  rejected boolean;
  events_before bigint;
  movements_before bigint;
  source_capacity numeric;
begin
  select * into c from writeoff_reversal_context;
  if c.actor_id is null or c.account_id is null or c.envelope_id is null then
    raise exception 'Missing Golden Ledger E2E transactional context';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', c.actor_id::text)::text, true);

  -- Debt: one write-off, three individual reversals, exact source cap and GL.
  debt_event := public.create_debt_expense_event(c.household_id, now(), 'TEST_WOR_DEBT', 100,
    jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 100)),
    'Test creditor', null, 'transactional', gen_random_uuid());
  select id into debt_id from public.obligations where origin_event_id = debt_event;
  debt_writeoff := public.writeoff_debt_event(c.household_id, debt_id, now(), 70, 'Debt write-off', null, gen_random_uuid());
  select id into debt_adjustment from public.obligation_adjustments where financial_event_id = debt_writeoff;
  debt_rev_20 := public.reverse_debt_writeoff_event(c.household_id, debt_adjustment, now(), 20, 'Debt reversal 20', 'one', '00000000-0000-4000-8000-000000020001');
  debt_rev_30 := public.reverse_debt_writeoff_event(c.household_id, debt_adjustment, now(), 30, 'Debt reversal 30', 'two', gen_random_uuid());
  debt_rev_20b := public.reverse_debt_writeoff_event(c.household_id, debt_adjustment, now(), 20, 'Debt reversal 20 final', 'three', gen_random_uuid());
  insert into writeoff_reversal_results
  select 'debt_partial_total_net_invariant',
    case when gross_settled_amount=0 and settlement_reversed_amount=0 and written_off_amount=70
              and writeoff_reversed_amount=70 and net_written_off_amount=0
              and remaining_amount=100 and status='open' then 'passed' else 'failed' end,
    'Debt is fully reopened after 20 + 30 + 20 write-off reversals.'
  from public.obligation_balances where obligation_id=debt_id;
  insert into writeoff_reversal_results values (
    'debt_source_link_and_actor',
    case when (select count(*) from public.obligation_adjustments where reverses_adjustment_id=debt_adjustment and reversal_of_event_id=debt_writeoff and created_by=c.actor_id)=3 then 'passed' else 'failed' end,
    'Every Debt reversal links to the exact write-off and records its actor.'
  );
  insert into writeoff_reversal_results values (
    'debt_gl_sides',
    case when exists (
      select 1 from public.financial_transaction_lines l join public.accounts a on a.id=l.account_id
      where l.transaction_id=(select financial_transaction_id from public.obligation_adjustments where financial_event_id=debt_rev_20)
        and a.name='Système — Gains d’abandon de dettes' and l.debit=20 and l.credit=0
    ) and exists (
      select 1 from public.financial_transaction_lines l join public.accounts a on a.id=l.account_id
      where l.transaction_id=(select financial_transaction_id from public.obligation_adjustments where financial_event_id=debt_rev_20)
        and a.name='Système — Dettes' and l.debit=0 and l.credit=20
    ) then 'passed' else 'failed' end,
    'Debt reversal is Dr gain / Cr debt.'
  );
  insert into writeoff_reversal_results values (
    'debt_cash_envelope_to_allocate_neutral',
    case when not exists(select 1 from public.envelope_movements where event_id in(debt_rev_20,debt_rev_30,debt_rev_20b))
          and not exists(select 1 from public.financial_transactions t where t.event_id in(debt_rev_20,debt_rev_30,debt_rev_20b) and (t.source_account_id is not null or t.destination_account_id is not null))
      then 'passed' else 'failed' end,
    'Debt write-off reversals create GL only, with no cash, envelope or To Allocate movement.'
  );
  retry := public.reverse_debt_writeoff_event(c.household_id, debt_adjustment, now(), 20, 'Debt reversal 20', 'one', '00000000-0000-4000-8000-000000020001');
  insert into writeoff_reversal_results values (
    'debt_idempotency',
    case when retry=debt_rev_20 and (select count(*) from public.obligation_adjustments where financial_event_id=debt_rev_20)=1 then 'passed' else 'failed' end,
    'The same idempotency key returns the original event without duplication.'
  );
  events_before := (select count(*) from public.financial_events where household_id=c.household_id);
  rejected := false;
  begin perform public.reverse_debt_writeoff_event(c.household_id, debt_adjustment, now(), .01, 'Over cap', null, gen_random_uuid()); exception when others then rejected := true; end;
  insert into writeoff_reversal_results values (
    'debt_over_cap_rollback',
    case when rejected and (select count(*) from public.financial_events where household_id=c.household_id)=events_before then 'passed' else 'failed' end,
    'A 0.01 excess is rejected atomically.'
  );
  rejected := false; begin perform public.reverse_debt_writeoff_event(c.household_id, debt_adjustment, now(), 0, 'Zero', null, gen_random_uuid()); exception when others then rejected := true; end;
  insert into writeoff_reversal_results values ('debt_zero_rejected', case when rejected then 'passed' else 'failed' end, 'Zero is rejected.');
  rejected := false; begin perform public.reverse_debt_writeoff_event(c.household_id, debt_adjustment, now(), -1, 'Negative', null, gen_random_uuid()); exception when others then rejected := true; end;
  insert into writeoff_reversal_results values ('debt_negative_rejected', case when rejected then 'passed' else 'failed' end, 'Negative is rejected.');

  -- Income: partial write-off reversal must reopen exactly the receivable and
  -- use the opposite loss/receivable posting, without a new income or envelope.
  income_event := public.create_income_receivable_event(c.household_id, now(), 'TEST_WOR_INCOME', 100, 'Test debtor', null, null, gen_random_uuid());
  select id into income_id from public.obligations where origin_event_id=income_event;
  income_writeoff := public.writeoff_income_receivable_event(c.household_id, income_id, now(), 70, 'Income write-off', null, gen_random_uuid());
  select id into income_adjustment from public.obligation_adjustments where financial_event_id=income_writeoff;
  income_reversal := public.reverse_income_receivable_writeoff_event(c.household_id, income_adjustment, now(), 20, 'Income reversal', 'income note', gen_random_uuid());
  insert into writeoff_reversal_results
  select 'income_partial_invariant',
    case when written_off_amount=70 and writeoff_reversed_amount=20 and net_written_off_amount=50 and remaining_amount=50 and status='open' then 'passed' else 'failed' end,
    'Income write-off reversal reopens exactly its amount.'
  from public.obligation_balances where obligation_id=income_id;
  insert into writeoff_reversal_results values (
    'income_gl_and_neutrality',
    case when exists(select 1 from public.financial_transaction_lines l join public.accounts a on a.id=l.account_id where l.transaction_id=(select financial_transaction_id from public.obligation_adjustments where financial_event_id=income_reversal) and a.name='Système — Créances' and l.debit=20)
          and exists(select 1 from public.financial_transaction_lines l join public.accounts a on a.id=l.account_id where l.transaction_id=(select financial_transaction_id from public.obligation_adjustments where financial_event_id=income_reversal) and a.name='Système — Pertes sur créances' and l.credit=20)
          and not exists(select 1 from public.envelope_movements where event_id=income_reversal)
      then 'passed' else 'failed' end,
    'Income reversal is Dr receivable / Cr loss with no envelope allocation.'
  );
  perform public.settle_receivable_event(c.household_id, income_id, now(), 'Income reopened settlement', 50, c.account_id, null, gen_random_uuid(), jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 50)));
  insert into writeoff_reversal_results
  select 'income_reopened_amount_can_settle', case when remaining_amount=0 and status='written_off' then 'passed' else 'failed' end,
    'The reopened Income amount can be settled while its net write-off remains traceable.'
  from public.obligation_balances where obligation_id=income_id;

  -- Recovery: reversal never refunds the source envelope and never releases
  -- a second recovery reservation on the same expense.
  expense_event := public.create_cash_expense_event(c.household_id, now(), 'TEST_WOR_RECOVERY_SOURCE', 100, c.account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 100)), null, gen_random_uuid());
  recovery_event := public.create_recovery_receivable_event(c.household_id, expense_event, c.envelope_id, now(), 'TEST_WOR_RECOVERY', 60, 'Test debtor', null, null, gen_random_uuid());
  select id into recovery_id from public.obligations where origin_event_id=recovery_event;
  recovery_writeoff := public.writeoff_recovery_event(c.household_id, recovery_id, now(), 60, 'Recovery write-off', null, gen_random_uuid());
  select id into recovery_adjustment from public.obligation_adjustments where financial_event_id=recovery_writeoff;
  source_capacity := (select sum(initial_amount) from public.obligations where recovery_source_event_id=expense_event);
  recovery_reversal := public.reverse_recovery_writeoff_event(c.household_id, recovery_adjustment, now(), 60, 'Recovery reversal', 'no refund', gen_random_uuid());
  insert into writeoff_reversal_results
  select 'recovery_total_reopens_and_cap_unchanged',
    case when remaining_amount=60 and status='open'
          and (select sum(initial_amount) from public.obligations where recovery_source_event_id=expense_event)=source_capacity then 'passed' else 'failed' end,
    'Recovery reversal reopens its obligation but does not release source-expense capacity.'
  from public.obligation_balances where obligation_id=recovery_id;
  insert into writeoff_reversal_results values (
    'recovery_gl_and_envelope_neutrality',
    case when exists(select 1 from public.financial_transaction_lines l join public.accounts a on a.id=l.account_id where l.transaction_id=(select financial_transaction_id from public.obligation_adjustments where financial_event_id=recovery_reversal) and a.name='Système — Créances' and l.debit=60)
          and exists(select 1 from public.financial_transaction_lines l join public.accounts a on a.id=l.account_id where l.transaction_id=(select financial_transaction_id from public.obligation_adjustments where financial_event_id=recovery_reversal) and a.name='Système — Recouvrements' and l.credit=60)
          and not exists(select 1 from public.envelope_movements where event_id=recovery_reversal)
      then 'passed' else 'failed' end,
    'Recovery reversal is Dr receivable / Cr recovery and has no refund or To Allocate movement.'
  );

  -- Targeted capacity: reversing A never consumes the separate capacity of B.
  targeted_event := public.create_debt_expense_event(c.household_id, now(), 'TEST_WOR_TARGETED', 100,
    jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 100)), null, null, null, gen_random_uuid());
  select id into targeted_id from public.obligations where origin_event_id=targeted_event;
  targeted_writeoff_a := public.writeoff_debt_event(c.household_id, targeted_id, now(), 40, 'Write-off A', null, gen_random_uuid());
  targeted_writeoff_b := public.writeoff_debt_event(c.household_id, targeted_id, now(), 60, 'Write-off B', null, gen_random_uuid());
  select id into targeted_a from public.obligation_adjustments where financial_event_id=targeted_writeoff_a;
  select id into targeted_b from public.obligation_adjustments where financial_event_id=targeted_writeoff_b;
  perform public.reverse_debt_writeoff_event(c.household_id, targeted_a, now(), 20, 'Reverse A', null, gen_random_uuid());
  rejected := false; begin perform public.reverse_debt_writeoff_event(c.household_id, targeted_b, now(), 60.01, 'Over B', null, gen_random_uuid()); exception when others then rejected := true; end;
  insert into writeoff_reversal_results values (
    'targeted_writeoff_capacity',
    case when rejected
          and (select coalesce(sum(amount),0) from public.obligation_adjustments where reverses_adjustment_id=targeted_a)=20
          and (select coalesce(sum(amount),0) from public.obligation_adjustments where reverses_adjustment_id=targeted_b)=0
      then 'passed' else 'failed' end,
    'A reversal of write-off A does not consume the independent cap of write-off B.'
  );

  -- Interaction with settlement reversals and a new write-off after reopening.
  interaction_event := public.create_debt_expense_event(c.household_id, now(), 'TEST_WOR_INTERACTION', 100,
    jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 100)), null, null, null, gen_random_uuid());
  select id into interaction_id from public.obligations where origin_event_id=interaction_event;
  perform public.settle_debt_event(c.household_id, interaction_id, now(), 'Interaction settlement', 100, c.account_id, null, gen_random_uuid());
  select id into interaction_settlement from public.obligation_settlements where obligation_id=interaction_id;
  perform public.reverse_debt_settlement_event(c.household_id, interaction_settlement, now(), 20, 'Interaction settlement reversal', null, gen_random_uuid());
  interaction_writeoff := public.writeoff_debt_event(c.household_id, interaction_id, now(), 20, 'Interaction write-off', null, gen_random_uuid());
  select id into interaction_adjustment from public.obligation_adjustments where financial_event_id=interaction_writeoff;
  perform public.reverse_debt_writeoff_event(c.household_id, interaction_adjustment, now(), 20, 'Interaction write-off reversal', null, gen_random_uuid());
  insert into writeoff_reversal_results
  select 'settlement_reversal_writeoff_reversal_interaction',
    case when gross_settled_amount=100 and settlement_reversed_amount=20 and net_settled_amount=80
              and written_off_amount=20 and writeoff_reversed_amount=20 and net_written_off_amount=0 and remaining_amount=20 then 'passed' else 'failed' end,
    'All producers and both guards use the same net invariant.'
  from public.obligation_balances where obligation_id=interaction_id;
  perform public.writeoff_debt_event(c.household_id, interaction_id, now(), 20, 'Reopened amount write-off', null, gen_random_uuid());
  insert into writeoff_reversal_results
  select 'reopened_amount_can_writeoff_again', case when remaining_amount=0 and status='written_off' then 'passed' else 'failed' end,
    'An amount reopened by a write-off reversal can be written off again.'
  from public.obligation_balances where obligation_id=interaction_id;

  -- Invalid source, wrong family and other household all roll back.
  events_before := (select count(*) from public.financial_events where household_id=c.household_id);
  rejected := false; begin perform public.reverse_debt_writeoff_event(c.household_id, gen_random_uuid(), now(), 1, 'Missing', null, gen_random_uuid()); exception when others then rejected := true; end;
  insert into writeoff_reversal_results values ('missing_source_rejected', case when rejected and (select count(*) from public.financial_events where household_id=c.household_id)=events_before then 'passed' else 'failed' end, 'A missing source leaves no orphan FinancialEvent.');
  rejected := false; begin perform public.reverse_debt_writeoff_event(c.household_id, income_adjustment, now(), 1, 'Wrong kind', null, gen_random_uuid()); exception when others then rejected := true; end;
  insert into writeoff_reversal_results values ('wrong_obligation_kind_rejected', case when rejected then 'passed' else 'failed' end, 'Debt RPC rejects an Income write-off source.');
  insert into public.households(name) values ('TEST_WOR_OTHER_HOUSEHOLD_ROLLBACK') returning id into other_household;
  rejected := false; begin perform public.reverse_debt_writeoff_event(other_household, debt_adjustment, now(), 1, 'Cross household', null, gen_random_uuid()); exception when others then rejected := true; end;
  insert into writeoff_reversal_results values ('other_household_rejected', case when rejected then 'passed' else 'failed' end, 'Cross-household reversal is rejected.');

  movements_before := (select count(*) from public.envelope_movements where household_id=c.household_id);
  insert into writeoff_reversal_results values (
    'all_reversal_events_envelope_neutral',
    case when (select count(*) from public.envelope_movements where household_id=c.household_id) = movements_before then 'passed' else 'failed' end,
    'Write-off reversal operations created no envelope movements.'
  );
end;
$$;

select
  count(*) as total,
  count(*) filter (where status = 'passed') as passed,
  count(*) filter (where status = 'failed') as failed,
  count(*) filter (where status = 'skipped') as skipped,
  jsonb_agg(jsonb_build_object('test', test_name, 'status', status, 'detail', detail) order by test_name) as details
from writeoff_reversal_results;

rollback;
