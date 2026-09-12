-- Restore the ledger-only counterpart used by direct budget allocations.
-- This is distinct from the system envelope with system_code = 'to_allocate'.
begin;

create or replace function public.ensure_financial_event_system_account(
  p_household_id uuid, p_code text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_is_system boolean;
  v_name text := case p_code
    when 'expense' then 'Système — Dépenses'
    when 'income' then 'Système — Revenus'
    when 'debt' then 'Système — Dettes'
    when 'receivable' then 'Système — Créances'
    when 'recovery' then 'Système — Recouvrements'
    when 'to_allocate' then 'Système — À répartir'
    when 'debt_writeoff_gain' then 'Système — Gains d’abandon de dettes'
    when 'receivable_loss' then 'Système — Pertes sur créances'
    else null
  end;
begin
  if v_name is null then
    raise exception 'Unsupported FinancialEvent counterpart';
  end if;

  select id, is_system into v_account_id, v_is_system
  from public.accounts
  where household_id = p_household_id and name = v_name;

  if found then
    if not v_is_system then
      raise exception 'A reserved FinancialEvent account name is already used';
    end if;
    return v_account_id;
  end if;

  insert into public.accounts(household_id, name, kind, is_system)
  values (p_household_id, v_name, 'ledger', true)
  returning id into v_account_id;
  return v_account_id;
end;
$$;

revoke all on function public.ensure_financial_event_system_account(uuid, text)
  from public, anon;
grant execute on function public.ensure_financial_event_system_account(uuid, text)
  to authenticated;

commit;
