-- A household member must not use a private account they cannot discover as
-- a source or destination in the shared canonical event engine. This guard
-- is reused by the eleven financial RPCs that validate ordinary accounts.
create or replace function public.assert_financial_event_ordinary_account(
  p_household_id uuid, p_account_id uuid
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_account_id is null or not exists (
    select 1 from public.accounts
    where id = p_account_id and household_id = p_household_id and not is_system
  ) then
    raise exception 'An ordinary account of the household is required';
  end if;

  -- Server-owned maintenance may have no JWT. Client requests always do.
  if (select auth.uid()) is not null and not private.can_discover_account(
    p_account_id, (select auth.uid())
  ) then
    raise exception 'Account is not available to this member';
  end if;
end;
$$;
