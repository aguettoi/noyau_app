-- R2.2: append-only physical account x envelope attribution.
-- This is an analytical projection. It never replaces the GL or envelope ledger.

create table public.envelope_account_position_batches (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  batch_kind text not null check (batch_kind in ('explicit_snapshot','monthly_reallocation')),
  month_start date,
  source_fingerprint text,
  idempotency_key uuid not null,
  note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (household_id,idempotency_key)
);

create table public.envelope_account_position_entries (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  batch_id uuid not null references public.envelope_account_position_batches(id) on delete restrict,
  financial_event_id uuid references public.financial_events(id) on delete restrict,
  account_id uuid not null references public.accounts(id) on delete restrict,
  envelope_id uuid not null references public.envelopes(id) on delete restrict,
  amount numeric(14,2) not null check (amount <> 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index envelope_account_position_entries_household_idx
  on public.envelope_account_position_entries(household_id,account_id,envelope_id);
create index envelope_account_position_entries_event_idx
  on public.envelope_account_position_entries(financial_event_id)
  where financial_event_id is not null;

alter table public.envelope_account_position_batches enable row level security;
alter table public.envelope_account_position_entries enable row level security;
revoke all on public.envelope_account_position_batches,public.envelope_account_position_entries from public,anon;
grant select on public.envelope_account_position_batches,public.envelope_account_position_entries to authenticated;
create policy envelope_account_position_batches_read on public.envelope_account_position_batches
  for select to authenticated using (public.is_household_member(household_id));
create policy envelope_account_position_entries_read on public.envelope_account_position_entries
  for select to authenticated using (public.is_household_member(household_id));

create or replace view public.envelope_account_current_positions
with (security_invoker=true) as
select household_id,account_id,envelope_id,sum(amount)::numeric(14,2) amount
from public.envelope_account_position_entries
group by household_id,account_id,envelope_id
having sum(amount) <> 0;
grant select on public.envelope_account_current_positions to authenticated;

create or replace function public.envelope_account_position_snapshot(p_household_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_accounts jsonb; v_envelopes jsonb; v_positions jsonb; v_account_gap numeric; v_envelope_gap numeric; v_fingerprint text;
begin
  if not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('account_id',x.id,'name',x.name,'kind',x.kind,'canonical',x.canonical,'allocated',x.allocated,'gap',x.canonical-x.allocated) order by x.name),'[]'::jsonb),
         coalesce(sum(abs(x.canonical-x.allocated)),0)
  into v_accounts,v_account_gap from (
    select a.id,a.name,a.kind,coalesce(b.theoretical_balance,0)::numeric(14,2) canonical,
           coalesce(sum(p.amount),0)::numeric(14,2) allocated
    from public.accounts a left join public.account_ledger_balances b on b.account_id=a.id
    left join public.envelope_account_current_positions p on p.account_id=a.id and p.household_id=a.household_id
    where a.household_id=p_household_id and a.archived_at is null and not a.is_system
    group by a.id,a.name,a.kind,b.theoretical_balance
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('envelope_id',x.id,'name',x.name,'system',x.is_system,'canonical',x.canonical,'allocated',x.allocated,'gap',x.canonical-x.allocated) order by x.is_system,x.name),'[]'::jsonb),
         coalesce(sum(abs(x.canonical-x.allocated)),0)
  into v_envelopes,v_envelope_gap from (
    select e.id,e.name,e.is_system,coalesce(b.balance,0)::numeric(14,2) canonical,
           coalesce(sum(p.amount),0)::numeric(14,2) allocated
    from public.envelopes e left join public.envelope_ledger_balances b on b.envelope_id=e.id
    left join public.envelope_account_current_positions p on p.envelope_id=e.id and p.household_id=e.household_id
    where e.household_id=p_household_id and e.archived_at is null
    group by e.id,e.name,e.is_system,b.balance
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('account_id',account_id,'envelope_id',envelope_id,'amount',amount) order by account_id,envelope_id),'[]'::jsonb)
  into v_positions from public.envelope_account_current_positions where household_id=p_household_id;
  v_fingerprint:=md5(v_accounts::text||v_envelopes::text||v_positions::text);
  return jsonb_build_object('reliable',v_account_gap=0 and v_envelope_gap=0,'account_gap',v_account_gap,'envelope_gap',v_envelope_gap,'accounts',v_accounts,'envelopes',v_envelopes,'positions',v_positions,'fingerprint',v_fingerprint);
end $$;

