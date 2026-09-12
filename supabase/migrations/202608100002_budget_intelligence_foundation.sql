-- Budget Intelligence foundation. Planning records never write ledger data.
begin;

create table if not exists public.budget_scenarios (
  id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120), description text,
  active boolean not null default false, priority integer not null default 0,
  valid_from date, valid_to date, trigger_type text, trigger_definition jsonb,
  notes text, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, household_id), unique (household_id, name),
  check (valid_to is null or valid_from is null or valid_to >= valid_from)
);

-- `budget_periods` originates in Lot 0. Its canonical period is starts_on / ends_on;
-- this migration extends it instead of creating parallel year/month columns.
alter table public.budget_periods
  add column if not exists scenario_id uuid,
  add column if not exists opened_at timestamptz,
  add column if not exists closed_at timestamptz,
  add column if not exists created_by uuid references auth.users(id);
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.budget_periods'::regclass
      and conname = 'budget_periods_id_household_unique'
  ) then
    alter table public.budget_periods
      add constraint budget_periods_id_household_unique unique (id, household_id);
  end if;
end;
$$;
create unique index if not exists budget_periods_one_active_per_household_period
  on public.budget_periods(household_id, starts_on) where status = 'active';
alter table public.budget_periods
  drop constraint if exists budget_periods_scenario_household_fk,
  add constraint budget_periods_scenario_household_fk
    foreign key (scenario_id, household_id)
    references public.budget_scenarios(id, household_id) on delete restrict;

create table if not exists public.budget_scenario_rules (
  id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households(id) on delete cascade,
  scenario_id uuid not null, envelope_id uuid not null, allocation_method text not null check (allocation_method in ('fixed','percentage','residual','target','none')),
  amount numeric(14,2), percentage numeric(7,4), minimum_amount numeric(14,2), maximum_amount numeric(14,2), priority integer not null default 0,
  rollover_policy text not null default 'report_total' check (rollover_policy in ('report_total','report_deficit_only','reset','cap_rollover')),
  rollover_cap numeric(14,2), funding_source_preference jsonb, contribution_rule text not null default 'custom' check (contribution_rule in ('proportional_income','fixed_percentage','ibrahim_only','nora_only','custom')),
  contribution_definition jsonb, notes text, active boolean not null default true, created_at timestamptz not null default now(),
  unique (scenario_id, envelope_id),
  foreign key (scenario_id, household_id) references public.budget_scenarios(id, household_id) on delete cascade,
  foreign key (envelope_id, household_id) references public.envelopes(id, household_id) on delete restrict,
  check ((allocation_method not in ('fixed','target')) or amount is not null),
  check ((allocation_method <> 'percentage') or (percentage is not null and percentage >= 0 and percentage <= 100)),
  check (minimum_amount is null or minimum_amount >= 0), check (maximum_amount is null or maximum_amount >= 0),
  check (minimum_amount is null or maximum_amount is null or minimum_amount <= maximum_amount),
  check (rollover_policy <> 'cap_rollover' or rollover_cap is not null)
);

create table if not exists public.budget_allocation_runs (
  id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households(id) on delete cascade,
  budget_period_id uuid not null, scenario_id uuid not null, status text not null default 'draft' check (status in ('draft','simulated','approved','applied','cancelled')),
  available_resources numeric(14,2) not null default 0, calculated_total numeric(14,2) not null default 0, remaining_unallocated numeric(14,2) not null default 0,
  summary jsonb not null default '{}'::jsonb, created_by uuid not null references auth.users(id), approved_by uuid references auth.users(id), applied_at timestamptz, created_at timestamptz not null default now(),
  unique (id, household_id),
  foreign key (budget_period_id, household_id) references public.budget_periods(id, household_id) on delete restrict,
  foreign key (scenario_id, household_id) references public.budget_scenarios(id, household_id) on delete restrict
);
create table if not exists public.budget_allocation_run_lines (
  id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households(id) on delete cascade,
  run_id uuid not null, envelope_id uuid not null, previous_balance numeric(14,2) not null default 0, rollover_amount numeric(14,2) not null default 0,
  planned_allocation numeric(14,2) not null default 0 check (planned_allocation >= 0), resulting_available numeric(14,2) not null,
  funding_source jsonb, contribution jsonb, priority integer not null default 0, warning text, created_at timestamptz not null default now(),
  unique (run_id, envelope_id), foreign key (run_id, household_id) references public.budget_allocation_runs(id, household_id) on delete cascade,
  foreign key (envelope_id, household_id) references public.envelopes(id, household_id) on delete restrict
);

create table if not exists public.budget_goals (
  id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120), target_amount numeric(14,2) not null check (target_amount > 0),
  target_date date, priority integer not null default 0, status text not null default 'planned' check (status in ('planned','active','completed','paused','cancelled')),
  funding_envelope_id uuid, monthly_target numeric(14,2) check (monthly_target is null or monthly_target >= 0), notes text,
  created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
  foreign key (funding_envelope_id, household_id) references public.envelopes(id, household_id) on delete restrict
);

alter table public.budget_scenarios enable row level security;
alter table public.budget_periods enable row level security;
alter table public.budget_scenario_rules enable row level security;
alter table public.budget_allocation_runs enable row level security;
alter table public.budget_allocation_run_lines enable row level security;
alter table public.budget_goals enable row level security;
revoke all on public.budget_scenarios, public.budget_periods, public.budget_scenario_rules, public.budget_allocation_runs, public.budget_allocation_run_lines, public.budget_goals from public, anon;
grant select, insert, update on public.budget_scenarios, public.budget_periods, public.budget_scenario_rules, public.budget_allocation_runs, public.budget_allocation_run_lines, public.budget_goals to authenticated;
drop policy if exists "members manage budget periods" on public.budget_periods;
create policy "members manage budget scenarios" on public.budget_scenarios for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "members manage budget periods" on public.budget_periods for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "members manage budget rules" on public.budget_scenario_rules for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "members manage allocation runs" on public.budget_allocation_runs for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "members manage allocation run lines" on public.budget_allocation_run_lines for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "members manage budget goals" on public.budget_goals for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));

create or replace view public.budget_envelope_reporting with (security_invoker = true) as
select e.household_id, e.id as envelope_id, date_trunc('month', m.occurred_at)::date as period_start,
  coalesce(sum(m.amount) filter (where m.movement_type = 'allocation'), 0) as allocations,
  coalesce(sum(m.amount) filter (where m.direction = 'inflow'), 0) as inflows,
  coalesce(sum(m.amount) filter (where m.direction = 'outflow'), 0) as outflows,
  coalesce(sum(m.amount) filter (where m.movement_type = 'consumption'), 0) as consumption,
  coalesce(sum(m.amount) filter (where m.direction = 'inflow'), 0) - coalesce(sum(m.amount) filter (where m.direction = 'outflow'), 0) as balance
from public.envelopes e left join public.envelope_movements m on m.envelope_id = e.id and m.household_id = e.household_id
group by e.household_id, e.id, date_trunc('month', m.occurred_at)::date;
grant select on public.budget_envelope_reporting to authenticated;
commit;
