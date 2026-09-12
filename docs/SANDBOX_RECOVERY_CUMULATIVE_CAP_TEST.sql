-- Transactional Sandbox receipt for the Recovery cumulative cap.
-- All business rows are rolled back at the end of this script.
begin;

create temp table recovery_cap_context on commit drop as
select members.household_id,
       members.user_id as actor_id,
       (
         select accounts.id
         from public.accounts accounts
         where accounts.household_id = members.household_id
           and not accounts.is_system
         order by accounts.id
         limit 1
       ) as account_id,
       (
         select envelopes.id
         from public.envelopes envelopes
         where envelopes.household_id = members.household_id
           and not envelopes.is_system
           and envelopes.archived_at is null
         order by envelopes.id
         limit 1
       ) as envelope_id
from public.household_members members
order by members.household_id, members.user_id
limit 1;

do $$
declare context recovery_cap_context%rowtype;
begin
  select * into context from recovery_cap_context;
  if context.actor_id is null
    or context.account_id is null
    or context.envelope_id is null then
    raise exception 'Recovery cumulative-cap test requires an actor, account and envelope';
  end if;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'authenticated', 'sub', context.actor_id::text)::text,
    true
  );
end;
$$;

grant select on recovery_cap_context to authenticated;
set local role authenticated;

create temp table recovery_cap_results(
  test_name text primary key,
  status text not null,
  detail text not null
) on commit drop;

do $$
declare
  c recovery_cap_context%rowtype;
  source_a uuid;
  source_b uuid;
  source_c uuid;
  other_source uuid;
  recovery_a uuid;
  recovery_b uuid;
  retry_event uuid;
  before_events bigint;
  before_transactions bigint;
  before_obligations bigint;
  rejected boolean;
  committed numeric(14, 2);
