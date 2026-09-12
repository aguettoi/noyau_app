-- Additive household contribution model. It does not write financial data.
begin;

create table if not exists public.budget_scenario_member_incomes (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  scenario_id uuid not null,
  member_user_id uuid not null,
  net_recurring_income numeric(14,2) not null default 0 check (net_recurring_income >= 0),
  other_recurring_income numeric(14,2) not null default 0 check (other_recurring_income >= 0),
  exceptional_income numeric(14,2) not null default 0 check (exceptional_income >= 0),
  exceptional_treatment text not null default 'excluded' check (exceptional_treatment in ('excluded', 'included_in_shared_capacity', 'direct_allocation')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (scenario_id, member_user_id),
  foreign key (scenario_id, household_id) references public.budget_scenarios(id, household_id) on delete cascade,
  foreign key (household_id, member_user_id) references public.household_members(household_id, user_id) on delete restrict
);

alter table public.budget_scenario_rules
  add column if not exists funding_mode text not null default 'shared_auto'
    check (funding_mode in ('personal_member', 'shared_auto', 'shared_custom', 'fixed_by_member', 'exceptional_income')),
  add column if not exists funding_member_user_id uuid,
  add column if not exists funding_definition jsonb not null default '{}'::jsonb;
alter table public.budget_scenario_rules
  drop constraint if exists budget_scenario_rules_funding_member_household_fk,
  add constraint budget_scenario_rules_funding_member_household_fk
    foreign key (household_id, funding_member_user_id)
    references public.household_members(household_id, user_id) on delete restrict;
alter table public.budget_scenario_rules
  drop constraint if exists budget_scenario_rules_personal_member_check,
  add constraint budget_scenario_rules_personal_member_check
    check (funding_mode <> 'personal_member' or funding_member_user_id is not null);

alter table public.budget_scenario_member_incomes enable row level security;
revoke all on public.budget_scenario_member_incomes from public, anon;
grant select, insert, update on public.budget_scenario_member_incomes to authenticated;
create policy "members manage budget scenario incomes" on public.budget_scenario_member_incomes
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

create or replace function public.save_budget_allocation_run_with_contributions(
  p_household_id uuid, p_run_id uuid, p_budget_period_id uuid, p_scenario_id uuid,
  p_available_resources numeric, p_calculated_total numeric, p_remaining_unallocated numeric,
  p_summary jsonb, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_line jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if jsonb_typeof(p_lines) <> 'array' then raise exception 'Budget run lines must be an array'; end if;
  if p_calculated_total <> coalesce((select sum((item.value ->> 'planned_allocation')::numeric) from jsonb_array_elements(p_lines) item(value)), 0) then raise exception 'Budget run total does not match its lines'; end if;
  insert into public.budget_allocation_runs(id, household_id, budget_period_id, scenario_id, status, available_resources, calculated_total, remaining_unallocated, summary, created_by)
  values (p_run_id, p_household_id, p_budget_period_id, p_scenario_id, 'simulated', p_available_resources, p_calculated_total, p_remaining_unallocated, coalesce(p_summary, '{}'::jsonb), auth.uid());
  for v_line in select value from jsonb_array_elements(p_lines) loop
    insert into public.budget_allocation_run_lines(household_id, run_id, envelope_id, previous_balance, rollover_amount, planned_allocation, resulting_available, funding_source, contribution, priority, warning)
    values (p_household_id, p_run_id, (v_line ->> 'envelope_id')::uuid, coalesce((v_line ->> 'previous_balance')::numeric, 0), coalesce((v_line ->> 'rollover_amount')::numeric, 0), coalesce((v_line ->> 'planned_allocation')::numeric, 0), coalesce((v_line ->> 'resulting_available')::numeric, 0), v_line -> 'funding_source', v_line -> 'contribution', coalesce((v_line ->> 'priority')::integer, 0), nullif(v_line ->> 'warning', ''));
  end loop;
  return p_run_id;
end; $$;
revoke all on function public.save_budget_allocation_run_with_contributions(uuid, uuid, uuid, uuid, numeric, numeric, numeric, jsonb, jsonb) from public, anon;
grant execute on function public.save_budget_allocation_run_with_contributions(uuid, uuid, uuid, uuid, numeric, numeric, numeric, jsonb, jsonb) to authenticated;

commit;
