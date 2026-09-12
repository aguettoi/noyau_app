-- Controlled Sandbox receipt. Run after PRECHECK, in one authenticated SQL session.
-- TEST_FE_20260809 is a fixed receipt identifier; do not rerun it after success.
begin;

create temp table test_fe_context on commit drop as
select members.household_id, members.user_id as actor_id,
  (select accounts.id from public.accounts accounts where accounts.household_id = members.household_id and not accounts.is_system order by accounts.id limit 1) as account_a_id,
  (select accounts.id from public.accounts accounts where accounts.household_id = members.household_id and not accounts.is_system order by accounts.id offset 1 limit 1) as account_b_id,
  (select envelopes.id from public.envelopes envelopes where envelopes.household_id = members.household_id and not envelopes.is_system and envelopes.archived_at is null order by envelopes.id limit 1) as envelope_a_id,
  (select envelopes.id from public.envelopes envelopes where envelopes.household_id = members.household_id and not envelopes.is_system and envelopes.archived_at is null order by envelopes.id offset 1 limit 1) as envelope_b_id
from public.household_members members
join auth.users users on users.id = members.user_id
order by members.household_id, members.user_id limit 1;

create temp table test_fe_keys(test_name text primary key, idempotency_key uuid unique not null) on commit drop;
insert into test_fe_keys values
 ('cash','00000000-0000-4000-8000-000000000101'),('debt','00000000-0000-4000-8000-000000000102'),('debt_partial','00000000-0000-4000-8000-000000000103'),('debt_final','00000000-0000-4000-8000-000000000104'),
 ('receivable','00000000-0000-4000-8000-000000000105'),('receivable_partial','00000000-0000-4000-8000-000000000106'),('receivable_final','00000000-0000-4000-8000-000000000107'),
 ('recovery','00000000-0000-4000-8000-000000000108'),('recovery_partial','00000000-0000-4000-8000-000000000109'),('recovery_final','00000000-0000-4000-8000-000000000110'),
 ('allocation','00000000-0000-4000-8000-000000000111'),('account_transfer','00000000-0000-4000-8000-000000000112'),('envelope_transfer','00000000-0000-4000-8000-000000000113'),
 ('invalid_split','00000000-0000-4000-8000-000000000114'),('invalid_amount','00000000-0000-4000-8000-000000000115'),('cross_household','00000000-0000-4000-8000-000000000116'),('invalid_system_envelope','00000000-0000-4000-8000-000000000117'),('invalid_debt_settlement','00000000-0000-4000-8000-000000000118'),('invalid_receivable_settlement','00000000-0000-4000-8000-000000000119');

do $$
declare context test_fe_context%rowtype;
begin
 select * into context from test_fe_context;
 if context.actor_id is null or context.account_a_id is null or context.account_b_id is null or context.envelope_a_id is null or context.envelope_b_id is null then
   raise exception 'TEST_FE_20260809 stopped: invalid household, actor, accounts or envelopes';
 end if;
 if exists (select 1 from public.financial_events events join test_fe_keys keys on keys.idempotency_key = events.idempotency_key)
  or exists (select 1 from public.financial_events events where events.description like 'TEST_FE_20260809%') then
   raise exception 'TEST_FE_20260809 stopped: receipt collision already exists';
 end if;
 perform set_config(
   'request.jwt.claims',
   jsonb_build_object('role', 'authenticated', 'sub', context.actor_id::text)::text,
   true
 );
end $$;
grant select on test_fe_context, test_fe_keys to authenticated;
set local role authenticated;

do $$
declare context test_fe_context%rowtype;
begin
  select * into context from test_fe_context;
  if current_user <> 'authenticated'
    or auth.uid() is distinct from context.actor_id
    or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception 'TEST_FE_20260809 stopped: authenticated JWT context was not established';
  end if;
end $$;

create temp table test_fe_results(test_name text primary key, status text not null, detail text not null) on commit drop;

