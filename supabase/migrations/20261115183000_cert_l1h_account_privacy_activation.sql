-- CERT-L1H activates only the already-audited account privacy workflow.
-- Direct table writes remain forbidden; every mutation stays inside the
-- holder/household/unanimous-consent SECURITY DEFINER contracts.
revoke all on function public.request_account_privacy_change(uuid,text),
  public.decide_account_privacy_change(uuid,text),
  public.cancel_account_privacy_change(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.request_account_privacy_change(uuid,text),
  public.decide_account_privacy_change(uuid,text),
  public.cancel_account_privacy_change(uuid)
  to authenticated;

-- Account visibility and pending consent state are invalidated through the
-- expurgated household topic only. No account id, mode, holder, balance or
-- consent decision is published in Realtime.
create trigger cert_l1h_realtime_account_privacy_settings
after insert or update or delete on public.account_privacy_settings
for each row execute function private.emit_household_realtime_invalidation();

create trigger cert_l1h_realtime_account_privacy_requests
after insert or update or delete on public.account_privacy_requests
for each row execute function private.emit_household_realtime_invalidation();

create function private.emit_account_privacy_consent_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id uuid := case when tg_op = 'DELETE' then old.request_id
                            else new.request_id end;
  v_household_id uuid;
begin
  select r.household_id into v_household_id
  from public.account_privacy_requests r where r.id = v_request_id;
  if v_household_id is not null then
    insert into public.household_realtime_invalidations(
      household_id, topic, changed_at
    ) values (v_household_id, 'account_privacy_requests', now())
    on conflict (household_id, topic) do update
      set changed_at = excluded.changed_at,
          revision = public.household_realtime_invalidations.revision + 1;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.emit_account_privacy_consent_invalidation()
  from public, anon, authenticated, service_role;

create trigger cert_l1h_realtime_account_privacy_consents
after insert or delete on public.account_privacy_consents
for each row execute function private.emit_account_privacy_consent_invalidation();
