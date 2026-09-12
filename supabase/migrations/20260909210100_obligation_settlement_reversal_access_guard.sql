begin;

-- The settlement reversal RPC is SECURITY DEFINER but must still enforce the
-- caller's household membership before it locks or writes any financial row.
create or replace function public.assert_household_access(
  p_household_id uuid
) returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
end;
$$;

commit;
