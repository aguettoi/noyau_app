-- Immutable, partial and cumulative reversals of canonical obligation
-- settlements.  Source settlements and their original ledger/envelope rows are
-- deliberately never changed or removed.
begin;

alter table public.financial_events
  drop constraint if exists financial_events_event_type_check;
alter table public.financial_events add constraint financial_events_event_type_check
  check (event_type in (
    'cash_expense', 'cash_income', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement', 'recovery_receivable',
    'recovery_settlement', 'budget_allocation', 'account_transfer',
    'envelope_transfer', 'debt_writeoff', 'income_receivable_writeoff',
    'recovery_writeoff', 'recovery_reversal',
    'debt_settlement_reversal', 'receivable_settlement_reversal',
    'recovery_settlement_reversal'
  ));

alter table public.financial_transactions
  drop constraint if exists financial_transactions_type_check;
alter table public.financial_transactions add constraint financial_transactions_type_check
  check (type in (
    'allocation', 'expense', 'transfer', 'adjustment', 'recovery', 'income',
    'opening_balance', 'correction', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement', 'recovery_receivable',
    'recovery_settlement', 'debt_writeoff', 'income_receivable_writeoff',
    'recovery_writeoff', 'recovery_reversal',
    'debt_settlement_reversal', 'receivable_settlement_reversal',
    'recovery_settlement_reversal'
  ));

alter table public.obligation_settlements
  add constraint obligation_settlements_id_household_unique unique (id, household_id);

create table public.obligation_settlement_reversals (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  obligation_id uuid not null,
  source_settlement_id uuid not null,
  financial_event_id uuid not null,
  financial_transaction_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  occurred_at timestamptz not null,
  reason text not null check (char_length(trim(reason)) between 1 and 280),
  notes text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (financial_event_id),
  foreign key (obligation_id, household_id)
    references public.obligations(id, household_id) on delete restrict,
  foreign key (source_settlement_id, household_id)
    references public.obligation_settlements(id, household_id) on delete restrict,
  foreign key (financial_event_id, household_id)
    references public.financial_events(id, household_id) on delete restrict,
  foreign key (financial_transaction_id, household_id)
    references public.financial_transactions(id, household_id) on delete restrict,
  foreign key (household_id, created_by)
    references public.household_members(household_id, user_id) on delete restrict
);
create index obligation_settlement_reversals_source_idx
  on public.obligation_settlement_reversals(source_settlement_id, occurred_at);
create index obligation_settlement_reversals_obligation_idx
  on public.obligation_settlement_reversals(obligation_id, occurred_at);

create or replace function public.assert_obligation_settlement_reversal_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_source_amount numeric(14,2); v_total numeric(14,2); v_obligation_id uuid;
begin
  select amount, obligation_id into v_source_amount, v_obligation_id
  from public.obligation_settlements
  where id = new.source_settlement_id and household_id = new.household_id;
  if v_source_amount is null or v_obligation_id <> new.obligation_id then
    raise exception 'Settlement reversal must target a settlement of the same household obligation';
  end if;
  select coalesce(sum(amount), 0) into v_total
  from public.obligation_settlement_reversals
  where source_settlement_id = new.source_settlement_id and household_id = new.household_id;
  if v_total > v_source_amount then
    raise exception 'Settlement reversal exceeds the amount still reversible';
  end if;
  return null;
end; $$;
create constraint trigger obligation_settlement_reversals_limit
after insert on public.obligation_settlement_reversals
deferrable initially deferred for each row
execute function public.assert_obligation_settlement_reversal_limit();
create trigger obligation_settlement_reversals_immutable
before update or delete on public.obligation_settlement_reversals
for each row execute function public.prevent_financial_event_mutation();

alter table public.obligation_settlement_reversals enable row level security;
revoke all on public.obligation_settlement_reversals from public, anon, authenticated;
grant select on public.obligation_settlement_reversals to authenticated;
create policy "members read obligation settlement reversals"
on public.obligation_settlement_reversals for select
using (public.is_household_member(household_id));

-- A source envelope movement can now be counter-posted several times.  The
-- old unique index only allowed a single full reversal.
drop index if exists public.envelope_movements_single_reversal_idx;
create index envelope_movements_reversal_source_idx
  on public.envelope_movements(reversal_of) where reversal_of is not null;

