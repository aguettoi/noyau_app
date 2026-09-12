-- Transactional Sandbox receipt: mandatory source-envelope refund on Recovery
-- settlement. All fixtures and all attempted writes are rolled back.
begin;

create temp table recovery_refund_context on commit drop as
select members.household_id,
       members.user_id as actor_id,
       (select accounts.id from public.accounts accounts
        where accounts.household_id = members.household_id
          and not accounts.is_system
        order by accounts.id limit 1) as account_id,
       (select envelopes.id from public.envelopes envelopes
        where envelopes.household_id = members.household_id
          and not envelopes.is_system and envelopes.archived_at is null
        order by envelopes.id limit 1) as envelope_id
from public.household_members members
order by members.household_id, members.user_id
limit 1;

do $$
declare c recovery_refund_context%rowtype;
begin
  select * into c from recovery_refund_context;
  if c.actor_id is null or c.account_id is null or c.envelope_id is null then
    raise exception 'Recovery refund receipt requires an actor, account and ordinary envelope';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'role', 'authenticated', 'sub', c.actor_id::text
  )::text, true);
end;
$$;

grant select on recovery_refund_context to authenticated;
set local role authenticated;

create temp table recovery_refund_results(
  test_name text primary key, status text not null, detail text not null
) on commit drop;

do $$
declare
  c recovery_refund_context%rowtype;
  source_event uuid;
  recovery_event_id uuid;
  recovery_id uuid;
  partial_event uuid;
  final_event uuid;
  retry_event uuid;
  invalid_before bigint;
  rejected boolean := false;
  movement_count bigint;
  refund_total numeric;
  ledger_balanced boolean;
