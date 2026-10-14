-- R2.11: explicit provenance for every opening account x envelope position.
begin;

alter table public.envelope_account_position_entries
  drop constraint envelope_account_position_entries_provenance_check;
alter table public.envelope_account_position_entries
  add constraint envelope_account_position_entries_provenance_check check (
    provenance in ('source_proof','balancing_deduction','human_confirmation',
      'opening_inventory_arbitration','human_input'));

create or replace function public.set_envelope_account_position_snapshot(
  p_household_id uuid,p_positions jsonb,p_note text,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_role text; v_batch uuid; v_item jsonb; v_account uuid; v_envelope uuid; v_amount numeric; v_current numeric; v_delta numeric; v_check jsonb; v_provenance text; v_reference text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.household_members where household_id=p_household_id and user_id=auth.uid() and inactive_at is null;
  if v_role <> 'owner' then raise exception 'Only an OWNER can initialise the position matrix'; end if;
  if p_positions is null or jsonb_typeof(p_positions)<>'array' then raise exception 'Positions must be an array'; end if;
  if nullif(trim(p_note),'') is null then raise exception 'Inventory note is required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('r2-initial-position:'||p_household_id::text,0));
  select id into v_batch from public.envelope_account_position_batches where household_id=p_household_id and idempotency_key=p_idempotency_key;
  if v_batch is not null then return v_batch; end if;
  if exists(select 1 from public.envelope_account_position_batches where household_id=p_household_id and batch_kind='explicit_snapshot') then raise exception 'The initial position matrix already exists'; end if;
  create temporary table if not exists pg_temp.r211_positions(account_id uuid,envelope_id uuid,amount numeric(14,2),provenance text,provenance_reference text,primary key(account_id,envelope_id)) on commit drop;
  truncate pg_temp.r211_positions;
  for v_item in select value from jsonb_array_elements(p_positions) loop
    v_account:=(v_item->>'account_id')::uuid; v_envelope:=(v_item->>'envelope_id')::uuid; v_amount:=(v_item->>'amount')::numeric;
    v_provenance:=coalesce(nullif(v_item->>'provenance',''),'openingInventoryArbitration');
    v_provenance:=case v_provenance
      when 'sourceProof' then 'source_proof'
      when 'balancingDeduction' then 'balancing_deduction'
      when 'humanConfirmation' then 'human_confirmation'
      when 'openingInventoryArbitration' then 'opening_inventory_arbitration'
      when 'humanInput' then 'opening_inventory_arbitration'
      when 'human_input' then 'opening_inventory_arbitration'
      else v_provenance end;
    v_reference:=nullif(trim(v_item->>'provenance_reference'),'');
    if v_provenance='opening_inventory_arbitration' and v_reference is null then
      v_reference:='Arbitrage explicite lors de l''inventaire';
    end if;
    if v_amount < 0 then raise exception 'A current position cannot be negative'; end if;
    if v_provenance not in ('source_proof','balancing_deduction','human_confirmation','opening_inventory_arbitration') then raise exception 'Invalid provenance'; end if;
    if v_reference is null then raise exception 'Provenance reference is required'; end if;
    if not exists(select 1 from public.accounts where id=v_account and household_id=p_household_id and archived_at is null and not is_system) then raise exception 'Invalid account'; end if;
    if not exists(select 1 from public.envelopes where id=v_envelope and household_id=p_household_id and archived_at is null) then raise exception 'Invalid envelope'; end if;
    if v_provenance='source_proof' and not exists(
      select 1 from public.envelope_account_initial_evidence x
      where x.household_id=p_household_id and x.account_id=v_account and x.envelope_id=v_envelope
        and x.amount=v_amount and x.evidence_kind='source_proof' and x.source_reference=v_reference
    ) then raise exception 'Unverified source evidence'; end if;
    insert into pg_temp.r211_positions values(v_account,v_envelope,v_amount,v_provenance,v_reference);
  end loop;
  if exists(select 1 from public.accounts a left join public.account_ledger_balances b on b.account_id=a.id left join (select account_id,sum(amount) amount from pg_temp.r211_positions group by account_id) p on p.account_id=a.id where a.household_id=p_household_id and a.archived_at is null and not a.is_system and coalesce(p.amount,0)<>coalesce(b.theoretical_balance,0)) then raise exception 'Snapshot does not reconcile account balances'; end if;
  if exists(select 1 from public.envelopes e left join public.envelope_ledger_balances b on b.envelope_id=e.id left join (select envelope_id,sum(amount) amount from pg_temp.r211_positions group by envelope_id) p on p.envelope_id=e.id where e.household_id=p_household_id and e.archived_at is null and coalesce(p.amount,0)<>coalesce(b.balance,0)) then raise exception 'Snapshot does not reconcile envelope balances'; end if;
  insert into public.envelope_account_position_batches(household_id,batch_kind,idempotency_key,note,created_by) values(p_household_id,'explicit_snapshot',p_idempotency_key,trim(p_note),auth.uid()) returning id into v_batch;
  for v_account,v_envelope,v_amount,v_provenance,v_reference in select account_id,envelope_id,amount,provenance,provenance_reference from pg_temp.r211_positions loop
    v_current:=0;
    select coalesce(amount,0) into v_current from public.envelope_account_current_positions where household_id=p_household_id and account_id=v_account and envelope_id=v_envelope;
    v_delta:=v_amount-coalesce(v_current,0);
    if v_delta<>0 then
      insert into public.envelope_account_position_entries(household_id,batch_id,account_id,envelope_id,amount,provenance,provenance_reference,created_by)
      values(p_household_id,v_batch,v_account,v_envelope,v_delta,v_provenance,v_reference,auth.uid());
    end if;
  end loop;
  v_check:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_check->>'reliable')::boolean then raise exception 'Snapshot invariant failed'; end if;
  return v_batch;
end $$;

create or replace function public.envelope_account_opening_history(p_household_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'batch_id',b.id,'account_id',e.account_id,'envelope_id',e.envelope_id,
    'amount',e.amount,'provenance',case when e.provenance='human_input' then 'opening_inventory_arbitration' else e.provenance end,
    'provenance_reference',e.provenance_reference,'created_by',e.created_by,
    'created_at',e.created_at,'note',b.note) order by e.created_at,e.id),'[]'::jsonb)
  into v_result
  from public.envelope_account_position_entries e
  join public.envelope_account_position_batches b on b.id=e.batch_id and b.household_id=e.household_id
  where e.household_id=p_household_id and b.batch_kind='explicit_snapshot';
  return v_result;
end $$;

revoke all on function public.set_envelope_account_position_snapshot(uuid,jsonb,text,uuid) from public,anon;
grant execute on function public.set_envelope_account_position_snapshot(uuid,jsonb,text,uuid) to authenticated;
revoke all on function public.envelope_account_opening_history(uuid) from public,anon;
grant execute on function public.envelope_account_opening_history(uuid) to authenticated;

comment on function public.envelope_account_opening_history(uuid) is
  'R2.11 read-only audit of opening positions, provenance, actor, timestamp, batch and inventory note.';

commit;