create or replace function public.assert_envelope_movement_group(
  p_movement_group_id uuid
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_household_id uuid; v_count integer; v_type text; v_event_id uuid;
  v_transaction_id uuid; v_transaction_type text; v_transaction_amount numeric(14,2);
  v_total numeric(14,2); v_inflow numeric(14,2); v_outflow numeric(14,2);
  v_all_ordinary boolean; v_source_id uuid;
begin
  select household_id, count(*), min(movement_type) into v_household_id,v_count,v_type
  from public.envelope_movements where movement_group_id=p_movement_group_id group by household_id;
  if not found then return; end if;
  if exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and household_id<>v_household_id) then raise exception 'An envelope movement group cannot span households'; end if;
  select event_id,financial_transaction_id into v_event_id,v_transaction_id from public.envelope_movements where movement_group_id=p_movement_group_id limit 1;
  if exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and financial_transaction_id is distinct from v_transaction_id) or exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and event_id is distinct from v_event_id) then raise exception 'Envelope movement group must reference one transaction and FinancialEvent'; end if;
  if v_type in ('consumption','allocation','refund','adjustment','reversal') and exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type<>v_type) then raise exception 'Envelope movement group contains incompatible types'; end if;
  if v_type='consumption' then
    select type,amount into v_transaction_type,v_transaction_amount from public.financial_transactions where id=v_transaction_id and household_id=v_household_id;
    select sum(amount) into v_total from public.envelope_movements where movement_group_id=p_movement_group_id;
    if v_transaction_id is null or v_transaction_type not in ('expense','debt_expense') or v_total<>v_transaction_amount then raise exception 'Expense envelope allocations must equal the expense amount'; end if;
  elsif v_type='allocation' then
    select type,amount into v_transaction_type,v_transaction_amount from public.financial_transactions where id=v_transaction_id and household_id=v_household_id;
    select sum(m.amount),bool_and(not e.is_system) into v_total,v_all_ordinary from public.envelope_movements m join public.envelopes e on e.id=m.envelope_id where m.movement_group_id=p_movement_group_id;
    if (select event_type from public.financial_events where id=v_event_id)='cash_income' then
      if v_transaction_id is null or v_transaction_type<>'income' or v_total<>v_transaction_amount then raise exception 'Income envelope allocations must equal the income amount'; end if;
    elsif (select event_type from public.financial_events where id=v_event_id)='receivable_settlement' then
      if v_transaction_id is null or v_transaction_type<>'receivable_settlement' or v_total<>v_transaction_amount then raise exception 'Receivable settlement envelope allocations must equal the settlement amount'; end if;
    elsif (select event_type from public.financial_events where id=v_event_id)='budget_allocation' then
      if v_count<>1 or v_transaction_id is null or v_transaction_type<>'allocation' or v_total<>v_transaction_amount or not coalesce(v_all_ordinary,false) then raise exception 'Budget allocation must fund one ordinary destination envelope directly'; end if;
    else raise exception 'Allocation movements require a supported FinancialEvent type'; end if;
  elsif v_type='reversal' then
    if v_transaction_id is null or exists(
      select 1 from public.envelope_movements r join public.envelope_movements o on o.id=r.reversal_of
      where r.movement_group_id=p_movement_group_id and (
        o.household_id<>r.household_id or o.envelope_id<>r.envelope_id or o.direction=r.direction
      )
    ) then raise exception 'Envelope reversal must counter-post an original movement in the same envelope'; end if;
    if exists(
      select 1 from public.envelope_movements r
      where r.movement_group_id=p_movement_group_id and r.amount > (
        select o.amount - coalesce(sum(previous.amount),0)
        from public.envelope_movements o
        left join public.envelope_movements previous on previous.reversal_of=o.id and previous.id<>r.id
        where o.id=r.reversal_of group by o.amount
      )
    ) then raise exception 'Envelope reversal exceeds the amount still reversible'; end if;
  elsif v_type in ('transfer_in','transfer_out') then
    select count(*),sum(case when direction='inflow' then amount else 0 end),sum(case when direction='outflow' then amount else 0 end) into v_count,v_inflow,v_outflow from public.envelope_movements where movement_group_id=p_movement_group_id;
    select envelope_id into v_source_id from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type='transfer_out';
    if v_count<2 or v_inflow<>v_outflow or (select count(*) from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type='transfer_in')<>v_count-1 or (select count(*) from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type='transfer_out')<>1 or exists(select 1 from public.envelope_movements where movement_group_id=p_movement_group_id and movement_type='transfer_in' and envelope_id=v_source_id) or (select count(distinct envelope_id) from public.envelope_movements where movement_group_id=p_movement_group_id)<>v_count then raise exception 'Envelope transfer must have one source and balanced distinct destinations'; end if;
  end if;
