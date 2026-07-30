-- Phase 0: immutable, balanced financial ledger.
create table public.financial_transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  period_id uuid references public.budget_periods(id) on delete set null,
  type text not null check (type in ('allocation', 'expense', 'transfer', 'adjustment', 'recovery')),
  occurred_at timestamptz not null default now(),
  reason text not null check (char_length(trim(reason)) between 1 and 280),
  created_by uuid not null references auth.users(id),
  reversed_by uuid unique references public.financial_transactions(id),
  created_at timestamptz not null default now()
);

create table public.financial_transaction_lines (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.financial_transactions(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete restrict,
  envelope_id uuid references public.envelopes(id) on delete restrict,
  member_id uuid references auth.users(id) on delete set null,
  amount numeric(14, 2) not null check (amount <> 0),
  created_at timestamptz not null default now()
);

-- An append-only audit trail for the new ledger.  The source application will
-- require a short reason on every transaction; this table keeps that context
-- even when a transaction is later reversed.
create table public.financial_audit_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  transaction_id uuid not null references public.financial_transactions(id) on delete cascade,
  action text not null check (action in ('created', 'reversed')),
  reason text not null,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index financial_transactions_household_date_idx on public.financial_transactions(household_id, occurred_at desc);
create index financial_transaction_lines_transaction_idx on public.financial_transaction_lines(transaction_id);
create index financial_transaction_lines_account_idx on public.financial_transaction_lines(account_id);
create index financial_audit_events_transaction_idx on public.financial_audit_events(transaction_id, created_at desc);

alter table public.financial_transactions enable row level security;
alter table public.financial_transaction_lines enable row level security;
alter table public.financial_audit_events enable row level security;

create policy "members read financial transactions" on public.financial_transactions for select
using (public.is_household_member(household_id));
create policy "members read financial lines" on public.financial_transaction_lines for select
using (exists (
  select 1 from public.financial_transactions transactions
  where transactions.id = transaction_id
    and public.is_household_member(transactions.household_id)
));

create policy "members read financial audit events" on public.financial_audit_events for select
using (public.is_household_member(household_id));

-- The client must never insert ledger rows directly.  This RPC validates the
-- entire double-entry operation before writing any row, and therefore avoids
-- transient unbalanced states caused by line-by-line writes.
create or replace function public.create_financial_transaction(
  p_household_id uuid,
  p_period_id uuid,
  p_type text,
  p_occurred_at timestamptz,
  p_reason text,
  p_lines jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transaction_id uuid;
  v_line jsonb;
  v_total numeric(14, 2) := 0;
  v_account_household_id uuid;
  v_envelope_household_id uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;

  if p_type not in ('allocation', 'expense', 'transfer', 'adjustment', 'recovery') then
    raise exception 'Unsupported transaction type';
  end if;

  if char_length(trim(coalesce(p_reason, ''))) not between 1 and 280 then
    raise exception 'A reason between 1 and 280 characters is required';
  end if;

  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'At least two ledger lines are required';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if coalesce(v_line ->> 'account_id', '') = ''
       or coalesce(v_line ->> 'amount', '') = '' then
      raise exception 'Each ledger line requires an account and amount';
    end if;

    select household_id into v_account_household_id
    from public.accounts
    where id = (v_line ->> 'account_id')::uuid;
    if v_account_household_id is null or v_account_household_id <> p_household_id then
      raise exception 'Account does not belong to household';
    end if;

    if nullif(v_line ->> 'envelope_id', '') is not null then
      select household_id into v_envelope_household_id
      from public.envelopes
      where id = (v_line ->> 'envelope_id')::uuid;
      if v_envelope_household_id is null or v_envelope_household_id <> p_household_id then
        raise exception 'Envelope does not belong to household';
      end if;
    end if;

    v_total := v_total + (v_line ->> 'amount')::numeric(14, 2);
  end loop;

  if v_total <> 0 then
    raise exception 'Ledger transaction must balance to zero';
  end if;

  insert into public.financial_transactions (
    household_id, period_id, type, occurred_at, reason, created_by
  ) values (
    p_household_id, p_period_id, p_type, coalesce(p_occurred_at, now()), trim(p_reason), auth.uid()
  ) returning id into v_transaction_id;

  insert into public.financial_transaction_lines (
    transaction_id, account_id, envelope_id, member_id, amount
  )
  select
    v_transaction_id,
    (value ->> 'account_id')::uuid,
    nullif(value ->> 'envelope_id', '')::uuid,
    nullif(value ->> 'member_id', '')::uuid,
    (value ->> 'amount')::numeric(14, 2)
  from jsonb_array_elements(p_lines);

  insert into public.financial_audit_events (
    household_id, transaction_id, action, reason, actor_id
  ) values (
    p_household_id, v_transaction_id, 'created', trim(p_reason), auth.uid()
  );

  return v_transaction_id;
end;
$$;

grant execute on function public.create_financial_transaction(uuid, uuid, text, timestamptz, text, jsonb) to authenticated;
