-- F3: internal member compensations and canonical reconciliation adjustments.
begin;

alter table public.households add column if not exists compensation_policy text not null default 'propose'
  check (compensation_policy in ('propose','automatic_unambiguous','never'));

alter table public.financial_events drop constraint if exists financial_events_event_type_check;
alter table public.financial_events add constraint financial_events_event_type_check check (event_type in (
  'cash_expense','cash_income','debt_expense','debt_settlement','income_receivable',
  'receivable_settlement','recovery_receivable','recovery_settlement','budget_allocation',
  'account_transfer','envelope_transfer','debt_writeoff','income_receivable_writeoff',
  'recovery_writeoff','recovery_reversal','debt_settlement_reversal',
  'receivable_settlement_reversal','recovery_settlement_reversal','debt_writeoff_reversal',
  'income_receivable_writeoff_reversal','recovery_writeoff_reversal','account_opening',
  'envelope_opening','obligation_opening','daily_reversal','reconciliation_adjustment'
));

create table public.member_compensations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id),
  source_financial_event_id uuid not null references public.financial_events(id),
  debtor_user_id uuid not null references auth.users(id),
  creditor_user_id uuid not null references auth.users(id),
  initial_amount numeric(14,2) not null check (initial_amount > 0),
  currency_code text not null default 'MAD' check (currency_code='MAD'),
  envelope_id uuid references public.envelopes(id),
  actual_account_id uuid references public.accounts(id),
  recommended_account_id uuid references public.accounts(id),
  actual_payment_method_id uuid references public.payment_methods(id),
  recommended_payment_method_id uuid references public.payment_methods(id),
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  idempotency_key uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (debtor_user_id<>creditor_user_id),
  unique(household_id,idempotency_key),
  unique(source_financial_event_id,debtor_user_id,creditor_user_id)
);
create table public.member_compensation_actions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id),
  compensation_id uuid not null references public.member_compensations(id),
  action_kind text not null check (action_kind in ('transfer_declared','receipt_confirmed','abandoned')),
  amount numeric(14,2) not null check (amount>0),
  transfer_financial_event_id uuid references public.financial_events(id),
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  idempotency_key uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(household_id,idempotency_key),
  unique(transfer_financial_event_id)
);
create table public.member_compensation_allocations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id),
  action_id uuid not null references public.member_compensation_actions(id),
  envelope_id uuid not null references public.envelopes(id),
  amount numeric(14,2) not null check(amount>0),
  unique(action_id,envelope_id)
);
create index member_compensations_household_idx on public.member_compensations(household_id,created_at desc);
create index member_compensation_actions_parent_idx on public.member_compensation_actions(compensation_id,created_at);

alter table public.member_compensations enable row level security;
alter table public.member_compensation_actions enable row level security;
alter table public.member_compensation_allocations enable row level security;
revoke all on public.member_compensations,public.member_compensation_actions,public.member_compensation_allocations from public,anon;
grant select on public.member_compensations,public.member_compensation_actions,public.member_compensation_allocations to authenticated;
create policy member_compensations_read on public.member_compensations for select to authenticated
  using(public.is_household_member(household_id));
create policy member_compensation_actions_read on public.member_compensation_actions for select to authenticated
  using(public.is_household_member(household_id));
create policy member_compensation_allocations_read on public.member_compensation_allocations for select to authenticated
  using(public.is_household_member(household_id));
create trigger member_compensations_immutable before update or delete on public.member_compensations
  for each row execute function public.prevent_financial_event_mutation();
create trigger member_compensation_actions_immutable before update or delete on public.member_compensation_actions
  for each row execute function public.prevent_financial_event_mutation();
create trigger member_compensation_allocations_immutable before update or delete on public.member_compensation_allocations
  for each row execute function public.prevent_financial_event_mutation();

create or replace view public.member_compensation_balances with (security_invoker=true) as
select c.*,
 coalesce(sum(a.amount) filter(where a.action_kind='receipt_confirmed'),0)::numeric(14,2) received_amount,
 coalesce(sum(a.amount) filter(where a.action_kind='abandoned'),0)::numeric(14,2) abandoned_amount,
 greatest(c.initial_amount-coalesce(sum(a.amount) filter(where a.action_kind in ('receipt_confirmed','abandoned')),0),0)::numeric(14,2) remaining_amount,
 case when coalesce(sum(a.amount) filter(where a.action_kind in ('receipt_confirmed','abandoned')),0)>=c.initial_amount then
   case when coalesce(sum(a.amount) filter(where a.action_kind='abandoned'),0)>0 then 'abandoned' else 'settled' end
   when coalesce(sum(a.amount) filter(where a.action_kind='transfer_declared'),0)>coalesce(sum(a.amount) filter(where a.action_kind='receipt_confirmed'),0) then 'transfer_sent'
   else 'to_pay' end status
