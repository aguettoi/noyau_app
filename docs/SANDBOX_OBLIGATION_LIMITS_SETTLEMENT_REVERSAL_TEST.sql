-- Transactional regression suite for Phase 1 obligation limits.
-- Run only against Sandbox. Every fixture and write is rolled back.
begin;

create temp table obligation_limit_results (
  test_name text primary key,
  status text not null,
  detail text not null
) on commit drop;

do $$
declare
  h uuid;
  actor uuid;
  account_id uuid;
  v_envelope_id uuid;
  debt_event uuid; debt_id uuid; debt_settlement uuid; debt_reversal uuid; debt_writeoff uuid;
  income_event uuid; income_id uuid; income_settlement uuid; income_reversal uuid; income_writeoff uuid; income_movement uuid;
  expense_event uuid; recovery_event uuid; recovery_id uuid; recovery_settlement uuid; recovery_reversal uuid; recovery_writeoff uuid;
  idempotent_event uuid; idempotent_debt uuid; retry_event uuid;
  rejected boolean := false;
  before_events bigint;
  other_household uuid;
begin
  select id into h
  from public.households
  where name = 'FINANCIEL PILOTE — GOLDEN LEDGER E2E';
  select user_id into actor
  from public.household_members
  where household_id = h
  order by created_at
  limit 1;
  select id into account_id from public.accounts where household_id = h and name = 'GL-E2E Banque A';
  select id into v_envelope_id from public.envelopes where household_id = h and name = 'GL-E2E Nourriture';
  if actor is null or account_id is null or v_envelope_id is null then
    raise exception 'Missing Golden Ledger test context';
  end if;
  perform set_config('request.jwt.claim.sub', actor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- Debt: settlement total -> partial reversal -> exact write-off.
  debt_event := public.create_debt_expense_event(h, now(), 'TEST_LIMIT_DEBT', 100,
    jsonb_build_array(jsonb_build_object('envelope_id', v_envelope_id, 'amount', 100)),
    'Test creditor', null, 'transactional test', gen_random_uuid());
  select id into debt_id from public.obligations where origin_event_id = debt_event;
  perform public.settle_debt_event(h, debt_id, now(), 'TEST_LIMIT_DEBT settlement', 100, account_id, null, gen_random_uuid());
  select id into debt_settlement from public.obligation_settlements where obligation_id = debt_id;
  debt_reversal := public.reverse_debt_settlement_event(h, debt_settlement, now(), 20, 'partial correction', null, gen_random_uuid());
  debt_writeoff := public.writeoff_debt_event(h, debt_id, now(), 20, 'remaining write-off', null, gen_random_uuid());
  insert into obligation_limit_results
  select 'debt_total_settlement_reversal_writeoff',
    case when gross_settled_amount=100 and settlement_reversed_amount=20 and net_settled_amount=80
              and written_off_amount=20 and remaining_amount=0 and initial_amount=net_settled_amount+written_off_amount+remaining_amount
         then 'passed' else 'failed' end,
    'Debt uses gross - reversal + write-off exactly.'
  from public.obligation_balances where obligation_id=debt_id;
  insert into obligation_limit_results
  select 'debt_financial_event_gl_chain',
    case when (select count(*) from public.financial_transactions where event_id in(debt_reversal,debt_writeoff))=2
              and not exists(select 1 from public.envelope_movements where event_id in(debt_reversal,debt_writeoff))
         then 'passed' else 'failed' end,
    'Debt correction and write-off remain FinancialEvent/GL-only operations.';

  -- Income: same invariant and an explicit source envelope reversal.
  income_event := public.create_income_receivable_event(h, now(), 'TEST_LIMIT_INCOME', 100, 'Test debtor', null, null, gen_random_uuid());
  select id into income_id from public.obligations where origin_event_id = income_event;
  perform public.settle_receivable_event(h, income_id, now(), 'TEST_LIMIT_INCOME settlement', 100, account_id, null, gen_random_uuid(),
    jsonb_build_array(jsonb_build_object('envelope_id', v_envelope_id, 'amount', 100)));
  select id into income_settlement from public.obligation_settlements where obligation_id = income_id;
  select id into income_movement from public.envelope_movements where event_id=(select event_id from public.obligation_settlements where id=income_settlement) and envelope_id=v_envelope_id;
  income_reversal := public.reverse_income_receivable_settlement_event(h, income_settlement, now(), 20, 'partial correction',
    jsonb_build_array(jsonb_build_object('source_movement_id', income_movement, 'amount', 20)), null, gen_random_uuid());
  income_writeoff := public.writeoff_income_receivable_event(h, income_id, now(), 20, 'remaining write-off', null, gen_random_uuid());
  insert into obligation_limit_results
  select 'income_total_settlement_reversal_writeoff',
    case when gross_settled_amount=100 and settlement_reversed_amount=20 and net_settled_amount=80
              and written_off_amount=20 and remaining_amount=0 and initial_amount=net_settled_amount+written_off_amount+remaining_amount
         then 'passed' else 'failed' end,
    'Income uses gross - reversal + write-off exactly.'
  from public.obligation_balances where obligation_id=income_id;
  insert into obligation_limit_results
  select 'income_reversal_envelope_chain',
    case when exists(select 1 from public.envelope_movements where event_id=income_reversal and envelope_id=v_envelope_id and movement_type='reversal' and direction='outflow' and amount=20)
              and not exists(select 1 from public.envelope_movements where event_id=income_writeoff)
         then 'passed' else 'failed' end,
    'Income reversal reverses only its recorded allocation; write-off has no envelope movement.';

  -- Recovery: source expense, settlement/refund, reversal, then write-off.
  expense_event := public.create_cash_expense_event(h, now(), 'TEST_LIMIT_RECOVERY source', 100, account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', v_envelope_id, 'amount', 100)), null, gen_random_uuid());
  recovery_event := public.create_recovery_receivable_event(h, expense_event, v_envelope_id, now(), 'TEST_LIMIT_RECOVERY', 100, 'Test debtor', null, null, gen_random_uuid());
  select id into recovery_id from public.obligations where origin_event_id=recovery_event;
  perform public.settle_recovery_event(h, recovery_id, now(), 'TEST_LIMIT_RECOVERY settlement', 100, account_id, true, null, gen_random_uuid());
  select id into recovery_settlement from public.obligation_settlements where obligation_id=recovery_id;
  recovery_reversal := public.reverse_recovery_settlement_event(h, recovery_settlement, now(), 20, 'partial correction', null, gen_random_uuid());
  recovery_writeoff := public.writeoff_recovery_event(h, recovery_id, now(), 20, 'remaining write-off', null, gen_random_uuid());
  insert into obligation_limit_results
  select 'recovery_total_settlement_reversal_writeoff',
    case when gross_settled_amount=100 and settlement_reversed_amount=20 and net_settled_amount=80
              and written_off_amount=20 and remaining_amount=0 and initial_amount=net_settled_amount+written_off_amount+remaining_amount
         then 'passed' else 'failed' end,
    'Recovery uses gross - reversal + write-off exactly.'
  from public.obligation_balances where obligation_id=recovery_id;
  insert into obligation_limit_results
  select 'recovery_refund_reversal_no_writeoff_movement',
    case when exists(select 1 from public.envelope_movements where event_id=recovery_reversal and envelope_id=v_envelope_id and movement_type='reversal' and direction='outflow' and amount=20)
              and not exists(select 1 from public.envelope_movements where event_id=recovery_writeoff)
         then 'passed' else 'failed' end,
    'Recovery reversal counters the exact refund; write-off creates no refund.';
  insert into obligation_limit_results
  select 'recovery_cap_unchanged',
    case when (select sum(initial_amount) from public.obligations where recovery_source_event_id=expense_event)=100
         then 'passed' else 'failed' end,
    'Settlement reversal and write-off do not release Recovery source capacity.';

  -- Exact limit, excess rejection and rollback.
  idempotent_event := public.create_debt_expense_event(h, now(), 'TEST_LIMIT_IDEMPOTENCY', 20,
    jsonb_build_array(jsonb_build_object('envelope_id', v_envelope_id, 'amount', 20)), null, null, null, gen_random_uuid());
  select id into idempotent_debt from public.obligations where origin_event_id=idempotent_event;
  retry_event := public.writeoff_debt_event(h,idempotent_debt,now(),20,'idempotent write-off',null,'00000000-0000-4000-8000-000000009901');
  perform public.writeoff_debt_event(h,idempotent_debt,now(),20,'idempotent write-off',null,'00000000-0000-4000-8000-000000009901');
  insert into obligation_limit_results values ('writeoff_exact_and_idempotent',
    case when (select remaining_amount from public.obligation_balances where obligation_id=idempotent_debt)=0
              and (select count(*) from public.obligation_adjustments where financial_event_id=retry_event)=1 then 'passed' else 'failed' end,
    'Exact write-off succeeds once for the same idempotency key.');
  before_events := (select count(*) from public.financial_events where household_id=h);
  begin
    perform public.writeoff_debt_event(h,idempotent_debt,now(),1,'over limit',null,gen_random_uuid());
  exception when others then rejected := true;
  end;
  insert into obligation_limit_results values ('writeoff_over_remaining_rolls_back',
    case when rejected and (select count(*) from public.financial_events where household_id=h)=before_events then 'passed' else 'failed' end,
    'Write-off above remaining leaves no FinancialEvent.');

  insert into public.households(name)
  values ('TEST_LIMIT_OTHER_HOUSEHOLD_ROLLBACK')
  returning id into other_household;
  rejected := false;
  begin
    perform public.writeoff_debt_event(other_household,idempotent_debt,now(),1,'cross household',null,gen_random_uuid());
  exception when others then rejected := true;
  end;
  insert into obligation_limit_results values ('other_household_rejected',
    case when rejected then 'passed' else 'failed' end,
    'A caller cannot write off another household obligation.');
end $$;

select count(*) as total,
       count(*) filter (where status='passed') as passed,
       count(*) filter (where status='failed') as failed,
       count(*) filter (where status='skipped') as skipped,
       jsonb_agg(jsonb_build_object('test',test_name,'status',status,'detail',detail) order by test_name) as details
from obligation_limit_results;

rollback;
