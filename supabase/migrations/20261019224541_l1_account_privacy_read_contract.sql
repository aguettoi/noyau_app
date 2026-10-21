-- L1 additive follow-up: holders need a safe read contract for pending
-- unanimous-consent requests. No client can write these tables directly.
grant execute on function private.account_is_holder(uuid,uuid) to authenticated;
grant select on public.account_privacy_settings,
  public.account_privacy_requests, public.account_privacy_consents,
  public.account_privacy_audit to authenticated;

create policy "l1 holders read privacy settings"
  on public.account_privacy_settings for select to authenticated
  using (private.account_is_holder(account_id, (select auth.uid())));

create policy "l1 holders read privacy requests"
  on public.account_privacy_requests for select to authenticated
  using (private.account_is_holder(account_id, (select auth.uid())));

create policy "l1 holders read privacy consents"
  on public.account_privacy_consents for select to authenticated
  using (exists (
    select 1 from public.account_privacy_requests r
    where r.id=request_id and
      private.account_is_holder(r.account_id, (select auth.uid()))
  ));

create policy "l1 holders read privacy audit"
  on public.account_privacy_audit for select to authenticated
  using (private.account_is_holder(account_id, (select auth.uid())));

create function public.cancel_account_privacy_change(p_request_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_request public.account_privacy_requests%rowtype;
  v_actor uuid := auth.uid();
begin
  select * into v_request from public.account_privacy_requests
    where id=p_request_id for update;
  if v_actor is null or not found or v_request.status <> 'pending'
     or v_request.requested_by <> v_actor
     or not private.account_is_holder(v_request.account_id,v_actor) then
    raise exception 'Account privacy cancellation denied';
  end if;
  update public.account_privacy_requests
    set status='cancelled',resolved_at=now() where id=p_request_id;
  insert into public.account_privacy_audit(
    account_id,household_id,request_id,actor_id,action,
    from_visibility,to_visibility
  ) values (v_request.account_id,v_request.household_id,p_request_id,v_actor,
            'cancelled',private.account_visibility(v_request.account_id),
            v_request.requested_visibility);
end;
$$;
revoke all on function public.cancel_account_privacy_change(uuid)
  from public, anon;
grant execute on function public.cancel_account_privacy_change(uuid)
  to authenticated;