from public.member_compensations c left join public.member_compensation_actions a on a.compensation_id=c.id
group by c.id;
grant select on public.member_compensation_balances to authenticated;

create or replace function public.create_member_compensation(
 p_household_id uuid,p_source_event_id uuid,p_debtor_user_id uuid,p_creditor_user_id uuid,
 p_amount numeric,p_reason text,p_envelope_id uuid,p_actual_account_id uuid,p_recommended_account_id uuid,
 p_actual_payment_method_id uuid,p_recommended_payment_method_id uuid,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 if p_amount<=0 or p_debtor_user_id=p_creditor_user_id then raise exception 'Invalid compensation parties or amount'; end if;
 if not exists(select 1 from public.household_members where household_id=p_household_id and user_id=p_debtor_user_id)
 or not exists(select 1 from public.household_members where household_id=p_household_id and user_id=p_creditor_user_id) then raise exception 'Compensation parties must be household members'; end if;
 if not exists(select 1 from public.financial_events where id=p_source_event_id and household_id=p_household_id and event_type='cash_expense') then raise exception 'Compensation source must be a household cash expense'; end if;
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
 if p_transfer_event_id is not null and not exists(select 1 from public.financial_events where id=p_transfer_event_id and household_id=v_c.household_id and event_type='account_transfer') then raise exception 'Transfer event is incompatible'; end if;
 if p_action_kind='abandoned' then
   select coalesce(sum((value->>'amount')::numeric),0) into v_sum from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb));
   if jsonb_array_length(coalesce(p_allocations,'[]'::jsonb))>0 and v_sum<>p_amount then raise exception 'Abandonment allocations must equal amount'; end if;
 end if;
 insert into public.member_compensation_actions(household_id,compensation_id,action_kind,amount,transfer_financial_event_id,reason,idempotency_key,created_by)
 values(v_c.household_id,v_c.id,p_action_kind,p_amount,p_transfer_event_id,trim(p_reason),p_idempotency_key,auth.uid())
 on conflict(household_id,idempotency_key) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.member_compensation_actions where household_id=v_c.household_id and idempotency_key=p_idempotency_key; return v_id; end if;
 if p_action_kind='abandoned' then
  for v_item in select value from jsonb_array_elements(p_allocations) loop
   if not exists(select 1 from public.envelopes where id=(v_item->>'envelope_id')::uuid and household_id=v_c.household_id and archived_at is null) then raise exception 'Allocation envelope access denied'; end if;
   insert into public.member_compensation_allocations(household_id,action_id,envelope_id,amount) values(v_c.household_id,v_id,(v_item->>'envelope_id')::uuid,(v_item->>'amount')::numeric);
  end loop;
 end if;
 return v_id;
end $$;

alter table public.account_reconciliation_resolutions drop constraint if exists account_reconciliation_resolutions_kind_source_check;
alter table public.account_reconciliation_resolutions drop constraint if exists account_reconciliation_resolutions_resolution_kind_check;
alter table public.account_reconciliation_resolutions drop constraint if exists account_reconciliation_resolutions_check;
alter table public.account_reconciliation_resolutions add constraint account_reconciliation_resolutions_resolution_kind_check
 check(resolution_kind in ('documentary','temporary','financial_event','follow_up','reversal','regularization'));
alter table public.account_reconciliation_resolutions add constraint account_reconciliation_resolutions_kind_source_check check(
 (resolution_kind in ('financial_event','regularization') and financial_event_id is not null and follow_up_observation_id is null)
 or (resolution_kind='follow_up' and financial_event_id is null and follow_up_observation_id is not null)
 or (resolution_kind in ('documentary','temporary') and financial_event_id is null and follow_up_observation_id is null)
 or (resolution_kind='reversal' and reversal_of_resolution_id is not null));

create table public.reconciliation_regularization_allocations(
 id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households(id),
 resolution_id uuid not null references public.account_reconciliation_resolutions(id), envelope_id uuid not null references public.envelopes(id),
 direction text not null check(direction in ('inflow','outflow')), amount numeric(14,2) not null check(amount>0), unique(resolution_id,envelope_id));
alter table public.reconciliation_regularization_allocations enable row level security;
revoke all on public.reconciliation_regularization_allocations from public,anon; grant select on public.reconciliation_regularization_allocations to authenticated;
create policy reconciliation_regularization_allocations_read on public.reconciliation_regularization_allocations for select to authenticated using(public.is_household_member(household_id));
create trigger reconciliation_regularization_allocations_immutable before update or delete on public.reconciliation_regularization_allocations for each row execute function public.prevent_financial_event_mutation();

