-- F3.1: complete compensation workflow and reversible reconciliation adjustments.
begin;

create or replace view public.member_compensation_balances with (security_invoker=true) as
select c.*,
 coalesce(sum(a.amount) filter(where a.action_kind='receipt_confirmed'),0)::numeric(14,2) received_amount,
 coalesce(sum(a.amount) filter(where a.action_kind='abandoned'),0)::numeric(14,2) abandoned_amount,
 greatest(c.initial_amount-coalesce(sum(a.amount) filter(where a.action_kind in ('receipt_confirmed','abandoned')),0),0)::numeric(14,2) remaining_amount,
 case when coalesce(sum(a.amount) filter(where a.action_kind in ('receipt_confirmed','abandoned')),0)>=c.initial_amount then
   case when coalesce(sum(a.amount) filter(where a.action_kind='abandoned'),0)>0 then 'abandoned' else 'settled' end
   when coalesce(sum(a.amount) filter(where a.action_kind='transfer_declared'),0)>coalesce(sum(a.amount) filter(where a.action_kind='receipt_confirmed'),0) then 'transfer_sent'
   else 'to_pay' end status,
 coalesce(sum(a.amount) filter(where a.action_kind='transfer_declared'),0)::numeric(14,2) declared_amount,
 greatest(coalesce(sum(a.amount) filter(where a.action_kind='transfer_declared'),0)-coalesce(sum(a.amount) filter(where a.action_kind='receipt_confirmed'),0),0)::numeric(14,2) pending_receipt
from public.member_compensations c left join public.member_compensation_actions a on a.compensation_id=c.id
group by c.id;
grant select on public.member_compensation_balances to authenticated;

create or replace function public.create_member_compensation(
 p_household_id uuid,p_source_event_id uuid,p_debtor_user_id uuid,p_creditor_user_id uuid,
 p_amount numeric,p_reason text,p_envelope_id uuid,p_actual_account_id uuid,p_recommended_account_id uuid,
 p_actual_payment_method_id uuid,p_recommended_payment_method_id uuid,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_source_amount numeric;
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 if p_amount<=0 or p_debtor_user_id=p_creditor_user_id then raise exception 'Invalid compensation parties or amount'; end if;
 if not exists(select 1 from public.household_members where household_id=p_household_id and user_id=p_debtor_user_id)
 or not exists(select 1 from public.household_members where household_id=p_household_id and user_id=p_creditor_user_id) then raise exception 'Compensation parties must be household members'; end if;
 select t.amount into v_source_amount from public.financial_events e join public.financial_transactions t on t.event_id=e.id
 where e.id=p_source_event_id and e.household_id=p_household_id and e.event_type='cash_expense';
 if v_source_amount is null or p_amount>v_source_amount then raise exception 'Compensation exceeds source expense'; end if;
 if p_envelope_id is not null and not exists(select 1 from public.envelopes where id=p_envelope_id and household_id=p_household_id) then raise exception 'Envelope access denied'; end if;
 if p_actual_account_id is not null and not exists(select 1 from public.accounts where id=p_actual_account_id and household_id=p_household_id and archived_at is null) then raise exception 'Actual account access denied'; end if;
 if p_recommended_account_id is not null and not exists(select 1 from public.accounts where id=p_recommended_account_id and household_id=p_household_id and archived_at is null) then raise exception 'Recommended account access denied'; end if;
 insert into public.member_compensations(household_id,source_financial_event_id,debtor_user_id,creditor_user_id,initial_amount,envelope_id,actual_account_id,recommended_account_id,actual_payment_method_id,recommended_payment_method_id,reason,idempotency_key,created_by)
 values(p_household_id,p_source_event_id,p_debtor_user_id,p_creditor_user_id,p_amount,p_envelope_id,p_actual_account_id,p_recommended_account_id,p_actual_payment_method_id,p_recommended_payment_method_id,trim(p_reason),p_idempotency_key,auth.uid())
 on conflict(household_id,idempotency_key) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.member_compensations where household_id=p_household_id and idempotency_key=p_idempotency_key; end if;
 return v_id;
end $$;

create or replace function public.record_member_compensation_action(
 p_compensation_id uuid,p_action_kind text,p_amount numeric,p_transfer_event_id uuid,p_reason text,p_allocations jsonb,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_c public.member_compensation_balances%rowtype; v_id uuid; v_sum numeric; v_item jsonb;
begin
 perform 1 from public.member_compensations where id=p_compensation_id for update;
 select * into v_c from public.member_compensation_balances where id=p_compensation_id;
 if auth.uid() is null or v_c.id is null or not public.is_household_member(v_c.household_id) then raise exception 'Compensation access denied'; end if;
 if p_action_kind not in ('transfer_declared','receipt_confirmed','abandoned') or p_amount<=0 or p_amount>v_c.remaining_amount then raise exception 'Invalid action or amount'; end if;
 if p_action_kind='transfer_declared' and auth.uid()<>v_c.debtor_user_id then raise exception 'Only debtor can declare transfer'; end if;
 if p_action_kind in ('receipt_confirmed','abandoned') and auth.uid()<>v_c.creditor_user_id then raise exception 'Only creditor can confirm or abandon'; end if;
 if p_action_kind='receipt_confirmed' and p_amount>v_c.pending_receipt then raise exception 'Receipt exceeds declared transfers'; end if;
 if p_action_kind='transfer_declared' and p_transfer_event_id is not null and not exists(
   select 1 from public.financial_events e join public.financial_transactions t on t.event_id=e.id
   where e.id=p_transfer_event_id and e.household_id=v_c.household_id and e.event_type='account_transfer' and t.amount=p_amount
 ) then raise exception 'Transfer event is incompatible'; end if;
 if p_action_kind<>'transfer_declared' and p_transfer_event_id is not null then raise exception 'Transfer event only belongs to transfer declaration'; end if;
 if p_action_kind='abandoned' then
   select coalesce(sum((value->>'amount')::numeric),0) into v_sum from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb));
   if jsonb_array_length(coalesce(p_allocations,'[]'::jsonb))>0 and round(v_sum,2)<>round(p_amount,2) then raise exception 'Abandonment allocations must equal amount'; end if;
 end if;
 insert into public.member_compensation_actions(household_id,compensation_id,action_kind,amount,transfer_financial_event_id,reason,idempotency_key,created_by)
 values(v_c.household_id,v_c.id,p_action_kind,p_amount,p_transfer_event_id,trim(p_reason),p_idempotency_key,auth.uid())
 on conflict(household_id,idempotency_key) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.member_compensation_actions where household_id=v_c.household_id and idempotency_key=p_idempotency_key; return v_id; end if;
 if p_action_kind='abandoned' then for v_item in select value from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) loop
   if not exists(select 1 from public.envelopes where id=(v_item->>'envelope_id')::uuid and household_id=v_c.household_id and archived_at is null) then raise exception 'Allocation envelope access denied'; end if;
   insert into public.member_compensation_allocations(household_id,action_id,envelope_id,amount) values(v_c.household_id,v_id,(v_item->>'envelope_id')::uuid,(v_item->>'amount')::numeric);
 end loop; end if;
 return v_id;
