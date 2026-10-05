-- F2A hardening after the initial additive migration.
-- Configuration only; no financial tables are written.

revoke all on table public.payment_methods from public, anon;
grant select on table public.payment_methods to authenticated;

drop policy if exists payment_methods_select_member on public.payment_methods;
drop policy if exists payment_methods_insert_member on public.payment_methods;
drop policy if exists payment_methods_update_member on public.payment_methods;

create policy payment_methods_select_member
on public.payment_methods for select to authenticated
using (exists (
  select 1 from public.household_members hm
  where hm.household_id = payment_methods.household_id
    and hm.user_id = (select auth.uid())
));

-- Mutations are deliberately RPC-only.

create or replace function public.update_payment_method(
  p_id uuid, p_account_id uuid, p_holder_user_id uuid,
  p_method_type text, p_label text, p_active boolean
) returns public.payment_methods
language plpgsql security definer set search_path = public, auth as $$
declare
  v public.payment_methods;
  v_household_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select pm.household_id into v_household_id
  from public.payment_methods pm
  where pm.id = p_id;
  if v_household_id is null or not exists (
    select 1 from public.household_members hm
    where hm.household_id = v_household_id and hm.user_id = auth.uid()
  ) then raise exception 'Payment method access denied'; end if;
  if p_method_type not in ('bank_card','cash','bank_transfer','other') then
    raise exception 'Invalid payment method type';
  end if;
  if nullif(trim(p_label), '') is null or char_length(trim(p_label)) > 80 then
    raise exception 'Payment method label must contain between 1 and 80 characters';
  end if;
  if p_account_id is not null and not exists (
    select 1 from public.accounts a
    where a.id = p_account_id and a.household_id = v_household_id
  ) then raise exception 'Account household mismatch'; end if;
  if p_holder_user_id is not null and not exists (
    select 1 from public.household_members hm
    where hm.household_id = v_household_id and hm.user_id = p_holder_user_id
  ) then raise exception 'Holder household mismatch'; end if;
  update public.payment_methods
  set account_id = p_account_id,
      holder_user_id = p_holder_user_id,
      method_type = p_method_type,
      label = trim(p_label),
      active = p_active,
      archived_at = case when p_active then null else coalesce(archived_at, now()) end
  where id = p_id
  returning * into v;
  return v;
end; $$;

revoke all on function public.update_payment_method(uuid,uuid,uuid,text,text,boolean) from public, anon;
grant execute on function public.update_payment_method(uuid,uuid,uuid,text,text,boolean) to authenticated;
