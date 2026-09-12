-- Transactional Phase 1 receipt.  Every fixture and assertion is rolled back.
begin;

create temp table reversal_context on commit drop as
select hm.household_id, hm.user_id as actor_id,
  (select id from public.accounts a where a.household_id=hm.household_id and not a.is_system order by id limit 1) as account_id,
  (select id from public.envelopes e where e.household_id=hm.household_id and not e.is_system and e.archived_at is null order by id limit 1) as envelope_a_id,
  (select id from public.envelopes e where e.household_id=hm.household_id and not e.is_system and e.archived_at is null order by id offset 1 limit 1) as envelope_b_id
from public.household_members hm order by hm.household_id,hm.user_id limit 1;

do $$ declare c reversal_context%rowtype; begin
  select * into c from reversal_context;
  if c.actor_id is null or c.account_id is null or c.envelope_a_id is null or c.envelope_b_id is null then
    raise exception 'Settlement reversal receipt requires actor, ordinary account and two envelopes';
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',c.actor_id::text)::text,true);
end $$;
grant select on reversal_context to authenticated;
set local role authenticated;

create temp table reversal_results(test_name text primary key,status text not null,detail text not null) on commit drop;

do $$
declare
  c reversal_context%rowtype; debt_event uuid; debt_id uuid; debt_settlement uuid; debt_reversal_1 uuid; debt_reversal_2 uuid; debt_reversal_3 uuid;
  income_event uuid; income_id uuid; income_settlement uuid; income_reversal_1 uuid; income_reversal_2 uuid; income_reversal_3 uuid;
  recovery_source uuid; recovery_event uuid; recovery_id uuid; recovery_settlement uuid; recovery_reversal uuid; recovery_reversal_2 uuid;
  food_movement uuid; savings_movement uuid; to_allocate_movement uuid; rejected boolean; before_events bigint; retry uuid;