end; $$;

create or replace view public.obligation_balances
with (security_invoker = true) as
select o.household_id,o.id as obligation_id,o.obligation_kind,o.receivable_kind,
  o.origin_event_id,o.origin_transaction_id,o.origin_envelope_id,
  o.recovery_source_event_id,o.recovery_source_envelope_id,o.initial_amount,
  (coalesce(s.gross_settled_amount,0)-coalesce(r.settlement_reversed_amount,0))::numeric(14,2) as settled_amount,
  (o.initial_amount-coalesce(s.gross_settled_amount,0)+coalesce(r.settlement_reversed_amount,0)-coalesce(a.written_off_amount,0)-coalesce(a.reversed_amount,0))::numeric(14,2) as remaining_amount,
  case when (o.initial_amount-coalesce(s.gross_settled_amount,0)+coalesce(r.settlement_reversed_amount,0)-coalesce(a.written_off_amount,0)-coalesce(a.reversed_amount,0))>0 then 'open' when coalesce(a.reversed_amount,0)>0 then 'reversed' when coalesce(a.written_off_amount,0)>0 then 'written_off' else 'settled' end as status,
  o.counterparty_name,o.description,o.due_at,o.created_at,
  (o.due_at is not null and o.due_at<current_date and (o.initial_amount-coalesce(s.gross_settled_amount,0)+coalesce(r.settlement_reversed_amount,0)-coalesce(a.written_off_amount,0)-coalesce(a.reversed_amount,0))>0) as is_overdue,
  coalesce(a.written_off_amount,0)::numeric(14,2) as written_off_amount,
  coalesce(a.reversed_amount,0)::numeric(14,2) as reversed_amount,
  coalesce(s.gross_settled_amount,0)::numeric(14,2) as gross_settled_amount,
  coalesce(r.settlement_reversed_amount,0)::numeric(14,2) as settlement_reversed_amount,
  (coalesce(s.gross_settled_amount,0)-coalesce(r.settlement_reversed_amount,0))::numeric(14,2) as net_settled_amount
from public.obligations o
left join lateral (select coalesce(sum(amount),0)::numeric(14,2) gross_settled_amount from public.obligation_settlements where obligation_id=o.id) s on true
left join lateral (select coalesce(sum(amount),0)::numeric(14,2) settlement_reversed_amount from public.obligation_settlement_reversals where obligation_id=o.id) r on true
left join lateral (select coalesce(sum(amount) filter(where adjustment_kind='writeoff'),0)::numeric(14,2) written_off_amount,coalesce(sum(amount) filter(where adjustment_kind='reversal'),0)::numeric(14,2) reversed_amount from public.obligation_adjustments where obligation_id=o.id) a on true;