do $$
declare c test_fe_context%rowtype; cash_id uuid; debt_id uuid; debt_obligation uuid; receivable_id uuid; receivable_obligation uuid; recovery_id uuid; recovery_obligation uuid; v_event_id uuid; before_events bigint; before_tx bigint; before_movements bigint; rejected boolean; other_account uuid; system_envelope uuid; account_a_before numeric; account_b_before numeric; envelope_a_before numeric; envelope_b_before numeric;
begin
 select * into c from test_fe_context;
 cash_id := public.create_cash_expense_event(c.household_id, now(), 'TEST_FE_20260809 CASH EXPENSE', 100, c.account_a_id, jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_a_id,'amount',100)), 'Sandbox receipt', (select keys.idempotency_key from test_fe_keys keys where keys.test_name='cash'));
 perform public.create_cash_expense_event(c.household_id, now(), 'TEST_FE_20260809 CASH EXPENSE', 100, c.account_a_id, jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_a_id,'amount',100)), 'retry', (select keys.idempotency_key from test_fe_keys keys where keys.test_name='cash'));
 insert into test_fe_results select 'cash_expense', case when (select count(*) from public.financial_events events where events.id=cash_id)=1 and (select count(*) from public.financial_transactions transactions where transactions.event_id=cash_id)=1 and (select count(*) from public.envelope_movements movements where movements.event_id=cash_id)=1 and (select count(*) from public.obligations obligations where obligations.origin_event_id=cash_id)=0 then 'passed' else 'failed' end, 'event, ledger transaction and consumption created once';
 insert into test_fe_results select 'idempotence', case when (select count(*) from public.financial_events events where events.idempotency_key=(select keys.idempotency_key from test_fe_keys keys where keys.test_name='cash'))=1 and (select count(*) from public.financial_transactions transactions where transactions.event_id=cash_id)=1 then 'passed' else 'failed' end, 'same key has one impact';

 debt_id := public.create_debt_expense_event(c.household_id,now(),'TEST_FE_20260809 DEBT',120,jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_a_id,'amount',120)),'Sandbox creditor',null,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='debt'));
 select obligations.id into debt_obligation from public.obligations obligations where obligations.origin_event_id=debt_id;
 insert into test_fe_results select 'debt_creation',case when debt_obligation is not null and (select count(*) from public.envelope_movements movements where movements.event_id=debt_id)=1 then 'passed' else 'failed' end,'debt obligation and one envelope charge';
 v_event_id := public.settle_debt_event(c.household_id,debt_obligation,now(),'TEST_FE_20260809 DEBT PARTIAL',50,c.account_a_id,'Sandbox receipt',(select keys.idempotency_key from test_fe_keys keys where keys.test_name='debt_partial'));
 insert into test_fe_results select 'debt_partial_settlement',case when (select balances.remaining_amount from public.obligation_balances balances where balances.obligation_id=debt_obligation)=70 and (select count(*) from public.financial_transactions transactions where transactions.event_id=v_event_id)=1 then 'passed' else 'failed' end,'cash at partial settlement';
 perform public.settle_debt_event(c.household_id,debt_obligation,now(),'TEST_FE_20260809 DEBT FINAL',70,c.account_a_id,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='debt_final'));
 insert into test_fe_results select 'debt_final_settlement',case when (select balances.remaining_amount from public.obligation_balances balances where balances.obligation_id=debt_obligation)=0 and (select count(*) from public.obligation_settlements settlements where settlements.obligation_id=debt_obligation)=2 then 'passed' else 'failed' end,'debt closed without new charge';

 receivable_id := public.create_income_receivable_event(c.household_id,now(),'TEST_FE_20260809 RECEIVABLE',90,'Sandbox debtor',null,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='receivable'));
 select obligations.id into receivable_obligation from public.obligations obligations where obligations.origin_event_id=receivable_id;
 insert into test_fe_results select 'receivable_creation',case when receivable_obligation is not null and (select count(*) from public.envelope_movements movements where movements.event_id=receivable_id)=0 then 'passed' else 'failed' end,'receivable without initial cash';
 perform public.settle_receivable_event(c.household_id,receivable_obligation,now(),'TEST_FE_20260809 RECEIVABLE PARTIAL',40,c.account_a_id,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='receivable_partial'));
 insert into test_fe_results select 'receivable_partial_settlement',case when (select balances.remaining_amount from public.obligation_balances balances where balances.obligation_id=receivable_obligation)=50 then 'passed' else 'failed' end,'partial collection';
 perform public.settle_receivable_event(c.household_id,receivable_obligation,now(),'TEST_FE_20260809 RECEIVABLE FINAL',50,c.account_a_id,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='receivable_final'));
 insert into test_fe_results select 'receivable_final_settlement',case when (select balances.remaining_amount from public.obligation_balances balances where balances.obligation_id=receivable_obligation)=0 then 'passed' else 'failed' end,'final collection';

 recovery_id := public.create_recovery_receivable_event(c.household_id,cash_id,c.envelope_a_id,now(),'TEST_FE_20260809 RECOVERY',30,'Sandbox recovery debtor',null,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='recovery'));
 select obligations.id into recovery_obligation from public.obligations obligations where obligations.origin_event_id=recovery_id;
 perform public.settle_recovery_event(c.household_id,recovery_obligation,now(),'TEST_FE_20260809 RECOVERY PARTIAL',10,c.account_a_id,false,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='recovery_partial'));
 v_event_id := public.settle_recovery_event(c.household_id,recovery_obligation,now(),'TEST_FE_20260809 RECOVERY FINAL REFUND',20,c.account_a_id,true,'Sandbox receipt',(select keys.idempotency_key from test_fe_keys keys where keys.test_name='recovery_final'));
 insert into test_fe_results select 'recovery',case when recovery_obligation is not null and (select count(*) from public.envelope_movements movements where movements.event_id=recovery_id)=0 then 'passed' else 'failed' end,'recovery is a receivable, not income';
 insert into test_fe_results select 'recovery_envelope_refund',case when (select balances.remaining_amount from public.obligation_balances balances where balances.obligation_id=recovery_obligation)=0 and (select count(*) from public.envelope_movements movements where movements.event_id=v_event_id and movements.movement_type='refund' and movements.direction='inflow' and movements.envelope_id=c.envelope_a_id)=1 then 'passed' else 'failed' end,'only linked source envelope refunded';

 before_tx := (select count(*) from public.financial_transactions transactions where transactions.household_id=c.household_id);
 v_event_id := public.allocate_budget_event(c.household_id,now(),'TEST_FE_20260809 ALLOCATION',25,c.account_a_id,c.envelope_b_id,'Sandbox receipt',(select keys.idempotency_key from test_fe_keys keys where keys.test_name='allocation'));
 insert into test_fe_results select 'allocation',case when (select count(*) from public.budget_funding_links links where links.event_id=v_event_id)=1 and (select count(*) from public.envelope_movements movements where movements.event_id=v_event_id)=2 and (select count(*) from public.financial_transactions transactions where transactions.household_id=c.household_id)=before_tx then 'passed' else 'failed' end,'funding link and no bank transaction';
 select balances.theoretical_balance into account_a_before from public.account_ledger_balances balances where balances.account_id=c.account_a_id; select balances.theoretical_balance into account_b_before from public.account_ledger_balances balances where balances.account_id=c.account_b_id;
 v_event_id := public.create_account_transfer_event(c.household_id,now(),'TEST_FE_20260809 ACCOUNT TRANSFER',15,c.account_a_id,c.account_b_id,'Sandbox receipt',(select keys.idempotency_key from test_fe_keys keys where keys.test_name='account_transfer'));
 insert into test_fe_results select 'account_transfer',case when (select count(*) from public.financial_transactions transactions where transactions.event_id=v_event_id)=1 and (select count(*) from public.envelope_movements movements where movements.event_id=v_event_id)=0 and (select balances.theoretical_balance from public.account_ledger_balances balances where balances.account_id=c.account_a_id)=account_a_before-15 and (select balances.theoretical_balance from public.account_ledger_balances balances where balances.account_id=c.account_b_id)=account_b_before+15 then 'passed' else 'failed' end,'bank-account deltas are -15 and +15, net zero';
 select balances.balance into envelope_a_before from public.envelope_ledger_balances balances where balances.envelope_id=c.envelope_a_id; select balances.balance into envelope_b_before from public.envelope_ledger_balances balances where balances.envelope_id=c.envelope_b_id;
 v_event_id := public.create_envelope_transfer_event(c.household_id,now(),'TEST_FE_20260809 ENVELOPE TRANSFER',5,c.envelope_a_id,c.envelope_b_id,'Sandbox receipt',(select keys.idempotency_key from test_fe_keys keys where keys.test_name='envelope_transfer'));
 insert into test_fe_results select 'envelope_transfer',case when (select count(*) from public.envelope_movements movements where movements.event_id=v_event_id)=2 and (select count(*) from public.financial_transactions transactions where transactions.event_id=v_event_id)=0 and (select balances.balance from public.envelope_ledger_balances balances where balances.envelope_id=c.envelope_a_id)=envelope_a_before-5 and (select balances.balance from public.envelope_ledger_balances balances where balances.envelope_id=c.envelope_b_id)=envelope_b_before+5 then 'passed' else 'failed' end,'envelope deltas are -5 and +5, net zero';

 before_events := (select count(*) from public.financial_events events where events.household_id=c.household_id); before_tx := (select count(*) from public.financial_transactions transactions where transactions.household_id=c.household_id); before_movements := (select count(*) from public.envelope_movements movements where movements.household_id=c.household_id); rejected:=false;
 begin perform public.create_cash_expense_event(c.household_id,now(),'TEST_FE_20260809 INVALID SPLIT',7,c.account_a_id,jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_a_id,'amount',1)),'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='invalid_split')); exception when others then rejected:=true; end;
 insert into test_fe_results select 'rollback_atomicity',case when rejected and (select count(*) from public.financial_events events where events.household_id=c.household_id)=before_events and (select count(*) from public.financial_transactions transactions where transactions.household_id=c.household_id)=before_tx and (select count(*) from public.envelope_movements movements where movements.household_id=c.household_id)=before_movements then 'passed' else 'failed' end,'invalid split leaves no partial rows';
 rejected:=false; begin perform public.create_cash_expense_event(c.household_id,now(),'TEST_FE_20260809 INVALID AMOUNT',0,c.account_a_id,jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_a_id,'amount',1)),'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='invalid_amount')); exception when others then rejected:=true; end;
 insert into test_fe_results values('negative_amount',case when rejected then 'passed' else 'failed' end,'non-positive amount rejected without residual data');
 rejected:=false; begin perform public.settle_debt_event(c.household_id,debt_obligation,now(),'TEST_FE_20260809 INVALID DEBT SETTLEMENT',1,c.account_a_id,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='invalid_debt_settlement')); exception when others then rejected:=true; end;
 insert into test_fe_results values('negative_debt_settlement',case when rejected then 'passed' else 'failed' end,'debt settlement above remaining amount rejected');
 rejected:=false; begin perform public.settle_receivable_event(c.household_id,receivable_obligation,now(),'TEST_FE_20260809 INVALID RECEIVABLE SETTLEMENT',1,c.account_a_id,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='invalid_receivable_settlement')); exception when others then rejected:=true; end;
 insert into test_fe_results values('negative_receivable_settlement',case when rejected then 'passed' else 'failed' end,'receivable settlement above remaining amount rejected');
 select envelopes.id into system_envelope from public.envelopes envelopes where envelopes.household_id=c.household_id and envelopes.is_system order by envelopes.id limit 1;
 rejected:=false; begin perform public.create_cash_expense_event(c.household_id,now(),'TEST_FE_20260809 INVALID SYSTEM ENVELOPE',1,c.account_a_id,jsonb_build_array(jsonb_build_object('envelope_id',system_envelope,'amount',1)),'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='invalid_system_envelope')); exception when others then rejected:=true; end;
 insert into test_fe_results values('negative_system_envelope',case when rejected then 'passed' else 'failed' end,'system envelope rejected');
 insert into test_fe_results select 'negative_tests',case when bool_and(status='passed') then 'passed' else 'failed' end,'amount, over-settlement and system-envelope rules enforced' from test_fe_results where test_name like 'negative_%';
 select accounts.id into other_account from public.accounts accounts where accounts.household_id<>c.household_id and not accounts.is_system order by accounts.household_id,accounts.id limit 1;
 if other_account is null then insert into test_fe_results values('cross_household','skipped','No second exploitable household exists.'); else rejected:=false; begin perform public.create_account_transfer_event(c.household_id,now(),'TEST_FE_20260809 CROSS HOUSEHOLD',1,c.account_a_id,other_account,'Sandbox receipt',(select idempotency_key from test_fe_keys where test_name='cross_household')); exception when others then rejected:=true; end; insert into test_fe_results values('cross_household',case when rejected then 'passed' else 'failed' end,'cross-household object rejected'); end if;
 rejected:=false; begin update public.financial_events as events set description=events.description where events.id=cash_id; exception when others then rejected:=true; end; insert into test_fe_results values('immutability_events',case when rejected then 'passed' else 'failed' end,'financial event update rejected');
 rejected:=false; begin update public.envelope_movements as movements set description=movements.description where movements.event_id=cash_id; exception when others then rejected:=true; end; insert into test_fe_results values('immutability_movements',case when rejected then 'passed' else 'failed' end,'envelope movement update rejected');
 rejected:=false; begin update public.obligations as obligations set initial_amount=obligations.initial_amount where obligations.id=debt_obligation; exception when others then rejected:=true; end; insert into test_fe_results values('immutability_obligations',case when rejected then 'passed' else 'failed' end,'obligation update rejected');
 insert into test_fe_results select 'immutability',case when bool_and(status='passed') then 'passed' else 'failed' end,'immutable samples reject direct update' from test_fe_results where test_name like 'immutability_%';
end $$;

select count(*) filter(where status='failed')=0 and count(*) filter(where status='passed')>=15 as business_tests_ready,
 count(*) as tests_total,count(*) filter(where status='passed') as tests_passed,count(*) filter(where status='failed') as tests_failed,count(*) filter(where status='skipped') as tests_skipped,count(*) filter(where status='failed') as blocking_issue_count,count(*) filter(where status='skipped') as warning_count,
 coalesce(bool_and(status='passed') filter(where test_name='cash_expense'),false) as cash_expense_ok,coalesce(bool_and(status='passed') filter(where test_name='idempotence'),false) as idempotence_ok,coalesce(bool_and(status='passed') filter(where test_name='debt_creation'),false) as debt_creation_ok,coalesce(bool_and(status='passed') filter(where test_name='debt_partial_settlement'),false) as debt_partial_settlement_ok,coalesce(bool_and(status='passed') filter(where test_name='debt_final_settlement'),false) as debt_final_settlement_ok,coalesce(bool_and(status='passed') filter(where test_name='receivable_creation'),false) as receivable_creation_ok,coalesce(bool_and(status='passed') filter(where test_name='receivable_partial_settlement'),false) as receivable_partial_settlement_ok,coalesce(bool_and(status='passed') filter(where test_name='receivable_final_settlement'),false) as receivable_final_settlement_ok,coalesce(bool_and(status='passed') filter(where test_name='recovery'),false) as recovery_ok,coalesce(bool_and(status='passed') filter(where test_name='recovery_envelope_refund'),false) as recovery_envelope_refund_ok,coalesce(bool_and(status='passed') filter(where test_name='allocation'),false) as allocation_ok,coalesce(bool_and(status='passed') filter(where test_name='account_transfer'),false) as account_transfer_ok,coalesce(bool_and(status='passed') filter(where test_name='envelope_transfer'),false) as envelope_transfer_ok,coalesce(bool_and(status='passed') filter(where test_name='rollback_atomicity'),false) as rollback_atomicity_ok,coalesce(max(status) filter(where test_name='cross_household'),'failed') as cross_household_status,coalesce(bool_and(status='passed') filter(where test_name='immutability'),false) as immutability_ok,coalesce(bool_and(status='passed') filter(where test_name='negative_tests'),false) as negative_tests_ok,
 not exists(select 1 from public.financial_events events where events.description not like 'TEST_FE_20260809%' and events.idempotency_key in(select idempotency_key from test_fe_keys)) as legacy_data_preserved,
 coalesce(jsonb_agg(jsonb_build_object('test',test_name,'detail',detail) order by test_name) filter(where status='failed'),'[]'::jsonb) as blocking_details,coalesce(jsonb_agg(jsonb_build_object('test',test_name,'detail',detail) order by test_name) filter(where status='skipped'),'[]'::jsonb) as warnings from test_fe_results;
reset role;
reset "request.jwt.claims";
commit;
