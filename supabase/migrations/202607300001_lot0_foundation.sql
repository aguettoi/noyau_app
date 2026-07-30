-- Noyau, Lot 0: durable financial and household foundation.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  locale text not null default 'fr_MA',
  timezone text not null default 'Africa/Casablanca',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  kind text not null check (kind in ('bank', 'cash', 'savings', 'loan')),
  currency_code text not null default 'MAD' check (currency_code ~ '^[A-Z]{3}$'),
  opening_balance numeric(14, 2) not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, name)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  icon text,
  color text,
  created_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (household_id, name)
);

alter table public.envelopes
  add column if not exists category_id uuid references public.categories(id) on delete set null,
  add column if not exists target_amount numeric(14, 2),
  add column if not exists updated_at timestamptz not null default now();

alter table public.transactions
  add column if not exists account_id uuid references public.accounts(id) on delete restrict,
  add column if not exists transfer_group_id uuid,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create table public.budget_periods (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  starts_on date not null,
  ends_on date not null,
  status text not null default 'draft' check (status in ('draft', 'active', 'closed')),
  created_at timestamptz not null default now(),
  unique (household_id, starts_on),
  check (ends_on >= starts_on)
);

create table public.budget_allocations (
  id uuid primary key default gen_random_uuid(),
  budget_period_id uuid not null references public.budget_periods(id) on delete cascade,
  envelope_id uuid not null references public.envelopes(id) on delete restrict,
  planned_amount numeric(14, 2) not null check (planned_amount >= 0),
  source text not null check (source in ('income', 'surplus', 'manual', 'carry_over')),
  created_at timestamptz not null default now(),
  unique (budget_period_id, envelope_id, source)
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  action text not null check (action in ('insert', 'update', 'delete')),
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now()
);

create index accounts_household_active_idx on public.accounts(household_id) where archived_at is null;
create index categories_household_active_idx on public.categories(household_id) where archived_at is null;
create index envelopes_household_active_idx on public.envelopes(household_id) where archived_at is null;
create index transactions_household_account_date_idx on public.transactions(household_id, account_id, occurred_at desc) where deleted_at is null;
create index transactions_transfer_group_idx on public.transactions(transfer_group_id) where transfer_group_id is not null;
create index audit_events_household_created_idx on public.audit_events(household_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger accounts_set_updated_at before update on public.accounts
for each row execute function public.set_updated_at();
create trigger envelopes_set_updated_at before update on public.envelopes
for each row execute function public.set_updated_at();
create trigger transactions_set_updated_at before update on public.transactions
for each row execute function public.set_updated_at();

create or replace function public.write_audit_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  record_data jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  insert into public.audit_events (
    household_id, actor_id, entity_type, entity_id, action, before_state, after_state
  ) values (
    (record_data ->> 'household_id')::uuid,
    auth.uid(),
    tg_table_name,
    (record_data ->> 'id')::uuid,
    lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;

create trigger envelopes_audit after insert or update or delete on public.envelopes
for each row execute function public.write_audit_event();
create trigger transactions_audit after insert or update or delete on public.transactions
for each row execute function public.write_audit_event();

alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.budget_periods enable row level security;
alter table public.budget_allocations enable row level security;
alter table public.audit_events enable row level security;

create policy "users read own profile" on public.profiles
for select using (id = auth.uid());
create policy "users create own profile" on public.profiles
for insert with check (id = auth.uid());
create policy "users update own profile" on public.profiles
for update using (id = auth.uid()) with check (id = auth.uid());
create policy "members manage accounts" on public.accounts for all
using (public.is_household_member(household_id))
with check (public.is_household_member(household_id));
create policy "members manage categories" on public.categories for all
using (public.is_household_member(household_id))
with check (public.is_household_member(household_id));
create policy "members manage budget periods" on public.budget_periods for all
using (public.is_household_member(household_id))
with check (public.is_household_member(household_id));
create policy "members manage allocations" on public.budget_allocations for all
using (exists (
  select 1 from public.budget_periods periods
  where periods.id = budget_period_id
    and public.is_household_member(periods.household_id)
))
with check (exists (
  select 1 from public.budget_periods periods
  where periods.id = budget_period_id
    and public.is_household_member(periods.household_id)
));
create policy "members read audit events" on public.audit_events for select
using (public.is_household_member(household_id));
