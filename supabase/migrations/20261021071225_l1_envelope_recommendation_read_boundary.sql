-- L1: a shared envelope must remain readable, but its physical account
-- recommendation must not disclose a private account to a non-holder.
-- Row-level security alone cannot redact individual columns.
revoke select on public.envelopes from anon, authenticated;
grant select (
  id, household_id, name, color, archived_at, created_at, category_id,
  target_amount, updated_at, is_system, system_code, notes,
  import_session_id, recommendation_kind
) on public.envelopes to authenticated;

-- No client consumes this raw audit table. Its previous/current account ids
-- and free-form definitions can disclose a private account.
revoke all on public.envelope_recommendation_events from anon, authenticated;

create function public.list_household_envelopes_safe(p_household_id uuid)
returns setof jsonb
language sql stable security definer set search_path = ''
as $$
  select
    (to_jsonb(e) - 'recommended_account_id'
                 - 'recommended_payment_method_id'
                 - 'recommendation_definition')
    || jsonb_build_object(
      'recommended_account_id',
        case when e.recommended_account_id is not null
               and private.can_discover_account(
                 e.recommended_account_id, auth.uid()
               ) then to_jsonb(e.recommended_account_id)
             else 'null'::jsonb end,
      'recommended_payment_method_id',
        case when e.recommended_payment_method_id is not null
               and exists (
                 select 1 from public.payment_methods pm
                 where pm.id = e.recommended_payment_method_id
                   and private.can_discover_account(pm.account_id, auth.uid())
               ) then to_jsonb(e.recommended_payment_method_id)
             else 'null'::jsonb end,
      -- Definitions may contain historical account names, IDs or amounts.
      -- They remain server-side metadata until a field-level audience contract
      -- exists; the current Flutter consumer does not use this JSON.
      'recommendation_definition', '{}'::jsonb
    )
  from public.envelopes e
  where e.household_id = p_household_id
    and public.is_active_household_member(p_household_id, auth.uid())
  order by e.name, e.id;
$$;

revoke all on function public.list_household_envelopes_safe(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.list_household_envelopes_safe(uuid)
  to authenticated;
