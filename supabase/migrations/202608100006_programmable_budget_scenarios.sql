-- Additive programmable-template layer. Do not apply without PRE/POST review.
begin;

create table if not exists public.budget_scenario_versions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  scenario_id uuid not null,
  version integer not null check (version > 0),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (id, household_id),
  unique (scenario_id, version),
  foreign key (scenario_id, household_id)
    references public.budget_scenarios(id, household_id) on delete restrict
);

alter table public.budget_scenarios
  add column if not exists is_default boolean not null default false,
  add column if not exists current_version_id uuid;
create unique index if not exists budget_scenarios_one_default_per_household
  on public.budget_scenarios(household_id) where is_default;
alter table public.budget_scenarios
  drop constraint if exists budget_scenarios_current_version_household_fk,
  add constraint budget_scenarios_current_version_household_fk
    foreign key (current_version_id, household_id)
    references public.budget_scenario_versions(id, household_id) on delete restrict;

create table if not exists public.budget_scenario_sources (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  scenario_version_id uuid not null,
  source_type text not null check (source_type in ('member_recurring_income','member_other_recurring_income','exceptional_income','common_capacity','available_savings','other')),
  name text not null check (char_length(trim(name)) between 1 and 120),
  expected_amount numeric(14,2) not null default 0 check (expected_amount >= 0),
  member_user_id uuid,
  exceptional_treatment text check (exceptional_treatment in ('excluded','included_in_shared_capacity','direct_allocation')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, household_id),
  foreign key (scenario_version_id, household_id)
    references public.budget_scenario_versions(id, household_id) on delete cascade,
  foreign key (household_id, member_user_id)
    references public.household_members(household_id, user_id) on delete restrict,
  check ((source_type not in ('member_recurring_income','member_other_recurring_income')) or member_user_id is not null)
);

create table if not exists public.budget_scenario_steps (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  scenario_version_id uuid not null,
  step_order integer not null check (step_order >= 0),
  group_name text not null default 'Sans groupe' check (char_length(trim(group_name)) between 1 and 120),
  source_id uuid not null,
  envelope_id uuid not null,
  allocation_method text not null check (allocation_method in ('fixed','percentage','residual')),
  amount numeric(14,2), percentage numeric(7,4),
  contribution_key text not null check (contribution_key in ('automatic_remaining_capacity','custom_percentage','fixed_by_member','single_member','equal')),
  member_user_id uuid,
  key_definition jsonb not null default '{}'::jsonb,
  insufficient_funds_policy text not null default 'strict' check (insufficient_funds_policy in ('strict','cap','skip','proportional')),
  funding_source_preference uuid,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, household_id),
  unique (scenario_version_id, step_order),
  foreign key (scenario_version_id, household_id)
    references public.budget_scenario_versions(id, household_id) on delete cascade,
  foreign key (source_id, household_id)
    references public.budget_scenario_sources(id, household_id) on delete restrict,
  foreign key (envelope_id, household_id)
    references public.envelopes(id, household_id) on delete restrict,
  foreign key (household_id, member_user_id)
    references public.household_members(household_id, user_id) on delete restrict,
  foreign key (funding_source_preference, household_id)
    references public.accounts(id, household_id) on delete restrict,
  check ((allocation_method <> 'fixed') or (amount is not null and amount > 0)),
  check ((allocation_method <> 'percentage') or (percentage is not null and percentage >= 0 and percentage <= 100)),
  check ((contribution_key <> 'single_member') or member_user_id is not null)
);

alter table public.budget_allocation_runs
  add column if not exists scenario_version_id uuid;
alter table public.budget_allocation_runs
  drop constraint if exists budget_allocation_runs_scenario_version_household_fk,
  add constraint budget_allocation_runs_scenario_version_household_fk
    foreign key (scenario_version_id, household_id)
    references public.budget_scenario_versions(id, household_id) on delete restrict;

create or replace function public.save_programmable_budget_run(
  p_household_id uuid,
  p_run_id uuid,
  p_budget_period_id uuid,
  p_scenario_id uuid,
  p_scenario_version_id uuid,
  p_available_resources numeric,
  p_calculated_total numeric,
  p_remaining_unallocated numeric,
  p_summary jsonb,
  p_lines jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Budget run lines must be an array';
  end if;
  insert into public.budget_allocation_runs(
    id, household_id, budget_period_id, scenario_id, scenario_version_id,
    status, available_resources, calculated_total, remaining_unallocated,
    summary, created_by
  ) values (
    p_run_id, p_household_id, p_budget_period_id, p_scenario_id,
    p_scenario_version_id, 'simulated', p_available_resources,
    p_calculated_total, p_remaining_unallocated, coalesce(p_summary, '{}'::jsonb),
    auth.uid()
  );
  insert into public.budget_allocation_run_lines(
    household_id, run_id, envelope_id, previous_balance, rollover_amount,
    planned_allocation, resulting_available, funding_source, contribution,
    priority, warning
  )
  select p_household_id, p_run_id,
    (item.value ->> 'envelope_id')::uuid,
    coalesce((item.value ->> 'previous_balance')::numeric, 0),
    coalesce((item.value ->> 'rollover_amount')::numeric, 0),
    coalesce((item.value ->> 'planned_allocation')::numeric, 0),
    coalesce((item.value ->> 'resulting_available')::numeric, 0),
    item.value -> 'funding_source', item.value -> 'contribution',
    coalesce((item.value ->> 'priority')::integer, 0), nullif(item.value ->> 'warning', '')
  from jsonb_array_elements(p_lines) item(value);
  return p_run_id;
end;
$$;
revoke all on function public.save_programmable_budget_run(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb,jsonb) from public, anon;
grant execute on function public.save_programmable_budget_run(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb,jsonb) to authenticated;

alter table public.budget_scenario_versions enable row level security;
alter table public.budget_scenario_sources enable row level security;
alter table public.budget_scenario_steps enable row level security;
revoke all on public.budget_scenario_versions, public.budget_scenario_sources, public.budget_scenario_steps from public, anon;
grant select, insert, update on public.budget_scenario_versions, public.budget_scenario_sources, public.budget_scenario_steps to authenticated;
create policy "members manage budget scenario versions" on public.budget_scenario_versions for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "members manage budget scenario sources" on public.budget_scenario_sources for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "members manage budget scenario steps" on public.budget_scenario_steps for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));

commit;