begin
  select * into c from recovery_refund_context;
  source_event := public.create_cash_expense_event(
    c.household_id, now(), 'TEST_RECOVERY_REFUND SOURCE', 60, c.account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 60)),
    'transactional receipt', '00000000-0000-4000-8000-000000000901'
  );
  recovery_event_id := public.create_recovery_receivable_event(
    c.household_id, source_event, c.envelope_id, now(), 'TEST_RECOVERY_REFUND',
    60, 'Test debtor', null, 'transactional receipt',
    '00000000-0000-4000-8000-000000000902'
  );
  select id into recovery_id
  from public.obligations
  where origin_event_id = recovery_event_id;
  insert into recovery_refund_results values (
    'recovery_fixture', 'passed', 'A 60 MAD Recovery has a linked source envelope.'
  );

  -- false intentionally proves that the legacy parameter can no longer bypass
  -- the canonical refund.
  partial_event := public.settle_recovery_event(
    c.household_id, recovery_id, now(), 'TEST_RECOVERY_REFUND PARTIAL', 20,
    c.account_id, false, 'transactional receipt',
    '00000000-0000-4000-8000-000000000903'
  );
  select coalesce(sum(amount), 0), count(*) into refund_total, movement_count
  from public.envelope_movements
  where event_id = partial_event and envelope_id = c.envelope_id
    and movement_type = 'refund' and direction = 'inflow';
  insert into recovery_refund_results values (
    'false_cannot_bypass_refund',
    case when refund_total = 20 and movement_count = 1 then 'passed' else 'failed' end,
    'p_refund_source_envelope=false still refunds the linked source envelope.'
  );
  insert into recovery_refund_results values (
    'partial_refund_exact',
    case when refund_total = 20 then 'passed' else 'failed' end,
    'A partial 20 MAD settlement refunds exactly 20 MAD.'
  );
  insert into recovery_refund_results values (
    'partial_remaining_exact',
    case when (select remaining_amount from public.obligation_balances
               where obligation_id = recovery_id) = 40 then 'passed' else 'failed' end,
    'The Recovery remaining balance is 40 MAD after the partial settlement.'
  );
  insert into recovery_refund_results values (
    'one_event_one_transaction_partial',
    case when (select count(*) from public.financial_transactions where event_id = partial_event) = 1
           and (select count(*) from public.obligation_settlements where event_id = partial_event) = 1
      then 'passed' else 'failed' end,
    'Partial settlement has one event, one transaction and one settlement.'
  );
  select coalesce(sum(debit), 0) = coalesce(sum(credit), 0)
    into ledger_balanced
  from public.financial_transaction_lines
  where transaction_id = (select id from public.financial_transactions where event_id = partial_event);
  insert into recovery_refund_results values (
    'ledger_balanced_partial',
    case when ledger_balanced then 'passed' else 'failed' end,
    'Partial settlement ledger transaction remains balanced.'
  );
  insert into recovery_refund_results values (
    'no_income_or_to_allocate_partial',
    case when not exists (select 1 from public.financial_events where id = partial_event and event_type = 'cash_income')
           and not exists (
             select 1 from public.envelope_movements movements join public.envelopes envelopes
               on envelopes.id = movements.envelope_id
             where movements.event_id = partial_event and envelopes.is_system
           ) then 'passed' else 'failed' end,
    'A Recovery settlement creates neither income nor an À répartir movement.'
  );

  retry_event := public.settle_recovery_event(
    c.household_id, recovery_id, now(), 'ignored retry', 20, c.account_id, false,
    'transactional receipt', '00000000-0000-4000-8000-000000000903'
  );
  insert into recovery_refund_results values (
    'idempotence',
    case when retry_event = partial_event
           and (select count(*) from public.envelope_movements where event_id = partial_event) = 1
      then 'passed' else 'failed' end,
    'Retrying the idempotency key does not duplicate the refund.'
  );

  final_event := public.settle_recovery_event(
    c.household_id, recovery_id, now(), 'TEST_RECOVERY_REFUND FINAL', 40,
    c.account_id, true, 'transactional receipt',
    '00000000-0000-4000-8000-000000000904'
  );
  insert into recovery_refund_results values (
    'final_refund_exact',
    case when (select coalesce(sum(amount), 0) from public.envelope_movements
               where event_id = final_event and movement_type = 'refund') = 40
           and (select remaining_amount from public.obligation_balances where obligation_id = recovery_id) = 0
      then 'passed' else 'failed' end,
    'The final 40 MAD settlement refunds 40 MAD and closes the Recovery.'
  );
  insert into recovery_refund_results values (
    'refunds_match_recovery_total',
    case when (select coalesce(sum(amount), 0) from public.envelope_movements
               where event_id in (partial_event, final_event) and movement_type = 'refund') = 60
      then 'passed' else 'failed' end,
    'Partial plus final refunds equal the 60 MAD Recovery exactly.'
  );

  invalid_before := (select count(*) from public.financial_events where household_id = c.household_id);
  rejected := false;
  begin
    perform public.settle_recovery_event(
      c.household_id, recovery_id, now(), 'TEST_RECOVERY_REFUND OVER', .01,
      c.account_id, false, 'transactional receipt',
      '00000000-0000-4000-8000-000000000905'
    );
  exception when others then
    rejected := true;
  end;
  insert into recovery_refund_results values (
    'oversettlement_rejected',
    case when rejected then 'passed' else 'failed' end,
    'A settlement above the remaining Recovery is rejected.'
  );
  insert into recovery_refund_results values (
    'rollback_after_rejection',
    case when (select count(*) from public.financial_events where household_id = c.household_id) = invalid_before
      then 'passed' else 'failed' end,
    'A rejected settlement leaves no partial financial event.'
  );
end;
$$;

select count(*) as total,
       count(*) filter (where status = 'passed') as passed,
       count(*) filter (where status = 'failed') as failed,
       count(*) filter (where status = 'skipped') as skipped,
       jsonb_agg(jsonb_build_object('test', test_name, 'status', status, 'detail', detail) order by test_name) as details
from recovery_refund_results;

reset role;
reset "request.jwt.claims";
rollback;
