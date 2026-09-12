-- Sprint 2.1: additive evolution of the historical signed-line ledger into
-- explicit debit/credit postings. Run the complete file as a single script.
-- Every statement below is transactional: a new failure rolls back this run.

begin;

alter table public.accounts
  add column if not exists is_system boolean not null default false;

alter table public.accounts
  drop constraint if exists accounts_kind_check;
alter table public.accounts
  add constraint accounts_kind_check
  check (kind in ('bank', 'cash', 'savings', 'loan', 'ledger'));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.accounts'::regclass
      and conname = 'accounts_system_kind_check'
  ) then
    alter table public.accounts
      add constraint accounts_system_kind_check
      check (not is_system or kind = 'ledger');
  end if;
end;
$$;

-- Sprint 2 posts accounts through audited SECURITY DEFINER RPCs. Members may
-- read ordinary accounts, but cannot alter balances or system accounts through
-- a direct table request.
drop policy if exists "members manage accounts" on public.accounts;
drop policy if exists "members read ordinary accounts" on public.accounts;
create policy "members read ordinary accounts" on public.accounts for select
using (public.is_household_member(household_id) and not is_system);

alter table public.financial_transactions
  add column if not exists currency_code text not null default 'MAD'
    check (currency_code ~ '^[A-Z]{3}$'),
  add column if not exists source_account_id uuid references public.accounts(id) on delete restrict,
  add column if not exists destination_account_id uuid references public.accounts(id) on delete restrict,
  add column if not exists category_id uuid references public.categories(id) on delete restrict,
  add column if not exists description text,
  add column if not exists amount numeric(14, 2),
  add column if not exists notes text,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists archived_at timestamptz,
  add column if not exists validated_at timestamptz;

update public.financial_transactions transactions
set description = transactions.reason,
    amount = coalesce(transactions.amount, 0),
    validated_at = transactions.created_at
where transactions.description is null
   or transactions.amount is null
   or transactions.validated_at is null;

alter table public.financial_transactions
  alter column description set not null,
  alter column amount set not null,
  alter column validated_at set not null;

alter table public.financial_transactions
  drop constraint if exists financial_transactions_type_check;
alter table public.financial_transactions
  add constraint financial_transactions_type_check
  check (type in (
    'allocation', 'expense', 'transfer', 'adjustment', 'recovery',
    'income', 'opening_balance', 'correction'
  ));

alter table public.financial_transaction_lines
  add column if not exists debit numeric(14, 2) not null default 0,
  add column if not exists credit numeric(14, 2) not null default 0,
  add column if not exists occurred_at timestamptz;

-- Convert only untouched historical signed rows. `lines.amount` is essential:
-- `transactions.amount` is the new transaction summary and must never be used
-- to derive a line posting.
update public.financial_transaction_lines lines
set debit = case when lines.amount > 0 then lines.amount else 0 end,
    credit = case when lines.amount < 0 then -lines.amount else 0 end
where lines.debit = 0
  and lines.credit = 0
  and lines.amount <> 0;

update public.financial_transaction_lines lines
set occurred_at = transactions.occurred_at
from public.financial_transactions transactions
where transactions.id = lines.transaction_id
  and lines.occurred_at is null;

-- Never silently repair malformed pre-existing postings.
do $$
begin
  if exists (
    select 1
    from public.financial_transaction_lines lines
    where lines.debit < 0
       or lines.credit < 0
       or (lines.debit > 0 and lines.credit > 0)
       or (lines.debit = 0 and lines.credit = 0)
  ) then
    raise exception 'Historical ledger lines cannot be converted safely';
  end if;
end;
$$;

alter table public.financial_transaction_lines
  alter column occurred_at set not null;

