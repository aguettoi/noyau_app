-- The common GL writer must not accept a private account from a member who
-- cannot discover it, including RPCs that do not call the ordinary-account
-- validator before writing (notably income). System accounts are exempt.
create or replace function public.insert_financial_event_ledger_transaction(
  p_household_id uuid, p_event_id uuid, p_type text,
  p_occurred_at timestamptz, p_description text, p_amount numeric,
  p_source_account_id uuid, p_destination_account_id uuid,
  p_debit_account_id uuid, p_credit_account_id uuid, p_notes text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_transaction_id uuid;
  v_occurred_at timestamptz := coalesce(p_occurred_at, now());
  v_account_id uuid;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'A positive amount is required';
  end if;

  if (select auth.uid()) is not null then
    for v_account_id in
      select distinct id from unnest(array[
        p_source_account_id,p_destination_account_id,
        p_debit_account_id,p_credit_account_id
      ]) as ids(id) where id is not null
    loop
      if exists (
        select 1 from public.accounts a
        where a.id=v_account_id and a.household_id=p_household_id
          and not a.is_system
      ) and not private.can_discover_account(
        v_account_id,(select auth.uid())
      ) then
        raise exception 'Account is not available to this member';
      end if;
    end loop;
  end if;

  insert into public.financial_transactions(
    household_id,event_id,type,occurred_at,reason,description,amount,
    currency_code,source_account_id,destination_account_id,notes,created_by,
    validated_at
  ) values (
    p_household_id,p_event_id,p_type,v_occurred_at,trim(p_description),
    trim(p_description),p_amount,'MAD',p_source_account_id,
    p_destination_account_id,nullif(trim(coalesce(p_notes,'')),''),
    auth.uid(),now()
  ) returning id into v_transaction_id;

  insert into public.financial_transaction_lines(
    transaction_id,account_id,amount,debit,credit,occurred_at
  ) values
    (v_transaction_id,p_debit_account_id,p_amount,p_amount,0,v_occurred_at),
    (v_transaction_id,p_credit_account_id,-p_amount,0,p_amount,v_occurred_at);
  insert into public.financial_audit_events(
    household_id,transaction_id,action,reason,actor_id
  ) values (
    p_household_id,v_transaction_id,'created',trim(p_description),auth.uid()
  );
  return v_transaction_id;
end;
$$;