create or replace function public.set_envelope_account_position_snapshot(
  p_household_id uuid,p_positions jsonb,p_note text,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_role text; v_batch uuid; v_item jsonb; v_account uuid; v_envelope uuid; v_amount numeric; v_current numeric; v_delta numeric; v_check jsonb;
begin
  select role into v_role from public.household_members where household_id=p_household_id and user_id=auth.uid();
  if v_role <> 'owner' then raise exception 'Only an OWNER can initialise the position matrix'; end if;
  if p_positions is null or jsonb_typeof(p_positions)<>'array' then raise exception 'Positions must be an array'; end if;
  select id into v_batch from public.envelope_account_position_batches where household_id=p_household_id and idempotency_key=p_idempotency_key;
  if v_batch is not null then return v_batch; end if;
  create temporary table if not exists pg_temp.r2_positions(account_id uuid,envelope_id uuid,amount numeric(14,2),primary key(account_id,envelope_id)) on commit drop;
  truncate pg_temp.r2_positions;
  for v_item in select value from jsonb_array_elements(p_positions) loop
    v_account:=(v_item->>'account_id')::uuid; v_envelope:=(v_item->>'envelope_id')::uuid; v_amount:=(v_item->>'amount')::numeric;
    if v_amount < 0 then raise exception 'A current position cannot be negative'; end if;
    if not exists(select 1 from public.accounts where id=v_account and household_id=p_household_id and archived_at is null and not is_system) then raise exception 'Invalid account'; end if;
    if not exists(select 1 from public.envelopes where id=v_envelope and household_id=p_household_id and archived_at is null) then raise exception 'Invalid envelope'; end if;
    insert into pg_temp.r2_positions values(v_account,v_envelope,v_amount);
  end loop;
  if exists(select 1 from public.accounts a left join public.account_ledger_balances b on b.account_id=a.id left join (select account_id,sum(amount) amount from pg_temp.r2_positions group by account_id) p on p.account_id=a.id where a.household_id=p_household_id and a.archived_at is null and not a.is_system and coalesce(p.amount,0)<>coalesce(b.theoretical_balance,0)) then raise exception 'Snapshot does not reconcile account balances'; end if;
  if exists(select 1 from public.envelopes e left join public.envelope_ledger_balances b on b.envelope_id=e.id left join (select envelope_id,sum(amount) amount from pg_temp.r2_positions group by envelope_id) p on p.envelope_id=e.id where e.household_id=p_household_id and e.archived_at is null and coalesce(p.amount,0)<>coalesce(b.balance,0)) then raise exception 'Snapshot does not reconcile envelope balances'; end if;
  insert into public.envelope_account_position_batches(household_id,batch_kind,idempotency_key,note,created_by) values(p_household_id,'explicit_snapshot',p_idempotency_key,nullif(trim(p_note),''),auth.uid()) returning id into v_batch;
  for v_account,v_envelope,v_amount in
    select coalesce(n.account_id,c.account_id),coalesce(n.envelope_id,c.envelope_id),coalesce(n.amount,0)
    from pg_temp.r2_positions n full join (select * from public.envelope_account_current_positions where household_id=p_household_id) c using(account_id,envelope_id)
  loop
    v_current:=0;
    select coalesce(amount,0) into v_current from public.envelope_account_current_positions where household_id=p_household_id and account_id=v_account and envelope_id=v_envelope;
    v_delta:=v_amount-coalesce(v_current,0);
    if v_delta<>0 then insert into public.envelope_account_position_entries(household_id,batch_id,account_id,envelope_id,amount,created_by) values(p_household_id,v_batch,v_account,v_envelope,v_delta,auth.uid()); end if;
  end loop;
  v_check:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_check->>'reliable')::boolean then raise exception 'Snapshot invariant failed'; end if;
  return v_batch;
end $$;