-- Keep the historical RPC operational during the additive migration.  Its
-- signed input remains the public compatibility contract; debit and credit
-- are derived once, atomically, when its lines are written.
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
  v_line_amount numeric(14, 2);
  v_total numeric(14, 2) := 0;
  v_debit_total numeric(14, 2) := 0;
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

    v_line_amount := (v_line ->> 'amount')::numeric(14, 2);
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

    v_total := v_total + v_line_amount;
    if v_line_amount > 0 then
      v_debit_total := v_debit_total + v_line_amount;
    end if;
  end loop;

  if v_total <> 0 then
    raise exception 'Ledger transaction must balance to zero';
  end if;

  insert into public.financial_transactions (
    household_id, period_id, type, occurred_at, reason, description, amount,
    currency_code, created_by, validated_at
  ) values (
    p_household_id, p_period_id, p_type, coalesce(p_occurred_at, now()),
    trim(p_reason), trim(p_reason), v_debit_total, 'MAD', auth.uid(), now()
  ) returning id into v_transaction_id;

  insert into public.financial_transaction_lines (
    transaction_id, account_id, envelope_id, member_id, amount, debit, credit,
    occurred_at
  )
  select
    v_transaction_id,
    (value ->> 'account_id')::uuid,
    nullif(value ->> 'envelope_id', '')::uuid,
    nullif(value ->> 'member_id', '')::uuid,
    (value ->> 'amount')::numeric(14, 2),
    case when (value ->> 'amount')::numeric(14, 2) > 0
      then (value ->> 'amount')::numeric(14, 2) else 0 end,
    case when (value ->> 'amount')::numeric(14, 2) < 0
      then -(value ->> 'amount')::numeric(14, 2) else 0 end,
    coalesce(p_occurred_at, now())
  from jsonb_array_elements(p_lines);

  insert into public.financial_audit_events (
    household_id, transaction_id, action, reason, actor_id
  ) values (
    p_household_id, v_transaction_id, 'created', trim(p_reason), auth.uid()
  );

  return v_transaction_id;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.financial_transaction_lines'::regclass
      and conname = 'financial_transaction_lines_debit_credit_check'
  ) then
    alter table public.financial_transaction_lines
      add constraint financial_transaction_lines_debit_credit_check
      check (
        debit >= 0
        and credit >= 0
        and ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
      );
  end if;
end;
$$;

-- The summary is derived from lines for legacy transactions and is safe to
-- rerun. It does not affect accounts.opening_balance.
update public.financial_transactions transactions
set amount = coalesce((
  select sum(lines.debit)
  from public.financial_transaction_lines lines
  where lines.transaction_id = transactions.id
), 0);

create index if not exists financial_transaction_lines_account_occurred_idx
  on public.financial_transaction_lines(account_id, occurred_at desc);
create index if not exists financial_transactions_household_active_date_idx
  on public.financial_transactions(household_id, occurred_at desc)
  where archived_at is null;

create or replace view public.account_ledger_balances
with (security_invoker = true)
as
select
  accounts.id as account_id,
  accounts.household_id,
  accounts.opening_balance,
  coalesce(sum(lines.debit - lines.credit), 0)::numeric(14, 2) as ledger_balance,
  (
    accounts.opening_balance
    + case
      -- A positive loan opening balance is an outstanding liability.
      when accounts.kind = 'loan' then coalesce(sum(lines.credit - lines.debit), 0)
      else coalesce(sum(lines.debit - lines.credit), 0)
    end
  )::numeric(14, 2) as theoretical_balance
from public.accounts accounts
left join public.financial_transaction_lines lines on lines.account_id = accounts.id
group by accounts.id, accounts.household_id, accounts.opening_balance, accounts.kind;

create or replace function public.assert_financial_transaction_balanced()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_transaction_id uuid;
  v_debits numeric(14, 2);
  v_credits numeric(14, 2);
begin
  if tg_op = 'DELETE' then
    v_transaction_id := old.transaction_id;
  else
    v_transaction_id := new.transaction_id;
  end if;
  select coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_debits, v_credits
  from public.financial_transaction_lines
  where transaction_id = v_transaction_id;
  if v_debits <> v_credits or v_debits = 0 then
    raise exception 'A ledger transaction must have balanced non-zero debit and credit totals';
  end if;
  return null;
end;
$$;

drop trigger if exists financial_transaction_lines_balanced
  on public.financial_transaction_lines;
create constraint trigger financial_transaction_lines_balanced
after insert or update or delete on public.financial_transaction_lines
deferrable initially deferred
for each row execute function public.assert_financial_transaction_balanced();

