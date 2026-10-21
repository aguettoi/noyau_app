-- Close the first demonstrated indirect path: GL lines and their parent
-- transactions/events must not disclose a hidden account's amounts.
create function private.can_read_financial_line(
  p_account_id uuid,p_user_id uuid
) returns boolean language sql stable security definer set search_path = ''
as $$
  select p_account_id is null or exists (
    select 1 from public.accounts a where a.id=p_account_id
      and (a.is_system or
           private.can_read_account_balance(a.id,p_user_id))
  );
$$;

create function private.can_read_financial_transaction(
  p_transaction_id uuid,p_user_id uuid
) returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1 from public.financial_transactions t
    join public.household_members m on m.household_id=t.household_id
    where t.id=p_transaction_id and m.user_id=p_user_id
      and m.inactive_at is null
      and private.can_read_financial_line(t.source_account_id,p_user_id)
      and private.can_read_financial_line(t.destination_account_id,p_user_id)
      and not exists (
        select 1 from public.financial_transaction_lines l
        where l.transaction_id=t.id
          and not private.can_read_financial_line(l.account_id,p_user_id)
      )
  );
$$;

create function private.can_read_financial_event(
  p_event_id uuid,p_user_id uuid
) returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1 from public.financial_events e
    join public.household_members m on m.household_id=e.household_id
    where e.id=p_event_id and m.user_id=p_user_id
      and m.inactive_at is null
      and not exists (
        select 1 from public.financial_transactions t
        where t.event_id=e.id
          and not private.can_read_financial_transaction(t.id,p_user_id)
      )
      and not exists (
        select 1 from public.expense_payment_contexts c
        where c.event_id=e.id
          and not private.can_read_financial_line(c.actual_account_id,p_user_id)
      )
  );
$$;

revoke all on function private.can_read_financial_line(uuid,uuid),
  private.can_read_financial_transaction(uuid,uuid),
  private.can_read_financial_event(uuid,uuid) from public,anon;
grant execute on function private.can_read_financial_line(uuid,uuid),
  private.can_read_financial_transaction(uuid,uuid),
  private.can_read_financial_event(uuid,uuid) to authenticated;

create policy "l1 private GL lines" on public.financial_transaction_lines
  as restrictive for select to authenticated
  using (private.can_read_financial_transaction(
    transaction_id,(select auth.uid())));
create policy "l1 private GL transactions" on public.financial_transactions
  as restrictive for select to authenticated
  using (private.can_read_financial_transaction(id,(select auth.uid())));
create policy "l1 private financial events" on public.financial_events
  as restrictive for select to authenticated
  using (private.can_read_financial_event(id,(select auth.uid())));
create policy "l1 private envelope movements" on public.envelope_movements
  as restrictive for select to authenticated
  using ((event_id is null or private.can_read_financial_event(
    event_id,(select auth.uid())))
    and (financial_transaction_id is null or
      private.can_read_financial_transaction(
        financial_transaction_id,(select auth.uid()))));
create policy "l1 private payment context" on public.expense_payment_contexts
  as restrictive for select to authenticated
  using (private.can_read_financial_event(event_id,(select auth.uid())));
create policy "l1 private event attachments" on public.financial_event_attachments
  as restrictive for select to authenticated
  using (private.can_read_financial_event(
    financial_event_id,(select auth.uid())));
create policy "l1 private balance observations" on public.account_balance_observations
  as restrictive for select to authenticated
  using (private.can_read_account_balance(account_id,(select auth.uid())));
create policy "l1 private payment methods" on public.payment_methods
  as restrictive for select to authenticated
  using (private.can_discover_account(account_id,(select auth.uid())));