create or replace function public.reverse_obligation_settlement_event(
  p_household_id uuid,p_source_settlement_id uuid,p_occurred_at timestamptz,
  p_amount numeric,p_reason text,p_notes text,p_idempotency_key uuid,
  p_expected_kind text,p_envelope_reversals jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_event_id uuid; v_tx_id uuid; v_obligation_id uuid; v_source_amount numeric(14,2);
  v_source_event_id uuid; v_source_tx_id uuid; v_account_id uuid; v_reversible numeric(14,2);
  v_event_type text; v_debt_id uuid; v_receivable_id uuid; v_group_id uuid:=gen_random_uuid();
  v_item jsonb; v_movement_id uuid; v_movement_amount numeric(14,2); v_total numeric(14,2):=0;
  v_original_envelope_id uuid; v_original_direction text; v_seen uuid[]:='{}';
begin
  if p_amount is null or p_amount<=0 then raise exception 'A positive reversal amount is required'; end if;
  if char_length(trim(coalesce(p_reason,'')))=0 then raise exception 'A reversal reason is required'; end if;
  v_event_type:=case p_expected_kind when 'debt' then 'debt_settlement_reversal' when 'income' then 'receivable_settlement_reversal' when 'recovery' then 'recovery_settlement_reversal' else null end;
  if v_event_type is null then raise exception 'Unsupported settlement reversal'; end if;
  v_event_id:=public.create_or_get_financial_event(p_household_id,v_event_type,p_occurred_at,'Annulation : '||trim(p_reason),p_notes,p_idempotency_key);
  if exists(select 1 from public.obligation_settlement_reversals where financial_event_id=v_event_id) then return v_event_id; end if;
  select s.obligation_id,s.amount,s.event_id,s.financial_transaction_id
  into v_obligation_id,v_source_amount,v_source_event_id,v_source_tx_id
  from public.obligation_settlements s join public.obligations o on o.id=s.obligation_id and o.household_id=s.household_id join public.financial_transactions t on t.id=s.financial_transaction_id and t.household_id=s.household_id
  where s.id=p_source_settlement_id and s.household_id=p_household_id for update of s,o;
  if not found then raise exception 'Source settlement does not belong to household'; end if;
  -- Validate exact subtype separately: a debt has a null receivable kind.
  if (p_expected_kind='debt' and (select obligation_kind from public.obligations where id=v_obligation_id)<>'debt') or
     (p_expected_kind='income' and (select receivable_kind from public.obligations where id=v_obligation_id)<>'income') or
     (p_expected_kind='recovery' and (select receivable_kind from public.obligations where id=v_obligation_id)<>'recovery') then raise exception 'Source settlement has an incompatible obligation type'; end if;
  select v_source_amount-coalesce(sum(amount),0) into v_reversible from public.obligation_settlement_reversals where source_settlement_id=p_source_settlement_id and household_id=p_household_id;
  if p_amount>v_reversible then raise exception 'Settlement reversal exceeds the amount still reversible'; end if;
  if p_expected_kind='debt' then
    select source_account_id into v_account_id from public.financial_transactions where id=v_source_tx_id;
    perform public.assert_financial_event_ordinary_account(p_household_id,v_account_id);
    v_debt_id:=public.ensure_financial_event_system_account(p_household_id,'debt');
    v_tx_id:=public.insert_financial_event_ledger_transaction(p_household_id,v_event_id,'debt_settlement_reversal',p_occurred_at,'Annulation règlement : '||trim(p_reason),p_amount,null,v_account_id,v_account_id,v_debt_id,p_notes);
  else
    select destination_account_id into v_account_id from public.financial_transactions where id=v_source_tx_id;
    perform public.assert_financial_event_ordinary_account(p_household_id,v_account_id);
    v_receivable_id:=public.ensure_financial_event_system_account(p_household_id,'receivable');
    v_tx_id:=public.insert_financial_event_ledger_transaction(p_household_id,v_event_id,case when p_expected_kind='income' then 'receivable_settlement_reversal' else 'recovery_settlement_reversal' end,p_occurred_at,'Annulation encaissement : '||trim(p_reason),p_amount,v_account_id,null,v_receivable_id,v_account_id,p_notes);
  end if;
  if p_expected_kind='income' then
    if p_envelope_reversals is null or jsonb_typeof(p_envelope_reversals)<>'array' then raise exception 'Income reversal allocations must be an array'; end if;
    for v_item in select value from jsonb_array_elements(p_envelope_reversals) loop
      begin v_movement_id:=nullif(v_item->>'source_movement_id','')::uuid; v_movement_amount:=nullif(v_item->>'amount','')::numeric; exception when others then raise exception 'Each income reversal requires a source movement and amount'; end;
      if v_movement_id is null or v_movement_amount is null or v_movement_amount<=0 or v_movement_id=any(v_seen) then raise exception 'Each income reversal source must be unique with a positive amount'; end if;
      select envelope_id,direction into v_original_envelope_id,v_original_direction from public.envelope_movements where id=v_movement_id and household_id=p_household_id and event_id=v_source_event_id and movement_type='allocation' for update;
      if not found or v_original_direction<>'inflow' then raise exception 'Income reversal source movement does not belong to the source settlement'; end if;
      if v_movement_amount>(select amount-coalesce(sum(r.amount),0) from public.envelope_movements m left join public.envelope_movements r on r.reversal_of=m.id where m.id=v_movement_id group by m.amount) then raise exception 'Income reversal exceeds source envelope movement'; end if;
      insert into public.envelope_movements(household_id,event_id,financial_transaction_id,envelope_id,movement_group_id,movement_type,direction,amount,occurred_at,description,reversal_of,created_by) values(p_household_id,v_event_id,v_tx_id,v_original_envelope_id,v_group_id,'reversal','outflow',v_movement_amount,coalesce(p_occurred_at,now()),'Annulation encaissement : '||trim(p_reason),v_movement_id,auth.uid());
      v_seen:=array_append(v_seen,v_movement_id); v_total:=v_total+v_movement_amount;
    end loop;
    if v_total<>p_amount then raise exception 'Income reversal envelope allocations must equal the reversal amount'; end if;
  elsif p_expected_kind='recovery' then
    select id,envelope_id,direction into v_movement_id,v_original_envelope_id,v_original_direction from public.envelope_movements where household_id=p_household_id and event_id=v_source_event_id and movement_type='refund' for update;
    if not found or v_original_direction<>'inflow' then raise exception 'Recovery settlement has no source envelope refund'; end if;
    if p_amount>(select amount-coalesce(sum(r.amount),0) from public.envelope_movements m left join public.envelope_movements r on r.reversal_of=m.id where m.id=v_movement_id group by m.amount) then raise exception 'Recovery reversal exceeds source envelope refund'; end if;
    insert into public.envelope_movements(household_id,event_id,financial_transaction_id,envelope_id,movement_group_id,movement_type,direction,amount,occurred_at,description,reversal_of,created_by) values(p_household_id,v_event_id,v_tx_id,v_original_envelope_id,v_group_id,'reversal','outflow',p_amount,coalesce(p_occurred_at,now()),'Annulation remboursement : '||trim(p_reason),v_movement_id,auth.uid());
  end if;
  insert into public.obligation_settlement_reversals(household_id,obligation_id,source_settlement_id,financial_event_id,financial_transaction_id,amount,occurred_at,reason,notes,created_by) values(p_household_id,v_obligation_id,p_source_settlement_id,v_event_id,v_tx_id,p_amount,coalesce(p_occurred_at,now()),trim(p_reason),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  return v_event_id;
end; $$;

create function public.reverse_debt_settlement_event(p_household_id uuid,p_source_settlement_id uuid,p_occurred_at timestamptz,p_amount numeric,p_reason text,p_notes text default null,p_idempotency_key uuid default null) returns uuid language sql security definer set search_path=public as $$ select public.reverse_obligation_settlement_event($1,$2,$3,$4,$5,$6,$7,'debt','[]'::jsonb) $$;
create function public.reverse_income_receivable_settlement_event(p_household_id uuid,p_source_settlement_id uuid,p_occurred_at timestamptz,p_amount numeric,p_reason text,p_envelope_reversals jsonb,p_notes text default null,p_idempotency_key uuid default null) returns uuid language sql security definer set search_path=public as $$ select public.reverse_obligation_settlement_event($1,$2,$3,$4,$5,$7,$8,'income',$6) $$;
create function public.reverse_recovery_settlement_event(p_household_id uuid,p_source_settlement_id uuid,p_occurred_at timestamptz,p_amount numeric,p_reason text,p_notes text default null,p_idempotency_key uuid default null) returns uuid language sql security definer set search_path=public as $$ select public.reverse_obligation_settlement_event($1,$2,$3,$4,$5,$6,$7,'recovery','[]'::jsonb) $$;

revoke all on function public.reverse_obligation_settlement_event(uuid,uuid,timestamptz,numeric,text,text,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.reverse_debt_settlement_event(uuid,uuid,timestamptz,numeric,text,text,uuid) from public,anon;
revoke all on function public.reverse_income_receivable_settlement_event(uuid,uuid,timestamptz,numeric,text,jsonb,text,uuid) from public,anon;
revoke all on function public.reverse_recovery_settlement_event(uuid,uuid,timestamptz,numeric,text,text,uuid) from public,anon;
grant execute on function public.reverse_debt_settlement_event(uuid,uuid,timestamptz,numeric,text,text,uuid) to authenticated;
grant execute on function public.reverse_income_receivable_settlement_event(uuid,uuid,timestamptz,numeric,text,jsonb,text,uuid) to authenticated;
grant execute on function public.reverse_recovery_settlement_event(uuid,uuid,timestamptz,numeric,text,text,uuid) to authenticated;

commit;