create or replace function public.execute_monthly_account_reallocation(
  p_household_id uuid,p_month_start date,p_source_fingerprint text,p_moves jsonb,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text; v_batch uuid; v_snapshot jsonb; v_item jsonb; v_from uuid; v_to uuid; v_envelope uuid; v_amount numeric; v_available numeric; v_event uuid; v_move_key uuid; v_events jsonb:='[]'::jsonb;
begin
  select role into v_role from public.household_members where household_id=p_household_id and user_id=auth.uid();
  if v_role <> 'owner' then raise exception 'Only an OWNER can confirm a monthly reallocation'; end if;
  select id into v_batch from public.envelope_account_position_batches where household_id=p_household_id and idempotency_key=p_idempotency_key;
  if v_batch is not null then return jsonb_build_object('batch_id',v_batch,'replayed',true); end if;
  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then raise exception 'Current position matrix is not reliable'; end if;
  if v_snapshot->>'fingerprint'<>p_source_fingerprint then raise exception 'Proposal is stale'; end if;
  if p_moves is null or jsonb_typeof(p_moves)<>'array' or jsonb_array_length(p_moves)=0 then raise exception 'Moves are required'; end if;
  insert into public.envelope_account_position_batches(household_id,batch_kind,month_start,source_fingerprint,idempotency_key,created_by) values(p_household_id,'monthly_reallocation',date_trunc('month',p_month_start)::date,p_source_fingerprint,p_idempotency_key,auth.uid()) returning id into v_batch;
  for v_item in select value from jsonb_array_elements(p_moves) loop
    v_from:=(v_item->>'from_account_id')::uuid; v_to:=(v_item->>'to_account_id')::uuid; v_envelope:=(v_item->>'envelope_id')::uuid; v_amount:=(v_item->>'amount')::numeric;
    if v_amount<=0 or v_from=v_to then raise exception 'Invalid reallocation move'; end if;
    select amount into v_available from public.envelope_account_current_positions where household_id=p_household_id and account_id=v_from and envelope_id=v_envelope for update;
    if coalesce(v_available,0)<v_amount then raise exception 'Reallocation exceeds current attributed position'; end if;
    v_move_key:=(substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),1,8)||'-'||substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),9,4)||'-4'||substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),14,3)||'-a'||substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),18,3)||'-'||substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),21,12))::uuid;
    v_event:=public.create_account_transfer_event(p_household_id,now(),'Régularisation mensuelle compte × enveloppe',v_amount,v_from,v_to,'Décision R2 confirmée',v_move_key);
    insert into public.envelope_account_position_entries(household_id,batch_id,financial_event_id,account_id,envelope_id,amount,created_by) values
      (p_household_id,v_batch,v_event,v_from,v_envelope,-v_amount,auth.uid()),(p_household_id,v_batch,v_event,v_to,v_envelope,v_amount,auth.uid());
    v_events:=v_events||jsonb_build_array(v_event);
  end loop;
  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then raise exception 'Reallocation invariant failed'; end if;
  return jsonb_build_object('batch_id',v_batch,'replayed',false,'financial_events',v_events,'snapshot',v_snapshot);
end $$;

revoke all on function public.envelope_account_position_snapshot(uuid),public.set_envelope_account_position_snapshot(uuid,jsonb,text,uuid),public.execute_monthly_account_reallocation(uuid,date,text,jsonb,uuid) from public,anon;
grant execute on function public.envelope_account_position_snapshot(uuid),public.set_envelope_account_position_snapshot(uuid,jsonb,text,uuid),public.execute_monthly_account_reallocation(uuid,date,text,jsonb,uuid) to authenticated;

create or replace function public.monthly_close_todo_items(p_household_id uuid,p_month_start date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_end date:=p_month_start+interval '1 month'; v_result jsonb;
begin
  if not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.code,x.label),'[]'::jsonb) into v_result from (
    select 'reconciliations' code,'Écart de rapprochement — '||a.name label,'blocker' severity,'Comptes' destination,c.observation_id::text context_id,c.account_id::text account_id,null::text financial_event_id,c.observation_id::text reconciliation_id,null::text compensation_id
    from public.account_reconciliation_cases c join public.accounts a on a.id=c.account_id where c.household_id=p_household_id and c.status in ('open','partially_resolved','explained_pending')
    union all
    select 'cash','Inventaire espèces — '||a.name,'blocker','Comptes',a.id::text,a.id::text,null,null,null from public.accounts a where a.household_id=p_household_id and a.kind='cash' and a.archived_at is null and not exists(select 1 from public.account_balance_observations o where o.account_id=a.id and o.observed_at>=p_month_start and o.observed_at<v_end)
    union all
    select 'receipts','Justificatif — '||e.description,'warning','Transactions',e.id::text,null,e.id::text,null,null from public.financial_events e where e.household_id=p_household_id and e.event_type in ('cash_expense','debt_expense') and e.occurred_at>=p_month_start and e.occurred_at<v_end and not exists(select 1 from public.financial_event_attachments a where a.financial_event_id=e.id and a.deleted_at is null)
    union all
    select 'compensations','Compensation à traiter','warning','Compensations',c.id::text,null,c.source_financial_event_id::text,null,c.id::text from public.member_compensation_balances c where c.household_id=p_household_id and c.remaining_amount>0
  ) x;
  return v_result;
end $$;
revoke all on function public.monthly_close_todo_items(uuid,date) from public,anon;
grant execute on function public.monthly_close_todo_items(uuid,date) to authenticated;
