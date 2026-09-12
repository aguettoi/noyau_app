-- Financial events, soft budget provenance and obligations. Do not apply automatically.
begin;

create table if not exists public.financial_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  event_type text not null check (event_type in (
    'cash_expense', 'debt_expense', 'debt_settlement',
    'income_receivable', 'receivable_settlement',
    'recovery_receivable', 'recovery_settlement', 'budget_allocation',
    'account_transfer', 'envelope_transfer'
  )),
  description text not null check (char_length(trim(description)) between 1 and 280),
  occurred_at timestamptz not null,
  notes text,
  idempotency_key uuid,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (id, household_id),
  unique nulls not distinct (household_id, idempotency_key),
  foreign key (household_id, created_by)
    references public.household_members(household_id, user_id) on delete restrict
);

alter table public.financial_transactions add column if not exists event_id uuid;
alter table public.envelope_movements add column if not exists event_id uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'financial_transactions_event_household_fk') then
    alter table public.financial_transactions add constraint financial_transactions_event_household_fk
      foreign key (event_id, household_id) references public.financial_events(id, household_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'envelope_movements_event_household_fk') then
    alter table public.envelope_movements add constraint envelope_movements_event_household_fk
      foreign key (event_id, household_id) references public.financial_events(id, household_id) on delete restrict;
  end if;
end;
$$;

create table if not exists public.obligations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  obligation_kind text not null check (obligation_kind in ('debt', 'receivable')),
  receivable_kind text check (receivable_kind in ('income', 'recovery') or receivable_kind is null),
  origin_event_id uuid not null,
  origin_transaction_id uuid not null,
  origin_envelope_id uuid,
  recovery_source_event_id uuid,
  recovery_source_envelope_id uuid,
  initial_amount numeric(14, 2) not null check (initial_amount > 0),
  counterparty_name text,
  description text not null check (char_length(trim(description)) between 1 and 280),
  due_at date,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (id, household_id),
  foreign key (origin_event_id, household_id)
    references public.financial_events(id, household_id) on delete restrict,
  foreign key (origin_transaction_id, household_id)
    references public.financial_transactions(id, household_id) on delete restrict,
  foreign key (origin_envelope_id, household_id)
    references public.envelopes(id, household_id) on delete restrict,
  foreign key (recovery_source_event_id, household_id)
    references public.financial_events(id, household_id) on delete restrict,
  foreign key (recovery_source_envelope_id, household_id)
    references public.envelopes(id, household_id) on delete restrict,
  foreign key (household_id, created_by)
    references public.household_members(household_id, user_id) on delete restrict,
  check ((obligation_kind = 'receivable') = (receivable_kind is not null)),
  check (
    receivable_kind <> 'recovery'
    or recovery_source_event_id is not null
  )
);

create table if not exists public.obligation_settlements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  obligation_id uuid not null,
  event_id uuid not null,
  financial_transaction_id uuid not null,
  amount numeric(14, 2) not null check (amount > 0),
  occurred_at timestamptz not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (event_id),
  foreign key (obligation_id, household_id)
    references public.obligations(id, household_id) on delete restrict,
  foreign key (event_id, household_id)
    references public.financial_events(id, household_id) on delete restrict,
  foreign key (financial_transaction_id, household_id)
    references public.financial_transactions(id, household_id) on delete restrict,
  foreign key (household_id, created_by)
    references public.household_members(household_id, user_id) on delete restrict
);

create table if not exists public.budget_funding_links (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  event_id uuid not null,
  source_account_id uuid not null,
  envelope_id uuid not null,
  amount numeric(14, 2) not null check (amount > 0),
  occurred_at timestamptz not null,
  notes text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  foreign key (event_id, household_id)
    references public.financial_events(id, household_id) on delete restrict,
  foreign key (source_account_id, household_id)
    references public.accounts(id, household_id) on delete restrict,
  foreign key (envelope_id, household_id)
    references public.envelopes(id, household_id) on delete restrict,
  foreign key (household_id, created_by)
    references public.household_members(household_id, user_id) on delete restrict
);