create or replace function public.regularize_account_reconciliation(
 p_observation_id uuid,p_amount numeric,p_reason_code text,p_reason text,p_envelope_allocations jsonb,p_occurred_at timestamptz,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_o public.account_balance_observations%rowtype; v_remaining numeric; v_signed numeric; v_event uuid; v_tx uuid; v_adjustment uuid; v_resolution uuid; v_item jsonb; v_sum numeric:=0; v_group uuid:=gen_random_uuid();
begin
 select * into v_o from public.account_balance_observations where id=p_observation_id for update;
 if auth.uid() is null or v_o.id is null or not public.is_household_member(v_o.household_id) then raise exception 'Observation access denied'; end if;
 if v_o.snapshot_version is null then raise exception 'Legacy observation cannot be regularized'; end if;
 select remaining_difference into v_remaining from public.account_reconciliation_cases where observation_id=v_o.id;
 if p_amount<=0 or p_amount>abs(v_remaining) or p_reason_code not in ('missing_expense','missing_income','cash_error','bank_fee','unexplained','other') then raise exception 'Invalid regularization'; end if;
 for v_item in select value from jsonb_array_elements(coalesce(p_envelope_allocations,'[]'::jsonb)) loop v_sum:=v_sum+(v_item->>'amount')::numeric; end loop;
 if jsonb_array_length(coalesce(p_envelope_allocations,'[]'::jsonb))>0 and v_sum<>p_amount then raise exception 'Envelope allocations must equal regularization amount'; end if;
 v_signed:=case when v_remaining>0 then p_amount else -p_amount end;
 v_event:=public.create_or_get_financial_event(v_o.household_id,'reconciliation_adjustment',coalesce(p_occurred_at,now()),'Régularisation rapprochement — '||p_reason_code,trim(p_reason),p_idempotency_key);
 if exists(select 1 from public.account_reconciliation_resolutions where financial_event_id=v_event) then return v_event; end if;
 v_adjustment:=public.ensure_financial_event_system_account(v_o.household_id,'adjustment');
 v_tx:=public.insert_financial_event_ledger_transaction(v_o.household_id,v_event,'correction',coalesce(p_occurred_at,now()),trim(p_reason),p_amount,
   case when v_signed<0 then v_o.account_id else null end,case when v_signed>0 then v_o.account_id else null end,
   case when v_signed>0 then v_o.account_id else v_adjustment end,case when v_signed>0 then v_adjustment else v_o.account_id end,trim(p_reason));
 insert into public.account_reconciliation_resolutions(household_id,observation_id,account_id,resolution_kind,effective_amount,comment,financial_event_id,idempotency_key,created_by)
 values(v_o.household_id,v_o.id,v_o.account_id,'regularization',v_signed,trim(p_reason),v_event,p_idempotency_key::text,auth.uid()) returning id into v_resolution;
 for v_item in select value from jsonb_array_elements(p_envelope_allocations) loop
  if not exists(select 1 from public.envelopes where id=(v_item->>'envelope_id')::uuid and household_id=v_o.household_id and archived_at is null) then raise exception 'Envelope access denied'; end if;
  insert into public.envelope_movements(household_id,event_id,envelope_id,financial_transaction_id,movement_group_id,movement_type,direction,amount,occurred_at,description,created_by)
  values(v_o.household_id,v_event,(v_item->>'envelope_id')::uuid,v_tx,v_group,'adjustment',case when v_signed>0 then 'inflow' else 'outflow' end,(v_item->>'amount')::numeric,coalesce(p_occurred_at,now()),trim(p_reason),auth.uid());
  insert into public.reconciliation_regularization_allocations(household_id,resolution_id,envelope_id,direction,amount)
  values(v_o.household_id,v_resolution,(v_item->>'envelope_id')::uuid,case when v_signed>0 then 'inflow' else 'outflow' end,(v_item->>'amount')::numeric);
 end loop;
 return v_event;
end $$;

revoke all on function public.create_member_compensation(uuid,uuid,uuid,uuid,numeric,text,uuid,uuid,uuid,uuid,uuid,uuid),
 public.record_member_compensation_action(uuid,text,numeric,uuid,text,jsonb,uuid),
 public.regularize_account_reconciliation(uuid,numeric,text,text,jsonb,timestamptz,uuid) from public,anon;
grant execute on function public.create_member_compensation(uuid,uuid,uuid,uuid,numeric,text,uuid,uuid,uuid,uuid,uuid,uuid),
 public.record_member_compensation_action(uuid,text,numeric,uuid,text,jsonb,uuid),
 public.regularize_account_reconciliation(uuid,numeric,text,text,jsonb,timestamptz,uuid) to authenticated;

commit;
