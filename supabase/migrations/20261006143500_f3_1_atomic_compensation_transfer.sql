-- F3.1: atomic canonical transfer + compensation linkage and semantic replay.
begin;

create or replace function public.create_compensation_account_transfer(
 p_compensation_id uuid,p_source_account_id uuid,p_destination_account_id uuid,p_amount numeric,
 p_occurred_at timestamptz,p_description text,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_c public.member_compensation_balances%rowtype; v_event uuid;
begin
 perform 1 from public.member_compensations where id=p_compensation_id for update;
 select * into v_c from public.member_compensation_balances where id=p_compensation_id;
 if auth.uid() is null or v_c.id is null or auth.uid()<>v_c.debtor_user_id or not public.is_household_member(v_c.household_id) then raise exception 'Only debtor can perform compensation transfer'; end if;
 if p_amount<=0 or p_amount>v_c.remaining_amount-v_c.pending_receipt then raise exception 'Transfer exceeds amount still payable'; end if;
 v_event:=public.create_account_transfer_event(v_c.household_id,coalesce(p_occurred_at,now()),trim(p_description),p_amount,p_source_account_id,p_destination_account_id,'Règlement compensation '||v_c.id,p_idempotency_key);
 perform public.record_member_compensation_action(v_c.id,'transfer_declared',p_amount,v_event,'Virement canonique enregistré','[]'::jsonb,p_idempotency_key);
 return v_event;
end $$;

revoke all on function public.create_compensation_account_transfer(uuid,uuid,uuid,numeric,timestamptz,text,uuid) from public,anon;
grant execute on function public.create_compensation_account_transfer(uuid,uuid,uuid,numeric,timestamptz,text,uuid) to authenticated;
commit;