create or replace view public.obligation_balances
with (security_invoker = true)
as
select
  obligations.household_id,
  obligations.id as obligation_id,
  obligations.obligation_kind,
  obligations.receivable_kind,
  obligations.origin_event_id,
  obligations.origin_transaction_id,
  obligations.origin_envelope_id,
  obligations.recovery_source_event_id,
  obligations.recovery_source_envelope_id,
  obligations.initial_amount,
  coalesce(sum(settlements.amount), 0)::numeric(14, 2) as settled_amount,
  (obligations.initial_amount - coalesce(sum(settlements.amount), 0))::numeric(14, 2) as remaining_amount,
  case when obligations.initial_amount = coalesce(sum(settlements.amount), 0) then 'settled' else 'open' end as status,
  obligations.counterparty_name,
  obligations.description,
  obligations.due_at,
  obligations.created_at,
  (obligations.due_at is not null and obligations.due_at < current_date
    and obligations.initial_amount > coalesce(sum(settlements.amount), 0)) as is_overdue
from public.obligations
left join public.obligation_settlements settlements on settlements.obligation_id = obligations.id
group by obligations.id, obligations.household_id, obligations.obligation_kind,
  obligations.receivable_kind, obligations.origin_event_id, obligations.origin_transaction_id,
  obligations.origin_envelope_id, obligations.recovery_source_event_id,
  obligations.recovery_source_envelope_id, obligations.initial_amount,
  obligations.counterparty_name, obligations.description, obligations.due_at,
  obligations.created_at;

create or replace function public.prevent_financial_event_mutation()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'Financial event records are immutable';
end;
$$;

create or replace function public.assert_obligation_settlement_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_initial numeric(14, 2); v_settled numeric(14, 2);
begin
  select initial_amount into v_initial from public.obligations where id = new.obligation_id and household_id = new.household_id;
  select coalesce(sum(amount), 0) into v_settled from public.obligation_settlements
    where obligation_id = new.obligation_id and household_id = new.household_id;
  if v_initial is null or v_settled > v_initial then
    raise exception 'An obligation cannot be settled above its remaining amount';
  end if;
  return null;
end;
$$;

drop trigger if exists financial_events_immutable on public.financial_events;
create trigger financial_events_immutable before update or delete on public.financial_events
for each row execute function public.prevent_financial_event_mutation();
drop trigger if exists obligations_immutable on public.obligations;
create trigger obligations_immutable before update or delete on public.obligations
for each row execute function public.prevent_financial_event_mutation();
drop trigger if exists obligation_settlements_immutable on public.obligation_settlements;
create trigger obligation_settlements_immutable before update or delete on public.obligation_settlements
for each row execute function public.prevent_financial_event_mutation();
drop trigger if exists budget_funding_links_immutable on public.budget_funding_links;
create trigger budget_funding_links_immutable before update or delete on public.budget_funding_links
for each row execute function public.prevent_financial_event_mutation();
drop trigger if exists obligation_settlements_limit on public.obligation_settlements;
create constraint trigger obligation_settlements_limit after insert on public.obligation_settlements
deferrable initially deferred for each row execute function public.assert_obligation_settlement_limit();

alter table public.financial_events enable row level security;
alter table public.obligations enable row level security;
alter table public.obligation_settlements enable row level security;
alter table public.budget_funding_links enable row level security;

revoke all on public.financial_events, public.obligations, public.obligation_settlements, public.budget_funding_links from public, anon, authenticated;
grant select on public.financial_events, public.obligations, public.obligation_settlements, public.budget_funding_links, public.obligation_balances to authenticated;

create policy "members read financial events" on public.financial_events for select using (public.is_household_member(household_id));
create policy "members read obligations" on public.obligations for select using (public.is_household_member(household_id));
create policy "members read obligation settlements" on public.obligation_settlements for select using (public.is_household_member(household_id));
create policy "members read budget funding links" on public.budget_funding_links for select using (public.is_household_member(household_id));

commit;
