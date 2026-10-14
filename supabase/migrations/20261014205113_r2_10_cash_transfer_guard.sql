-- R2.10 hardening: cash-to-cash is an inventory operation, never a bank
-- transfer. The trigger runs in the same atomic transaction as the canonical
-- event, so a rejection rolls the whole execution back.
begin;

create or replace function public.guard_r2_10_cash_to_cash_transfer()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_from_kind text; v_to_kind text;
begin
  select kind into v_from_kind from public.accounts where id=new.from_account_id;
  select kind into v_to_kind from public.accounts where id=new.to_account_id;
  if v_from_kind='cash' and v_to_kind='cash' then
    raise exception 'Cash-to-cash reallocation requires an inventory decision, not an account transfer';
  end if;
  return new;
end $$;

revoke all on function public.guard_r2_10_cash_to_cash_transfer() from public,anon,authenticated;

create trigger guard_r2_10_cash_to_cash_transfer
before insert on public.envelope_account_physical_transfers
for each row execute function public.guard_r2_10_cash_to_cash_transfer();

commit;
