-- Transactional Phase 1 receipt. All fixtures are rolled back.
begin;
create temp table writeoff_context on commit drop as
select hm.household_id, hm.user_id as actor_id,
  (select id from public.accounts a where a.household_id=hm.household_id and not a.is_system order by id limit 1) account_id,
  (select id from public.envelopes e where e.household_id=hm.household_id and not e.is_system and e.archived_at is null order by id limit 1) envelope_id
from public.household_members hm order by hm.household_id, hm.user_id limit 1;
do $$ declare c writeoff_context%rowtype; begin select * into c from writeoff_context; if c.actor_id is null or c.account_id is null or c.envelope_id is null then raise exception 'Missing fixture context'; end if; perform set_config('request.jwt.claims', jsonb_build_object('role','authenticated','sub',c.actor_id::text)::text,true); end $$;
grant select on writeoff_context to authenticated;
set local role authenticated;
create temp table writeoff_results(test_name text primary key,status text not null,detail text not null) on commit drop;
do $$
declare c writeoff_context%rowtype; debt_event uuid; income_event uuid; recovery_source uuid; recovery_event uuid; debt_id uuid; income_id uuid; recovery_id uuid; v_writeoff_event uuid; retry uuid; rejected boolean; count_before bigint;
begin
select * into c from writeoff_context;
debt_event:=public.create_debt_expense_event(c.household_id,now(),'TEST_WO_DEBT',100,jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_id,'amount',100)),'Creditor',null,'test','00000000-0000-4000-8000-000000001001');
select id into debt_id from public.obligations where origin_event_id=debt_event;
v_writeoff_event:=public.writeoff_debt_event(c.household_id,debt_id,now(),40,'Partial debt writeoff','test','00000000-0000-4000-8000-000000001002');
insert into writeoff_results values('debt_partial',case when (select written_off_amount from public.obligation_balances where obligation_id=debt_id)=40 and (select remaining_amount from public.obligation_balances where obligation_id=debt_id)=60 then 'passed' else 'failed' end,'Partial debt write-off updates only the balance.');
perform public.writeoff_debt_event(c.household_id,debt_id,now(),60,'Final debt writeoff','test','00000000-0000-4000-8000-000000001003');
insert into writeoff_results values('debt_total',case when (select status from public.obligation_balances where obligation_id=debt_id)='written_off' then 'passed' else 'failed' end,'Final debt write-off closes the obligation.');
insert into writeoff_results values('debt_gl',case when (select count(*) from public.financial_transactions transactions where transactions.event_id=v_writeoff_event)=1 then 'passed' else 'failed' end,'Debt write-off creates one GL transaction.');
insert into writeoff_results values('debt_no_account_or_envelope',case when not exists(select 1 from public.envelope_movements movements where movements.event_id=v_writeoff_event) then 'passed' else 'failed' end,'Debt write-off creates no envelope movement.');
income_event:=public.create_income_receivable_event(c.household_id,now(),'TEST_WO_INCOME',100,'Debtor',null,'test','00000000-0000-4000-8000-000000001004'); select id into income_id from public.obligations where origin_event_id=income_event;
v_writeoff_event:=public.writeoff_income_receivable_event(c.household_id,income_id,now(),30,'Partial income writeoff','test','00000000-0000-4000-8000-000000001005');
insert into writeoff_results values('income_partial',case when (select written_off_amount from public.obligation_balances where obligation_id=income_id)=30 and (select remaining_amount from public.obligation_balances where obligation_id=income_id)=70 then 'passed' else 'failed' end,'Partial income write-off is tracked separately.');
perform public.writeoff_income_receivable_event(c.household_id,income_id,now(),70,'Final income writeoff','test','00000000-0000-4000-8000-000000001006');
insert into writeoff_results values('income_total',case when (select status from public.obligation_balances where obligation_id=income_id)='written_off' then 'passed' else 'failed' end,'Final income write-off closes the receivable.');
insert into writeoff_results values('income_gl_loss_receivable',case when (select count(*) from public.financial_transactions transactions where transactions.event_id=v_writeoff_event)=1 then 'passed' else 'failed' end,'Income write-off creates one loss/receivable GL transaction.');
insert into writeoff_results values('income_no_revenue_or_envelope',case when not exists(select 1 from public.envelope_movements movements where movements.event_id=v_writeoff_event) then 'passed' else 'failed' end,'Income write-off creates neither envelope movement nor cash income.');
recovery_source:=public.create_cash_expense_event(c.household_id,now(),'TEST_WO_RECOVERY_SOURCE',100,c.account_id,jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_id,'amount',100)),'test','00000000-0000-4000-8000-000000001007');
recovery_event:=public.create_recovery_receivable_event(c.household_id,recovery_source,c.envelope_id,now(),'TEST_WO_RECOVERY',60,'Debtor',null,'test','00000000-0000-4000-8000-000000001008'); select id into recovery_id from public.obligations where origin_event_id=recovery_event;
v_writeoff_event:=public.writeoff_recovery_event(c.household_id,recovery_id,now(),20,'Partial recovery writeoff','test','00000000-0000-4000-8000-000000001009');
insert into writeoff_results values('recovery_partial',case when (select written_off_amount from public.obligation_balances where obligation_id=recovery_id)=20 and (select remaining_amount from public.obligation_balances where obligation_id=recovery_id)=40 then 'passed' else 'failed' end,'Partial Recovery write-off reduces only its remaining balance.');
insert into writeoff_results values('recovery_gl',case when (select count(*) from public.financial_transactions transactions where transactions.event_id=v_writeoff_event)=1 then 'passed' else 'failed' end,'Recovery write-off creates one recovery/receivable GL transaction.');
insert into writeoff_results values('recovery_no_refund',case when not exists(select 1 from public.envelope_movements movements where movements.event_id=v_writeoff_event) then 'passed' else 'failed' end,'Recovery write-off creates no refund or envelope movement.');
insert into writeoff_results values('recovery_cap_unchanged',case when (select coalesce(sum(initial_amount),0) from public.obligations where recovery_source_event_id=recovery_source)=60 then 'passed' else 'failed' end,'Recovery write-off never releases source capacity.');
perform public.writeoff_recovery_event(c.household_id,recovery_id,now(),40,'Final recovery writeoff','test','00000000-0000-4000-8000-000000001010');
insert into writeoff_results values('recovery_total',case when (select status from public.obligation_balances where obligation_id=recovery_id)='written_off' then 'passed' else 'failed' end,'Final Recovery write-off closes the receivable.');
retry:=public.writeoff_debt_event(c.household_id,debt_id,now(),40,'Partial debt writeoff','test','00000000-0000-4000-8000-000000001002');
insert into writeoff_results values('idempotence',case when retry is not null and (select count(*) from public.obligation_adjustments where financial_event_id=retry)=1 then 'passed' else 'failed' end,'Retry does not duplicate an adjustment.');
rejected:=false; count_before:=(select count(*) from public.financial_events where household_id=c.household_id); begin perform public.writeoff_income_receivable_event(c.household_id,income_id,now(),1,'Over','test','00000000-0000-4000-8000-000000001011'); exception when others then rejected:=true; end;
insert into writeoff_results values('over_remaining_rejected',case when rejected then 'passed' else 'failed' end,'Write-off above remaining is rejected.');
insert into writeoff_results values('rollback',case when (select count(*) from public.financial_events where household_id=c.household_id)=count_before then 'passed' else 'failed' end,'Rejected write-off leaves no event.');
rejected:=false; begin perform public.writeoff_debt_event(c.household_id,debt_id,now(),0,'Zero','test','00000000-0000-4000-8000-000000001012'); exception when others then rejected:=true; end;
insert into writeoff_results values('zero_rejected',case when rejected then 'passed' else 'failed' end,'A zero write-off is rejected.');
insert into writeoff_results values('no_reversal_rpc',case when not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='reverse_recovery_event') then 'passed' else 'failed' end,'Phase 1 exposes no Recovery reversal RPC.');
end $$;
select count(*) total,count(*) filter(where status='passed') passed,count(*) filter(where status='failed') failed,count(*) filter(where status='skipped') skipped,jsonb_agg(jsonb_build_object('test',test_name,'status',status,'detail',detail) order by test_name) details from writeoff_results;
reset role; reset "request.jwt.claims"; rollback;
