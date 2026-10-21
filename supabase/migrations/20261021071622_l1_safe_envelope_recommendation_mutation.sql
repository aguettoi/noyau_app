-- The historical mutator returns a full public.envelopes row, bypassing the
-- column-level privacy boundary. Preserve its validated write behavior as an
-- owner-only implementation detail and expose a void, audience-checked call.
revoke all on function public.set_envelope_recommendation(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;

create function public.set_envelope_recommendation_safe(
  p_envelope_id uuid, p_account_id uuid, p_payment_method_id uuid
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null or (
    p_account_id is not null
    and not private.can_discover_account(p_account_id, v_actor)
  ) then
    raise exception 'Recommendation account unavailable';
  end if;
  if p_payment_method_id is not null and not exists (
    select 1 from public.payment_methods pm
    where pm.id = p_payment_method_id
      and (pm.account_id is null
        or private.can_discover_account(pm.account_id, v_actor))
  ) then
    raise exception 'Recommendation payment method unavailable';
  end if;
  perform public.set_envelope_recommendation(
    p_envelope_id, p_account_id, p_payment_method_id
  );
end;
$$;

revoke all on function public.set_envelope_recommendation_safe(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.set_envelope_recommendation_safe(uuid,uuid,uuid)
  to authenticated;