end $$;

create or replace function public.reverse_reconciliation_regularization(p_original_event_id uuid,p_occurred_at timestamptz,p_reason text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_e public.financial_events%rowtype; v_t public.financial_transactions%rowtype; v_event uuid; v_tx uuid; v_resolution public.account_reconciliation_resolutions%rowtype; v_group uuid:=gen_random_uuid();
begin
 select * into v_e from public.financial_events where id=p_original_event_id for update;
 if auth.uid() is null or v_e.id is null or not public.is_household_member(v_e.household_id) then raise exception 'FinancialEvent access denied'; end if;
 if v_e.event_type<>'reconciliation_adjustment' then raise exception 'Only reconciliation adjustment can be reversed here'; end if;
 select * into v_resolution from public.account_reconciliation_resolutions where financial_event_id=v_e.id and resolution_kind='regularization';
 if v_resolution.id is null then raise exception 'Regularization resolution not found'; end if;
 if exists(select 1 from public.account_reconciliation_resolutions where reversal_of_resolution_id=v_resolution.id) then
   select financial_event_id into v_event from public.account_reconciliation_resolutions where reversal_of_resolution_id=v_resolution.id;
   if exists(select 1 from public.financial_events where id=v_event and idempotency_key=p_idempotency_key) then return v_event; end if;
   raise exception 'Regularization already reversed';
 end if;
 v_event:=public.create_or_get_financial_event(v_e.household_id,'daily_reversal',coalesce(p_occurred_at,now()),'Contrepassation régularisation',trim(p_reason),p_idempotency_key);
 select * into v_t from public.financial_transactions where event_id=v_e.id;
 insert into public.financial_transactions(household_id,event_id,type,occurred_at,reason,description,amount,currency_code,source_account_id,destination_account_id,notes,created_by,validated_at)
 values(v_e.household_id,v_event,'reversal',coalesce(p_occurred_at,now()),trim(p_reason),'Contrepassation régularisation',v_t.amount,coalesce(v_t.currency_code,'MAD'),v_t.destination_account_id,v_t.source_account_id,trim(p_reason),auth.uid(),now()) returning id into v_tx;
 insert into public.financial_transaction_lines(transaction_id,account_id,envelope_id,member_id,amount,debit,credit,occurred_at)
 select v_tx,account_id,envelope_id,member_id,-amount,credit,debit,coalesce(p_occurred_at,now()) from public.financial_transaction_lines where transaction_id=v_t.id;
 insert into public.envelope_movements(household_id,event_id,envelope_id,financial_transaction_id,movement_group_id,movement_type,direction,amount,occurred_at,description,reversal_of,created_by)
 select v_e.household_id,v_event,envelope_id,v_tx,v_group,'reversal',case direction when 'inflow' then 'outflow' else 'inflow' end,amount,coalesce(p_occurred_at,now()),'Contrepassation — '||description,id,auth.uid() from public.envelope_movements where event_id=v_e.id;
 insert into public.daily_operation_reversals(household_id,original_event_id,reversal_event_id,reason_code,reason,created_by) values(v_e.household_id,v_e.id,v_event,'other',trim(p_reason),auth.uid());
 insert into public.account_reconciliation_resolutions(household_id,observation_id,account_id,resolution_kind,effective_amount,comment,financial_event_id,reversal_of_resolution_id,idempotency_key,created_by)
 values(v_resolution.household_id,v_resolution.observation_id,v_resolution.account_id,'reversal',-v_resolution.effective_amount,trim(p_reason),v_event,v_resolution.id,p_idempotency_key::text,auth.uid());
 return v_event;
end $$;

revoke all on function public.create_member_compensation(uuid,uuid,uuid,uuid,numeric,text,uuid,uuid,uuid,uuid,uuid,uuid), public.record_member_compensation_action(uuid,text,numeric,uuid,text,jsonb,uuid), public.reverse_reconciliation_regularization(uuid,timestamptz,text,uuid) from public,anon;
grant execute on function public.create_member_compensation(uuid,uuid,uuid,uuid,numeric,text,uuid,uuid,uuid,uuid,uuid,uuid), public.record_member_compensation_action(uuid,text,numeric,uuid,text,jsonb,uuid), public.reverse_reconciliation_regularization(uuid,timestamptz,text,uuid) to authenticated;

commit;