-- Provides the required counterparts for a complete double-entry system while
-- keeping them hidden from all ordinary-account queries.
create or replace function public.ensure_household_ledger_system_account(
  p_household_id uuid,
  p_code text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := case p_code
    when 'expense' then 'Système — Dépenses'
    when 'income' then 'Système — Revenus'
    when 'adjustment' then 'Système — Ajustements'
    when 'opening_balance' then 'Système — Soldes d’ouverture'
    else null
  end;
  v_account_id uuid;
  v_is_system boolean;
begin
  if v_name is null then raise exception 'Unsupported ledger counterpart'; end if;

  select id, is_system into v_account_id, v_is_system
  from public.accounts
  where household_id = p_household_id and name = v_name;
  if found then
    if not v_is_system then
      raise exception 'A reserved ledger account name is already used';
    end if;
    return v_account_id;
  end if;

  insert into public.accounts(household_id, name, kind, is_system)
  values (p_household_id, v_name, 'ledger', true)
  returning id into v_account_id;
  return v_account_id;
end;
$$;

create or replace function public.create_ledger_transaction(
  p_household_id uuid,
  p_type text,
  p_occurred_at timestamptz,
  p_description text,
  p_amount numeric,
  p_source_account_id uuid default null,
  p_destination_account_id uuid default null,
  p_category_id uuid default null,
  p_notes text default null,
  p_direction text default 'increase'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transaction_id uuid;
  v_counterparty_account_id uuid;
  v_account_id uuid;
  v_debit_account_id uuid;
  v_credit_account_id uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_type not in ('expense', 'income', 'transfer', 'adjustment', 'opening_balance', 'correction') then
    raise exception 'Unsupported transaction type';
  end if;
  if char_length(trim(coalesce(p_description, ''))) not between 1 and 280 then
    raise exception 'A description between 1 and 280 characters is required';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'A positive amount is required';
  end if;
  if p_direction not in ('increase', 'decrease') then
    raise exception 'Unsupported balance direction';
  end if;

  foreach v_account_id in array array[p_source_account_id, p_destination_account_id] loop
    if v_account_id is not null and not exists (
      select 1 from public.accounts
      where id = v_account_id and household_id = p_household_id and not is_system
    ) then
      raise exception 'Account does not belong to household';
    end if;
  end loop;
  if p_category_id is not null and not exists (
    select 1 from public.categories where id = p_category_id and household_id = p_household_id
  ) then
    raise exception 'Category does not belong to household';
  end if;

  if p_type = 'expense' then
    if p_source_account_id is null or p_destination_account_id is not null then
      raise exception 'An expense requires one payment account';
    end if;
    v_counterparty_account_id := public.ensure_household_ledger_system_account(p_household_id, 'expense');
    v_debit_account_id := v_counterparty_account_id;
    v_credit_account_id := p_source_account_id;
  elsif p_type = 'income' then
    if p_destination_account_id is null or p_source_account_id is not null then
      raise exception 'An income requires one receiving account';
    end if;
    v_counterparty_account_id := public.ensure_household_ledger_system_account(p_household_id, 'income');
    v_debit_account_id := p_destination_account_id;
    v_credit_account_id := v_counterparty_account_id;
  elsif p_type = 'transfer' then
    if p_source_account_id is null or p_destination_account_id is null or p_source_account_id = p_destination_account_id then
      raise exception 'A transfer requires two different accounts';
    end if;
    v_debit_account_id := p_destination_account_id;
    v_credit_account_id := p_source_account_id;
  else
    if p_source_account_id is null or p_destination_account_id is not null then
      raise exception 'This transaction requires one account';
    end if;
    v_counterparty_account_id := public.ensure_household_ledger_system_account(
      p_household_id,
      case when p_type = 'opening_balance' then 'opening_balance' else 'adjustment' end
    );
    if p_direction = 'increase' then
      v_debit_account_id := p_source_account_id;
      v_credit_account_id := v_counterparty_account_id;
    else
      v_debit_account_id := v_counterparty_account_id;
      v_credit_account_id := p_source_account_id;
    end if;
  end if;

  insert into public.financial_transactions(
    household_id, type, occurred_at, reason, description, amount, currency_code,
    source_account_id, destination_account_id, category_id, notes, created_by, validated_at
  ) values (
    p_household_id, p_type, coalesce(p_occurred_at, now()), trim(p_description), trim(p_description),
    p_amount, 'MAD', p_source_account_id, p_destination_account_id, p_category_id,
    nullif(trim(coalesce(p_notes, '')), ''), auth.uid(), now()
  ) returning id into v_transaction_id;

  insert into public.financial_transaction_lines(
    transaction_id, account_id, amount, debit, credit, occurred_at
  ) values
    (v_transaction_id, v_debit_account_id, p_amount, p_amount, 0, coalesce(p_occurred_at, now())),
    (v_transaction_id, v_credit_account_id, -p_amount, 0, p_amount, coalesce(p_occurred_at, now()));

  insert into public.financial_audit_events(household_id, transaction_id, action, reason, actor_id)
  values (p_household_id, v_transaction_id, 'created', trim(p_description), auth.uid());
  return v_transaction_id;
end;
$$;

grant select on public.account_ledger_balances to authenticated;
revoke all on function public.create_financial_transaction(
  uuid, uuid, text, timestamptz, text, jsonb
) from public, anon;
grant execute on function public.create_financial_transaction(
  uuid, uuid, text, timestamptz, text, jsonb
) to authenticated;
revoke all on function public.ensure_household_ledger_system_account(uuid, text)
  from public, anon;
revoke all on function public.create_ledger_transaction(
  uuid, text, timestamptz, text, numeric, uuid, uuid, uuid, text, text
) from public, anon;
grant execute on function public.create_ledger_transaction(
  uuid, text, timestamptz, text, numeric, uuid, uuid, uuid, text, text
) to authenticated;

commit;