begin
  select * into c from recovery_cap_context;

  source_a := public.create_cash_expense_event(
    c.household_id, now(), 'TEST_RECOVERY_CAP SOURCE A', 100,
    c.account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 100)),
    'transactional test', '00000000-0000-4000-8000-000000000801'
  );
  insert into recovery_cap_results values (
    'source_without_recovery',
    case when source_a is not null then 'passed' else 'failed' end,
    'A 100 MAD source expense starts with 100 MAD recoverable.'
  );

  recovery_a := public.create_recovery_receivable_event(
    c.household_id, source_a, c.envelope_id, now(),
    'TEST_RECOVERY_CAP RECOVERY 60', 60, 'Test debtor', null,
    'transactional test', '00000000-0000-4000-8000-000000000802'
  );
  select coalesce(sum(initial_amount), 0) into committed
  from public.obligations
  where recovery_source_event_id = source_a and receivable_kind = 'recovery';
  insert into recovery_cap_results values (
    'remaining_after_60',
    case when committed = 60 then 'passed' else 'failed' end,
    'A 60 MAD recovery reserves 60 MAD, leaving 40 MAD.'
  );

  recovery_b := public.create_recovery_receivable_event(
    c.household_id, source_a, c.envelope_id, now(),
    'TEST_RECOVERY_CAP RECOVERY 40', 40, 'Test debtor', null,
    'transactional test', '00000000-0000-4000-8000-000000000803'
  );
  select coalesce(sum(initial_amount), 0) into committed
  from public.obligations
  where recovery_source_event_id = source_a and receivable_kind = 'recovery';
  insert into recovery_cap_results values (
    'exact_cumulative_cap',
    case when recovery_b is not null and committed = 100 then 'passed' else 'failed' end,
    'A cumulative recovery exactly equal to the 100 MAD source is accepted.'
  );

  before_events := (select count(*) from public.financial_events where household_id = c.household_id);
  before_transactions := (select count(*) from public.financial_transactions where household_id = c.household_id);
  before_obligations := (select count(*) from public.obligations where household_id = c.household_id);
  rejected := false;
  begin
    perform public.create_recovery_receivable_event(
      c.household_id, source_a, c.envelope_id, now(),
      'TEST_RECOVERY_CAP OVER 100', 0.01, 'Test debtor', null,
      'transactional test', '00000000-0000-4000-8000-000000000804'
    );
  exception when others then
    rejected := sqlerrm = 'Recovery amount exceeds remaining recoverable amount';
  end;
  insert into recovery_cap_results values (
    'reject_after_cap',
    case when rejected then 'passed' else 'failed' end,
    'No recovery can be created after the cumulative cap is exhausted.'
  );
  insert into recovery_cap_results values (
    'rollback_after_rejection',
    case when (select count(*) from public.financial_events where household_id = c.household_id) = before_events
           and (select count(*) from public.financial_transactions where household_id = c.household_id) = before_transactions
           and (select count(*) from public.obligations where household_id = c.household_id) = before_obligations
      then 'passed' else 'failed' end,
    'A rejected over-cap request leaves no partial event, transaction or obligation.'
  );

  source_b := public.create_cash_expense_event(
    c.household_id, now(), 'TEST_RECOVERY_CAP SOURCE B', 100,
    c.account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 100)),
    'transactional test', '00000000-0000-4000-8000-000000000805'
  );
  perform public.create_recovery_receivable_event(
    c.household_id, source_b, c.envelope_id, now(),
    'TEST_RECOVERY_CAP SOURCE B 60', 60, 'Test debtor', null,
    'transactional test', '00000000-0000-4000-8000-000000000806'
  );
  rejected := false;
  begin
    perform public.create_recovery_receivable_event(
      c.household_id, source_b, c.envelope_id, now(),
      'TEST_RECOVERY_CAP SOURCE B 40.01', 40.01, 'Test debtor', null,
      'transactional test', '00000000-0000-4000-8000-000000000807'
    );
  exception when others then
    rejected := sqlerrm = 'Recovery amount exceeds remaining recoverable amount';
  end;
  insert into recovery_cap_results values (
    'reject_over_remaining_40',
    case when rejected then 'passed' else 'failed' end,
    'A 40.01 MAD request is rejected when only 40 MAD remains.'
  );

  retry_event := public.create_recovery_receivable_event(
    c.household_id, source_b, c.envelope_id, now(),
    'TEST_RECOVERY_CAP SOURCE B 60', 60, 'Test debtor', null,
    'retry', '00000000-0000-4000-8000-000000000806'
  );
  insert into recovery_cap_results values (
    'idempotence',
    case when retry_event = (
      select id from public.financial_events
      where idempotency_key = '00000000-0000-4000-8000-000000000806'::uuid
    )
      and (select count(*) from public.obligations where recovery_source_event_id = source_b) = 1
      then 'passed' else 'failed' end,
    'Retrying the same idempotency key reserves capacity only once.'
  );
  insert into recovery_cap_results values (
    'source_independence',
    case when (select coalesce(sum(initial_amount), 0) from public.obligations
               where recovery_source_event_id = source_a) = 100
           and (select coalesce(sum(initial_amount), 0) from public.obligations
                where recovery_source_event_id = source_b) = 60
      then 'passed' else 'failed' end,
    'Recoveries for another source expense are independent.'
  );

  source_c := public.create_cash_expense_event(
    c.household_id, now(), 'TEST_RECOVERY_CAP SOURCE C', 100,
    c.account_id,
    jsonb_build_array(jsonb_build_object('envelope_id', c.envelope_id, 'amount', 100)),
    'transactional test', '00000000-0000-4000-8000-000000000808'
  );
  perform public.create_recovery_receivable_event(
    c.household_id, source_c, c.envelope_id, now(),
    'TEST_RECOVERY_CAP SOURCE C 60', 60, 'Test debtor', null,
    'transactional test', '00000000-0000-4000-8000-000000000809'
  );
  perform public.create_recovery_receivable_event(
    c.household_id, source_c, c.envelope_id, now(),
    'TEST_RECOVERY_CAP SOURCE C 30', 30, 'Test debtor', null,
    'transactional test', '00000000-0000-4000-8000-000000000810'
  );
  rejected := false;
  begin
    perform public.create_recovery_receivable_event(
      c.household_id, source_c, c.envelope_id, now(),
      'TEST_RECOVERY_CAP SOURCE C SECOND 30', 30, 'Test debtor', null,
      'transactional test', '00000000-0000-4000-8000-000000000811'
    );
  exception when others then
    rejected := sqlerrm = 'Recovery amount exceeds remaining recoverable amount';
  end;
  insert into recovery_cap_results values (
    'serialized_competing_reservations',
    case when rejected
           and (select coalesce(sum(initial_amount), 0) from public.obligations
                where recovery_source_event_id = source_c) = 90
      then 'passed' else 'failed' end,
    'After 60 + 30, a competing second 30 request cannot exceed the 100 MAD source.'
  );

  select events.id into other_source
  from public.financial_events events
  where events.household_id <> c.household_id
    and events.event_type in ('cash_expense', 'debt_expense')
  order by events.created_at
  limit 1;
  if other_source is null then
    insert into recovery_cap_results values (
      'other_household_isolation',
      'skipped',
      'No second household expense is available in this Sandbox receipt.'
    );
  else
    rejected := false;
    begin
      perform public.create_recovery_receivable_event(
        c.household_id, other_source, c.envelope_id, now(),
        'TEST_RECOVERY_CAP OTHER HOUSEHOLD', 1, 'Test debtor', null,
        'transactional test', '00000000-0000-4000-8000-000000000812'
      );
    exception when others then
      rejected := true;
    end;
    insert into recovery_cap_results values (
      'other_household_isolation',
      case when rejected then 'passed' else 'failed' end,
      'A source expense from another household is rejected.'
    );
  end if;
  insert into recovery_cap_results values (
    'reversal_model',
    'skipped',
    'The current immutable obligation model exposes no recovery cancellation or reversal flow.'
  );
  insert into recovery_cap_results values (
    'concurrency_lock_contract',
    case when position('for update of transactions' in pg_get_functiondef(
      'public.create_recovery_receivable_event(uuid,uuid,uuid,timestamptz,text,numeric,text,date,text,uuid)'::regprocedure
    )) > 0 then 'passed' else 'failed' end,
    'The source transaction lock serializes concurrent reservations for one expense.'
  );
end;
$$;

select
  count(*) as total,
  count(*) filter (where status = 'passed') as passed,
  count(*) filter (where status = 'failed') as failed,
  count(*) filter (where status = 'skipped') as skipped,
  jsonb_agg(jsonb_build_object('test', test_name, 'status', status, 'detail', detail) order by test_name) as details
from recovery_cap_results;

reset role;
reset "request.jwt.claims";
rollback;
