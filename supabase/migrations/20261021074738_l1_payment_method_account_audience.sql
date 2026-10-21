-- A SECURITY DEFINER payment-method RPC could attach a method to a private
-- account not discoverable by its caller. Guard the write at the table edge
-- so both create and update paths share one rule.
create or replace function private.enforce_payment_method_account_audience()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is not null and new.account_id is not null
     and not private.can_discover_account(
       new.account_id,(select auth.uid())
     ) then
    raise exception 'Account is not available to this member';
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_payment_method_account_audience()
  from public, anon, authenticated;
drop trigger if exists l1_payment_method_account_audience
  on public.payment_methods;
create trigger l1_payment_method_account_audience
before insert or update on public.payment_methods
for each row execute function private.enforce_payment_method_account_audience();
