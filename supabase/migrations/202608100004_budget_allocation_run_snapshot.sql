-- Atomic persistence of a non-financial budget simulation snapshot.
-- This migration is additive and must be applied only after 202608100003.
begin;

-- Runs and their lines are historical snapshots. Authenticated users retain
-- read access only; SECURITY DEFINER RPCs below own every allowed mutation.
revoke insert, update, delete on public.budget_allocation_runs, public.budget_allocation_run_lines from authenticated;

create or replace function public.protect_budget_allocation_run_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Budget allocation runs are immutable';
  end if;
  if new.id is distinct from old.id
    or new.household_id is distinct from old.household_id
    or new.budget_period_id is distinct from old.budget_period_id
    or new.scenario_id is distinct from old.scenario_id
    or new.available_resources is distinct from old.available_resources
    or new.calculated_total is distinct from old.calculated_total
    or new.remaining_unallocated is distinct from old.remaining_unallocated
    or new.summary is distinct from old.summary
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'Budget allocation run snapshots are immutable';
  end if;
  if old.status = 'simulated' and new.status = 'approved'
    and new.approved_by is not null and new.approved_at is not null
    and new.applied_at is not distinct from old.applied_at
    and new.application_idempotency_key is not distinct from old.application_idempotency_key then
    return new;
  end if;
  if old.status = 'approved' and new.status = 'applied'
    and new.approved_by is not distinct from old.approved_by
    and new.approved_at is not distinct from old.approved_at
    and new.applied_at is not null and new.application_idempotency_key is not null then
    return new;
  end if;
  raise exception 'Invalid budget allocation run status transition';
end;
$$;

create or replace function public.protect_budget_allocation_run_line_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Budget allocation run lines are immutable';
  end if;
  if new.id is not distinct from old.id
    and new.household_id is not distinct from old.household_id
    and new.run_id is not distinct from old.run_id
    and new.envelope_id is not distinct from old.envelope_id
    and new.previous_balance is not distinct from old.previous_balance
    and new.rollover_amount is not distinct from old.rollover_amount
    and new.planned_allocation is not distinct from old.planned_allocation
    and new.resulting_available is not distinct from old.resulting_available
    and new.funding_source is not distinct from old.funding_source
    and new.contribution is not distinct from old.contribution
    and new.priority is not distinct from old.priority
    and new.warning is not distinct from old.warning
    and new.created_at is not distinct from old.created_at
    and old.applied_event_id is null
    and new.applied_event_id is not null
    and new.applied_at is not null then
    return new;
  end if;
  raise exception 'Budget allocation run line snapshots are immutable';
end;
$$;

drop trigger if exists protect_budget_allocation_run_snapshot on public.budget_allocation_runs;
create trigger protect_budget_allocation_run_snapshot
before update or delete on public.budget_allocation_runs
for each row execute function public.protect_budget_allocation_run_snapshot();

drop trigger if exists protect_budget_allocation_run_line_snapshot on public.budget_allocation_run_lines;
create trigger protect_budget_allocation_run_line_snapshot
before update or delete on public.budget_allocation_run_lines
for each row execute function public.protect_budget_allocation_run_line_snapshot();

create or replace function public.save_budget_allocation_run(
  p_household_id uuid,
  p_run_id uuid,
  p_budget_period_id uuid,
  p_scenario_id uuid,
  p_available_resources numeric,
  p_calculated_total numeric,
  p_remaining_unallocated numeric,
  p_lines jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Budget run lines must be an array';
  end if;
  if p_calculated_total <> coalesce((
    select sum((line.value ->> 'planned_allocation')::numeric)
    from jsonb_array_elements(p_lines) as line(value)
  ), 0) then
    raise exception 'Budget run total does not match its lines';
  end if;

  insert into public.budget_allocation_runs (
    id, household_id, budget_period_id, scenario_id, status,
    available_resources, calculated_total, remaining_unallocated, created_by
  ) values (
    p_run_id, p_household_id, p_budget_period_id, p_scenario_id, 'simulated',
    p_available_resources, p_calculated_total, p_remaining_unallocated, auth.uid()
  );

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    insert into public.budget_allocation_run_lines (
      household_id, run_id, envelope_id, previous_balance, rollover_amount,
      planned_allocation, resulting_available, priority, warning
    ) values (
      p_household_id,
      p_run_id,
      (v_line ->> 'envelope_id')::uuid,
      coalesce((v_line ->> 'previous_balance')::numeric, 0),
      coalesce((v_line ->> 'rollover_amount')::numeric, 0),
      coalesce((v_line ->> 'planned_allocation')::numeric, 0),
      coalesce((v_line ->> 'resulting_available')::numeric, 0),
      coalesce((v_line ->> 'priority')::integer, 0),
      nullif(v_line ->> 'warning', '')
    );
  end loop;
  return p_run_id;
end;
$$;

revoke all on function public.save_budget_allocation_run(uuid, uuid, uuid, uuid, numeric, numeric, numeric, jsonb) from public, anon;
grant execute on function public.save_budget_allocation_run(uuid, uuid, uuid, uuid, numeric, numeric, numeric, jsonb) to authenticated;

commit;
