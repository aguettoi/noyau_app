-- Read contract for Flutter: the same row shape for visible and hidden
-- accounts, with numeric fields null when the viewer lacks balance rights.
create function public.list_account_privacy_summaries_v2(p_household_id uuid)
returns table (
  id uuid, household_id uuid, name text, kind text,
  currency_code text, ownership_type text, is_system boolean,
  archived_at timestamptz, created_at timestamptz, updated_at timestamptz,
  visibility text, can_read_balance boolean, opening_balance numeric,
  holder_user_ids uuid[]
) language sql stable security definer set search_path = ''
as $$
  select a.id,a.household_id,a.name,a.kind,a.currency_code,
         a.ownership_type,a.is_system,a.archived_at,a.created_at,a.updated_at,
         private.account_visibility(a.id),
         private.can_read_account_balance(a.id,auth.uid()),
         case when private.can_read_account_balance(a.id,auth.uid())
              then a.opening_balance else null::numeric end,
         array(select h.user_id from public.account_holders h
               where h.account_id=a.id order by h.user_id)
  from public.accounts a
  where a.household_id=p_household_id
    and private.can_discover_account(a.id,auth.uid())
  order by a.created_at,a.id;
$$;
revoke all on function public.list_account_privacy_summaries_v2(uuid)
  from public,anon;
grant execute on function public.list_account_privacy_summaries_v2(uuid)
  to authenticated;