begin
  select * into c from reversal_context;

  -- Debt: 100 settled, then 20 + 30 reversed, then final 50.
  debt_event:=public.create_debt_expense_event(c.household_id,now(),'TEST_REV_DEBT',100,jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_a_id,'amount',100)),'Creditor',null,'receipt','00000000-0000-4000-8000-000000009101');
  select id into debt_id from public.obligations where origin_event_id=debt_event;
  debt_settlement:=public.settle_debt_event(c.household_id,debt_id,now(),'TEST_REV_DEBT_SETTLE',100,c.account_id,'receipt','00000000-0000-4000-8000-000000009102');
  select id into debt_settlement from public.obligation_settlements where event_id=debt_settlement;
  debt_reversal_1:=public.reverse_debt_settlement_event(c.household_id,debt_settlement,now(),20,'Erreur de montant','receipt','00000000-0000-4000-8000-000000009103');
  insert into reversal_results values('debt_partial_20',case when (select remaining_amount from public.obligation_balances where obligation_id=debt_id)=20 then 'passed' else 'failed' end,'Partial debt reversal reopens 20.');
  debt_reversal_2:=public.reverse_debt_settlement_event(c.household_id,debt_settlement,now(),30,'Saisie erronée','receipt','00000000-0000-4000-8000-000000009104');
  insert into reversal_results values('debt_second_partial_30',case when (select settlement_reversed_amount from public.obligation_balances where obligation_id=debt_id)=50 then 'passed' else 'failed' end,'Cumulative debt reversals total 50.');
  insert into reversal_results values('debt_gl_and_account',case when (select count(*) from public.financial_transactions where event_id in(debt_reversal_1,debt_reversal_2))=2 and not exists(select 1 from public.envelope_movements where event_id in(debt_reversal_1,debt_reversal_2)) then 'passed' else 'failed' end,'Debt reversals use GL only and no envelope movement.');
  rejected:=false; before_events:=(select count(*) from public.financial_events where household_id=c.household_id); begin perform public.reverse_debt_settlement_event(c.household_id,debt_settlement,now(),51,'Over','receipt','00000000-0000-4000-8000-000000009105'); exception when others then rejected:=true; end;
  insert into reversal_results values('debt_over_reversible_rejected',case when rejected then 'passed' else 'failed' end,'Amount above remaining reversible is refused.');
  insert into reversal_results values('debt_rejection_rollback',case when (select count(*) from public.financial_events where household_id=c.household_id)=before_events then 'passed' else 'failed' end,'Rejected debt reversal leaves no event.');
  retry:=public.reverse_debt_settlement_event(c.household_id,debt_settlement,now(),20,'Erreur de montant','receipt','00000000-0000-4000-8000-000000009103');
  insert into reversal_results values('debt_idempotence',case when retry=debt_reversal_1 and (select count(*) from public.obligation_settlement_reversals where financial_event_id=debt_reversal_1)=1 then 'passed' else 'failed' end,'Same key returns the original reversal only.');
  debt_reversal_3:=public.reverse_debt_settlement_event(c.household_id,debt_settlement,now(),50,'Annulation totale','receipt','00000000-0000-4000-8000-000000009106');
  insert into reversal_results values('debt_total_reversal',case when (select remaining_amount from public.obligation_balances where obligation_id=debt_id)=100 then 'passed' else 'failed' end,'Final reversal reopens all 100.');
  insert into reversal_results values('debt_gl_real_sides_and_net_zero',case when
    (select coalesce(sum(l.credit),0) from public.financial_transaction_lines l join public.obligation_settlements s on s.financial_transaction_id=l.transaction_id where s.id=debt_settlement and l.account_id=c.account_id)=100
    and (select coalesce(sum(l.debit),0) from public.financial_transaction_lines l join public.obligation_settlements s on s.financial_transaction_id=l.transaction_id where s.id=debt_settlement and l.account_id<>c.account_id)=100
    and not exists(select 1 from public.obligation_settlement_reversals r where r.financial_event_id in(debt_reversal_1,debt_reversal_2,debt_reversal_3) and ((select coalesce(sum(l.debit),0) from public.financial_transaction_lines l where l.transaction_id=r.financial_transaction_id and l.account_id=c.account_id)<>r.amount or (select coalesce(sum(l.credit),0) from public.financial_transaction_lines l where l.transaction_id=r.financial_transaction_id and l.account_id<>c.account_id)<>r.amount))
    and (select coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0) from public.financial_transaction_lines l where l.transaction_id in(select financial_transaction_id from public.obligation_settlements where id=debt_settlement union select financial_transaction_id from public.obligation_settlement_reversals where financial_event_id in(debt_reversal_1,debt_reversal_2,debt_reversal_3)) and l.account_id=c.account_id)=0
    then 'passed' else 'failed' end,'Debt settlement credits cash; every reversal debits cash and the total net cash position is zero.');

  -- Income: settlement 50 -> A20, B10 and system remainder20; explicit partial reversals.
  income_event:=public.create_income_receivable_event(c.household_id,now(),'TEST_REV_INCOME',50,'Debtor',null,'receipt','00000000-0000-4000-8000-000000009201');
  select id into income_id from public.obligations where origin_event_id=income_event;
  income_settlement:=public.settle_receivable_event(c.household_id,income_id,now(),'TEST_REV_INCOME_SETTLE',50,c.account_id,'receipt','00000000-0000-4000-8000-000000009202',jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_a_id,'amount',20),jsonb_build_object('envelope_id',c.envelope_b_id,'amount',10)));
  select id into income_settlement from public.obligation_settlements where event_id=income_settlement;
  select id into food_movement from public.envelope_movements where event_id=(select event_id from public.obligation_settlements where id=income_settlement) and envelope_id=c.envelope_a_id;
  select id into savings_movement from public.envelope_movements where event_id=(select event_id from public.obligation_settlements where id=income_settlement) and envelope_id=c.envelope_b_id;
  select m.id into to_allocate_movement from public.envelope_movements m join public.envelopes e on e.id=m.envelope_id where m.event_id=(select event_id from public.obligation_settlements where id=income_settlement) and e.system_code='to_allocate';
  income_reversal_1:=public.reverse_income_receivable_settlement_event(c.household_id,income_settlement,now(),10,'Erreur Nourriture',jsonb_build_array(jsonb_build_object('source_movement_id',food_movement,'amount',10)),'receipt','00000000-0000-4000-8000-000000009203');
  insert into reversal_results values('income_partial_source_envelope',case when (select remaining_amount from public.obligation_balances where obligation_id=income_id)=10 then 'passed' else 'failed' end,'Explicit 10 reversal reopens the income receivable.');
  income_reversal_2:=public.reverse_income_receivable_settlement_event(c.household_id,income_settlement,now(),10,'Erreur À répartir',jsonb_build_array(jsonb_build_object('source_movement_id',to_allocate_movement,'amount',10)),'receipt','00000000-0000-4000-8000-000000009204');
  insert into reversal_results values('income_partial_to_allocate',case when (select count(*) from public.envelope_movements where event_id=income_reversal_2 and reversal_of=to_allocate_movement)=1 then 'passed' else 'failed' end,'À répartir is counter-posted only when explicitly selected.');
  insert into reversal_results values('income_no_new_revenue',case when not exists(select 1 from public.financial_events where id in(income_reversal_1,income_reversal_2) and event_type='cash_income') then 'passed' else 'failed' end,'Income reversal never recognizes new revenue.');
  rejected:=false; before_events:=(select count(*) from public.financial_events where household_id=c.household_id); begin perform public.reverse_income_receivable_settlement_event(c.household_id,income_settlement,now(),5,'Invalid',jsonb_build_array(jsonb_build_object('source_movement_id',food_movement,'amount',4)),'receipt','00000000-0000-4000-8000-000000009205'); exception when others then rejected:=true; end;
  insert into reversal_results values('income_split_mismatch_rejected',case when rejected then 'passed' else 'failed' end,'Envelope split must equal reversal amount.');
  insert into reversal_results values('income_rejection_rollback',case when (select count(*) from public.financial_events where household_id=c.household_id)=before_events then 'passed' else 'failed' end,'Rejected income reversal leaves no event.');
  rejected:=false; begin perform public.reverse_income_receivable_settlement_event(c.household_id,income_settlement,now(),11,'Foreign source',jsonb_build_array(jsonb_build_object('source_movement_id',food_movement,'amount',11)),'receipt','00000000-0000-4000-8000-000000009206'); exception when others then rejected:=true; end;
  insert into reversal_results values('income_cumulative_movement_limit',case when rejected then 'passed' else 'failed' end,'A movement cannot be reversed above its source total.');
  income_reversal_3:=public.reverse_income_receivable_settlement_event(c.household_id,income_settlement,now(),30,'Annulation totale',jsonb_build_array(jsonb_build_object('source_movement_id',food_movement,'amount',10),jsonb_build_object('source_movement_id',savings_movement,'amount',10),jsonb_build_object('source_movement_id',to_allocate_movement,'amount',10)),'receipt','00000000-0000-4000-8000-000000009207');
  insert into reversal_results values('income_gl_real_sides_and_net_zero',case when
    (select coalesce(sum(l.debit),0) from public.financial_transaction_lines l join public.obligation_settlements s on s.financial_transaction_id=l.transaction_id where s.id=income_settlement and l.account_id=c.account_id)=50
    and not exists(select 1 from public.obligation_settlement_reversals r where r.financial_event_id in(income_reversal_1,income_reversal_2,income_reversal_3) and ((select coalesce(sum(l.credit),0) from public.financial_transaction_lines l where l.transaction_id=r.financial_transaction_id and l.account_id=c.account_id)<>r.amount or (select coalesce(sum(l.debit),0) from public.financial_transaction_lines l where l.transaction_id=r.financial_transaction_id and l.account_id<>c.account_id)<>r.amount))
    and (select coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0) from public.financial_transaction_lines l where l.transaction_id in(select financial_transaction_id from public.obligation_settlements where id=income_settlement union select financial_transaction_id from public.obligation_settlement_reversals where financial_event_id in(income_reversal_1,income_reversal_2,income_reversal_3)) and l.account_id=c.account_id)=0
    then 'passed' else 'failed' end,'Income settlement debits cash; every reversal credits cash and the total net cash position is zero.');

  -- Recovery: settlement 20 / refund 20, then reversal 10; no To Allocate and cap remains 60.
  recovery_source:=public.create_cash_expense_event(c.household_id,now(),'TEST_REV_RECOVERY_SOURCE',60,c.account_id,jsonb_build_array(jsonb_build_object('envelope_id',c.envelope_a_id,'amount',60)),'receipt','00000000-0000-4000-8000-000000009301');
  recovery_event:=public.create_recovery_receivable_event(c.household_id,recovery_source,c.envelope_a_id,now(),'TEST_REV_RECOVERY',60,'Debtor',null,'receipt','00000000-0000-4000-8000-000000009302');
  select id into recovery_id from public.obligations where origin_event_id=recovery_event;
  recovery_settlement:=public.settle_recovery_event(c.household_id,recovery_id,now(),'TEST_REV_RECOVERY_SETTLE',20,c.account_id,true,'receipt','00000000-0000-4000-8000-000000009303');
  select id into recovery_settlement from public.obligation_settlements where event_id=recovery_settlement;
  recovery_reversal:=public.reverse_recovery_settlement_event(c.household_id,recovery_settlement,now(),10,'Erreur recovery','receipt','00000000-0000-4000-8000-000000009304');
  insert into reversal_results values('recovery_partial_refund_reversed',case when (select remaining_amount from public.obligation_balances where obligation_id=recovery_id)=50 and (select count(*) from public.envelope_movements where event_id=recovery_reversal and movement_type='reversal' and direction='outflow')=1 then 'passed' else 'failed' end,'Recovery reversal debits the exact linked refund.');
  insert into reversal_results values('recovery_no_to_allocate_and_cap_unchanged',case when not exists(select 1 from public.envelope_movements m join public.envelopes e on e.id=m.envelope_id where m.event_id=recovery_reversal and e.system_code='to_allocate') and (select sum(initial_amount) from public.obligations where recovery_source_event_id=recovery_source)=60 then 'passed' else 'failed' end,'Recovery reversal leaves To Allocate and the cumulative cap unchanged.');
  rejected:=false; begin perform public.reverse_recovery_settlement_event(c.household_id,recovery_settlement,now(),11,'Over recovery','receipt','00000000-0000-4000-8000-000000009305'); exception when others then rejected:=true; end;
  insert into reversal_results values('recovery_over_reversible_rejected',case when rejected then 'passed' else 'failed' end,'Recovery reversal cannot exceed its settlement.');
  recovery_reversal_2:=public.reverse_recovery_settlement_event(c.household_id,recovery_settlement,now(),10,'Annulation totale recovery','receipt','00000000-0000-4000-8000-000000009306');
  insert into reversal_results values('recovery_gl_and_envelope_real_sides_net_zero',case when
    (select coalesce(sum(l.debit),0) from public.financial_transaction_lines l join public.obligation_settlements s on s.financial_transaction_id=l.transaction_id where s.id=recovery_settlement and l.account_id=c.account_id)=20
    and not exists(select 1 from public.obligation_settlement_reversals r where r.financial_event_id in(recovery_reversal,recovery_reversal_2) and ((select coalesce(sum(l.credit),0) from public.financial_transaction_lines l where l.transaction_id=r.financial_transaction_id and l.account_id=c.account_id)<>r.amount or (select coalesce(sum(l.debit),0) from public.financial_transaction_lines l where l.transaction_id=r.financial_transaction_id and l.account_id<>c.account_id)<>r.amount))
    and (select coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0) from public.financial_transaction_lines l where l.transaction_id in(select financial_transaction_id from public.obligation_settlements where id=recovery_settlement union select financial_transaction_id from public.obligation_settlement_reversals where financial_event_id in(recovery_reversal,recovery_reversal_2)) and l.account_id=c.account_id)=0
    and (select coalesce(sum(case when direction='inflow' then amount else -amount end),0) from public.envelope_movements where event_id in(select event_id from public.obligation_settlements where id=recovery_settlement union select recovery_reversal union select recovery_reversal_2))=0
    then 'passed' else 'failed' end,'Recovery reversal credits cash, debits receivable, and fully reverses the source-envelope refund.');

  -- Cross-household denial is exercised without creating a second durable fixture.
  rejected:=false; begin perform public.reverse_debt_settlement_event(gen_random_uuid(),debt_settlement,now(),1,'Other household','receipt','00000000-0000-4000-8000-000000009401'); exception when others then rejected:=true; end;
  insert into reversal_results values('other_household_rejected',case when rejected then 'passed' else 'failed' end,'A member cannot reverse a settlement through another household id.');
  insert into reversal_results values(
    'concurrency_lock_present',
    case when position(
      'for update of s,o' in lower(pg_get_functiondef(
        'public.reverse_obligation_settlement_event(uuid,uuid,timestamptz,numeric,text,text,uuid,text,jsonb)'::regprocedure
      ))
    ) > 0 then 'passed' else 'failed' end,
    'La RPC canonique verrouille le settlement source et l''obligation avant de calculer le restant reversible.'
  );
  insert into reversal_results values('atomicity_and_immutability',case when not exists(select 1 from public.obligation_settlements s where s.id=debt_settlement and s.amount<>100) and not exists(select 1 from public.financial_transactions t where t.event_id=debt_event and t.reversed_by is not null) then 'passed' else 'failed' end,'Source settlement and original transaction remain immutable.');
end $$;

select count(*) total,count(*) filter(where status='passed') passed,count(*) filter(where status='failed') failed,count(*) filter(where status='skipped') skipped,jsonb_agg(jsonb_build_object('test',test_name,'status',status,'detail',detail) order by test_name) details from reversal_results;
reset role; reset "request.jwt.claims"; rollback;
