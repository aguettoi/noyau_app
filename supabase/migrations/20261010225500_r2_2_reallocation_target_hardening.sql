-- R2.2 hardening: the server, not the UI, proves that moves reach the target.
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
  if exists(select 1 from public.envelopes e left join public.envelope_ledger_balances b on b.envelope_id=e.id left join (select envelope_id,sum(target_amount) amount from public.monthly_envelope_account_targets where household_id=p_household_id and month_start=date_trunc('month',p_month_start)::date group by envelope_id) t on t.envelope_id=e.id where e.household_id=p_household_id and e.archived_at is null and coalesce(t.amount,0)<>coalesce(b.balance,0)) then raise exception 'Targets do not reconcile envelope balances'; end if;
  create temporary table if not exists pg_temp.r2_moves(from_account_id uuid,to_account_id uuid,envelope_id uuid,amount numeric(14,2),primary key(from_account_id,to_account_id,envelope_id)) on commit drop;
  truncate pg_temp.r2_moves;
  for v_item in select value from jsonb_array_elements(p_moves) loop
    v_from:=(v_item->>'from_account_id')::uuid; v_to:=(v_item->>'to_account_id')::uuid; v_envelope:=(v_item->>'envelope_id')::uuid; v_amount:=(v_item->>'amount')::numeric;
    if v_amount<=0 or v_from=v_to then raise exception 'Invalid reallocation move'; end if;
    insert into pg_temp.r2_moves values(v_from,v_to,v_envelope,v_amount);
  end loop;
  -- Prove the proposed matrix equals the complete target before any write.
  if exists(
    with deltas as (
      select from_account_id account_id,envelope_id,-amount amount from pg_temp.r2_moves union all
      select to_account_id,envelope_id,amount from pg_temp.r2_moves
    ), proposed as (
      select account_id,envelope_id,sum(amount)::numeric(14,2) amount from (
        select account_id,envelope_id,amount from public.envelope_account_current_positions where household_id=p_household_id
        union all select * from deltas
      ) q group by account_id,envelope_id having sum(amount)<>0
    ), target as (
      select account_id,envelope_id,target_amount amount from public.monthly_envelope_account_targets where household_id=p_household_id and month_start=date_trunc('month',p_month_start)::date and target_amount<>0
    )
    select 1 from proposed p full join target t using(account_id,envelope_id) where coalesce(p.amount,0)<>coalesce(t.amount,0)
  ) then raise exception 'Moves do not reach the current monthly targets'; end if;
  insert into public.envelope_account_position_batches(household_id,batch_kind,month_start,source_fingerprint,idempotency_key,created_by) values(p_household_id,'monthly_reallocation',date_trunc('month',p_month_start)::date,p_source_fingerprint,p_idempotency_key,auth.uid()) returning id into v_batch;
  for v_from,v_to,v_envelope,v_amount in select from_account_id,to_account_id,envelope_id,amount from pg_temp.r2_moves order by from_account_id,to_account_id,envelope_id loop
    select amount into v_available from public.envelope_account_current_positions where household_id=p_household_id and account_id=v_from and envelope_id=v_envelope for update;
    if coalesce(v_available,0)<v_amount then raise exception 'Reallocation exceeds current attributed position'; end if;
    v_move_key:=(substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),1,8)||'-'||substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),9,4)||'-4'||substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),14,3)||'-a'||substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),18,3)||'-'||substr(md5(p_idempotency_key::text||v_from::text||v_to::text||v_envelope::text),21,12))::uuid;
    v_event:=public.create_account_transfer_event(p_household_id,now(),'Régularisation mensuelle compte × enveloppe',v_amount,v_from,v_to,'Décision R2 confirmée',v_move_key);
    insert into public.envelope_account_position_entries(household_id,batch_id,financial_event_id,account_id,envelope_id,amount,created_by) values(p_household_id,v_batch,v_event,v_from,v_envelope,-v_amount,auth.uid()),(p_household_id,v_batch,v_event,v_to,v_envelope,v_amount,auth.uid());
    v_events:=v_events||jsonb_build_array(v_event);
  end loop;
  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then raise exception 'Reallocation invariant failed'; end if;
  return jsonb_build_object('batch_id',v_batch,'replayed',false,'financial_events',v_events,'snapshot',v_snapshot);
end $$;
revoke all on function public.execute_monthly_account_reallocation(uuid,date,text,jsonb,uuid) from public,anon;
grant execute on function public.execute_monthly_account_reallocation(uuid,date,text,jsonb,uuid) to authenticated;
