-- R2.10: globally net physical transfers while preserving every analytical
-- account x envelope justification. No pilot data is created by this migration.
begin;

alter table public.envelope_account_position_batches
  add column if not exists economic_date date,
  add column if not exists execution_plan jsonb;

create table public.envelope_account_reallocation_justifications (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  batch_id uuid not null references public.envelope_account_position_batches(id) on delete restrict,
  from_account_id uuid not null references public.accounts(id) on delete restrict,
  to_account_id uuid not null references public.accounts(id) on delete restrict,
  envelope_id uuid not null references public.envelopes(id) on delete restrict,
  amount numeric(14,2) not null check(amount>0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(batch_id,from_account_id,to_account_id,envelope_id)
);
create index envelope_account_reallocation_justifications_household_idx
  on public.envelope_account_reallocation_justifications(household_id,batch_id);
alter table public.envelope_account_reallocation_justifications enable row level security;
revoke all on public.envelope_account_reallocation_justifications from public,anon;
grant select on public.envelope_account_reallocation_justifications to authenticated;
create policy envelope_account_reallocation_justifications_read
  on public.envelope_account_reallocation_justifications for select to authenticated
  using((select public.is_household_member(household_id)));

create table public.envelope_account_physical_transfers (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  batch_id uuid not null references public.envelope_account_position_batches(id) on delete restrict,
  financial_event_id uuid not null references public.financial_events(id) on delete restrict,
  from_account_id uuid not null references public.accounts(id) on delete restrict,
  to_account_id uuid not null references public.accounts(id) on delete restrict,
  amount numeric(14,2) not null check(amount>0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(batch_id,from_account_id,to_account_id)
);
create index envelope_account_physical_transfers_household_idx
  on public.envelope_account_physical_transfers(household_id,batch_id);
alter table public.envelope_account_physical_transfers enable row level security;
revoke all on public.envelope_account_physical_transfers from public,anon;
grant select on public.envelope_account_physical_transfers to authenticated;
create policy envelope_account_physical_transfers_read
  on public.envelope_account_physical_transfers for select to authenticated
  using((select public.is_household_member(household_id)));

create or replace function public.execute_monthly_account_reallocation_v2(
  p_household_id uuid,p_month_start date,p_source_fingerprint text,
  p_economic_date date,p_physical_transfers jsonb,p_analytical_moves jsonb,
  p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_role text; v_batch uuid; v_snapshot jsonb; v_item jsonb;
  v_from uuid; v_to uuid; v_envelope uuid; v_amount numeric;
  v_event uuid; v_move_key uuid; v_events jsonb:='[]'::jsonb;
  v_source uuid; v_destination uuid; v_source_need numeric; v_destination_need numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.household_members
    where household_id=p_household_id and user_id=auth.uid() and inactive_at is null;
  if v_role<>'owner' then raise exception 'Only an OWNER can confirm a monthly reallocation'; end if;
  if p_month_start<>date_trunc('month',p_month_start)::date or p_economic_date is null then
    raise exception 'A valid month and economic date are required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_household_id::text,0));
  select id into v_batch from public.envelope_account_position_batches
    where household_id=p_household_id and idempotency_key=p_idempotency_key;
  if v_batch is not null then return jsonb_build_object('batch_id',v_batch,'replayed',true); end if;
  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then raise exception 'Current position matrix is not reliable'; end if;
  if v_snapshot->>'fingerprint'<>p_source_fingerprint then raise exception 'Proposal is stale'; end if;
  if p_analytical_moves is null or jsonb_typeof(p_analytical_moves)<>'array'
    or jsonb_array_length(p_analytical_moves)=0 then raise exception 'Analytical moves are required'; end if;
  if p_physical_transfers is null or jsonb_typeof(p_physical_transfers)<>'array' then
    raise exception 'Physical transfers must be an array';
  end if;
  if exists(select 1 from public.envelopes e
    left join public.envelope_ledger_balances b on b.envelope_id=e.id
    left join (select envelope_id,sum(target_amount) amount from public.monthly_envelope_account_targets
      where household_id=p_household_id and month_start=p_month_start group by envelope_id) t on t.envelope_id=e.id
    where e.household_id=p_household_id and e.archived_at is null
      and coalesce(t.amount,0)<>coalesce(b.balance,0)) then
    raise exception 'Targets do not reconcile envelope balances';
  end if;

  create temporary table if not exists pg_temp.r2_analytical_moves(
    from_account_id uuid,to_account_id uuid,envelope_id uuid,amount numeric(14,2),
    primary key(from_account_id,to_account_id,envelope_id)) on commit drop;
  create temporary table if not exists pg_temp.r2_physical_transfers(
    from_account_id uuid,to_account_id uuid,amount numeric(14,2),
    primary key(from_account_id,to_account_id)) on commit drop;
  create temporary table if not exists pg_temp.r2_account_net(
    account_id uuid primary key,amount numeric(14,2) not null) on commit drop;
  create temporary table if not exists pg_temp.r2_expected_transfers(
    from_account_id uuid,to_account_id uuid,amount numeric(14,2),
    primary key(from_account_id,to_account_id)) on commit drop;
  truncate pg_temp.r2_analytical_moves,pg_temp.r2_physical_transfers,
    pg_temp.r2_account_net,pg_temp.r2_expected_transfers;

  for v_item in select value from jsonb_array_elements(p_analytical_moves) loop
    v_from:=(v_item->>'from_account_id')::uuid; v_to:=(v_item->>'to_account_id')::uuid;
    v_envelope:=(v_item->>'envelope_id')::uuid; v_amount:=(v_item->>'amount')::numeric;
    if v_amount<=0 or v_from=v_to then raise exception 'Invalid analytical move'; end if;
    if not exists(select 1 from public.accounts where id=v_from and household_id=p_household_id and archived_at is null and not is_system)
      or not exists(select 1 from public.accounts where id=v_to and household_id=p_household_id and archived_at is null and not is_system)
      or not exists(select 1 from public.envelopes where id=v_envelope and household_id=p_household_id and archived_at is null)
      then raise exception 'Cross-household or inactive analytical reference'; end if;
    insert into pg_temp.r2_analytical_moves values(v_from,v_to,v_envelope,v_amount);
  end loop;
  for v_item in select value from jsonb_array_elements(p_physical_transfers) loop
    v_from:=(v_item->>'from_account_id')::uuid; v_to:=(v_item->>'to_account_id')::uuid;
    v_amount:=(v_item->>'amount')::numeric;
    if v_amount<=0 or v_from=v_to then raise exception 'Invalid physical transfer'; end if;
    if not exists(select 1 from public.accounts where id=v_from and household_id=p_household_id and archived_at is null and not is_system)
      or not exists(select 1 from public.accounts where id=v_to and household_id=p_household_id and archived_at is null and not is_system)
      then raise exception 'Cross-household or inactive physical account'; end if;
    insert into pg_temp.r2_physical_transfers values(v_from,v_to,v_amount);
  end loop;

  insert into pg_temp.r2_account_net(account_id,amount)
  select account_id,sum(amount) from (
    select from_account_id account_id,-amount amount from pg_temp.r2_analytical_moves
    union all select to_account_id,amount from pg_temp.r2_analytical_moves
  ) n group by account_id having sum(amount)<>0;
  loop
    select account_id,-amount into v_source,v_source_need from pg_temp.r2_account_net
      where amount<0 order by account_id limit 1;
    exit when not found;
    select account_id,amount into v_destination,v_destination_need from pg_temp.r2_account_net
      where amount>0 order by account_id limit 1;
    if not found then raise exception 'Analytical net is unbalanced'; end if;
    v_amount:=least(v_source_need,v_destination_need);
    insert into pg_temp.r2_expected_transfers values(v_source,v_destination,v_amount);
    update pg_temp.r2_account_net set amount=amount+v_amount where account_id=v_source;
    update pg_temp.r2_account_net set amount=amount-v_amount where account_id=v_destination;
    delete from pg_temp.r2_account_net where amount=0;
  end loop;
  if exists(select 1 from pg_temp.r2_account_net) then raise exception 'Analytical net is unbalanced'; end if;
  if exists(select 1 from pg_temp.r2_expected_transfers e full join pg_temp.r2_physical_transfers p
    using(from_account_id,to_account_id) where coalesce(e.amount,0)<>coalesce(p.amount,0)) then
    raise exception 'Physical transfers are not the deterministic global net';
  end if;
  if exists(
    with deltas as (
      select from_account_id account_id,envelope_id,-amount amount from pg_temp.r2_analytical_moves
      union all select to_account_id,envelope_id,amount from pg_temp.r2_analytical_moves
    ), proposed as (
      select account_id,envelope_id,sum(amount)::numeric(14,2) amount from (
        select account_id,envelope_id,amount from public.envelope_account_current_positions where household_id=p_household_id
        union all select * from deltas) q group by account_id,envelope_id having sum(amount)<>0
    ), target as (
      select account_id,envelope_id,target_amount amount from public.monthly_envelope_account_targets
      where household_id=p_household_id and month_start=p_month_start and target_amount<>0)
    select 1 from proposed p full join target t using(account_id,envelope_id)
      where coalesce(p.amount,0)<>coalesce(t.amount,0)
  ) then raise exception 'Analytical moves do not reach the current monthly targets'; end if;

  insert into public.envelope_account_position_batches(
    household_id,batch_kind,month_start,source_fingerprint,idempotency_key,
    economic_date,execution_plan,note,created_by)
  values(p_household_id,'monthly_reallocation',p_month_start,p_source_fingerprint,
    p_idempotency_key,p_economic_date,jsonb_build_object(
      'physical_transfers',p_physical_transfers,'analytical_moves',p_analytical_moves),
    'Netting bancaire global R2.10',auth.uid()) returning id into v_batch;

  for v_from,v_to,v_amount in select from_account_id,to_account_id,amount
    from pg_temp.r2_physical_transfers order by from_account_id,to_account_id loop
    v_move_key:=public.r2_7_deterministic_uuid(
      'r2.10|'||p_idempotency_key||'|'||v_from||'|'||v_to);
    v_event:=public.create_account_transfer_event(p_household_id,p_economic_date::timestamptz,
      'Régularisation mensuelle nette compte × enveloppe',v_amount,v_from,v_to,
      'Décision R2.10 confirmée',v_move_key);
    insert into public.envelope_account_physical_transfers(
      household_id,batch_id,financial_event_id,from_account_id,to_account_id,amount,created_by)
    values(p_household_id,v_batch,v_event,v_from,v_to,v_amount,auth.uid());
    v_events:=v_events||jsonb_build_array(v_event);
  end loop;
  for v_from,v_to,v_envelope,v_amount in select from_account_id,to_account_id,envelope_id,amount
    from pg_temp.r2_analytical_moves order by from_account_id,to_account_id,envelope_id loop
    insert into public.envelope_account_reallocation_justifications(
      household_id,batch_id,from_account_id,to_account_id,envelope_id,amount,created_by)
    values(p_household_id,v_batch,v_from,v_to,v_envelope,v_amount,auth.uid());
    insert into public.envelope_account_position_entries(
      household_id,batch_id,account_id,envelope_id,amount,created_by)
    values(p_household_id,v_batch,v_from,v_envelope,-v_amount,auth.uid()),
      (p_household_id,v_batch,v_to,v_envelope,v_amount,auth.uid());
  end loop;
  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then raise exception 'Reallocation invariant failed'; end if;
  return jsonb_build_object('batch_id',v_batch,'replayed',false,
    'financial_events',v_events,'snapshot',v_snapshot);
end $$;

revoke all on function public.execute_monthly_account_reallocation_v2(
  uuid,date,text,date,jsonb,jsonb,uuid) from public,anon;
grant execute on function public.execute_monthly_account_reallocation_v2(
  uuid,date,text,date,jsonb,jsonb,uuid) to authenticated;

comment on function public.execute_monthly_account_reallocation_v2(
  uuid,date,text,date,jsonb,jsonb,uuid) is
  'R2.10 atomically validates analytical targets and executes only the deterministic globally-netted physical account transfers.';

commit;
