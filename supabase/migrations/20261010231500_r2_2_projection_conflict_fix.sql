-- R2.2 partial-index conflict target fix.
create or replace function public.project_envelope_movement_to_account_position()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_account uuid; v_account_count integer; v_batch uuid; v_signed numeric(14,2);
begin
  if new.event_id is null or not exists(select 1 from public.envelope_account_position_batches where household_id=new.household_id) then return new; end if;
  select count(distinct l.account_id),(array_agg(distinct l.account_id))[1] into v_account_count,v_account
  from public.financial_transactions t join public.financial_transaction_lines l on l.transaction_id=t.id join public.accounts a on a.id=l.account_id
  where t.event_id=new.event_id and t.household_id=new.household_id and a.household_id=new.household_id and not a.is_system;
  if v_account_count<>1 then return new; end if;
  insert into public.envelope_account_position_batches(household_id,batch_kind,month_start,idempotency_key,note,created_by)
  values(new.household_id,'canonical_event',date_trunc('month',new.occurred_at)::date,new.event_id,'Projection automatique d''un événement canonique non ambigu',new.created_by)
  on conflict(household_id,idempotency_key) do nothing returning id into v_batch;
  if v_batch is null then select id into v_batch from public.envelope_account_position_batches where household_id=new.household_id and idempotency_key=new.event_id; end if;
  v_signed:=case new.direction when 'inflow' then new.amount else -new.amount end;
  insert into public.envelope_account_position_entries(household_id,batch_id,financial_event_id,source_envelope_movement_id,account_id,envelope_id,amount,created_by)
  values(new.household_id,v_batch,new.event_id,new.id,v_account,new.envelope_id,v_signed,new.created_by)
  on conflict(source_envelope_movement_id) where source_envelope_movement_id is not null do nothing;
  return new;
end $$;
revoke all on function public.project_envelope_movement_to_account_position() from public,anon,authenticated;
