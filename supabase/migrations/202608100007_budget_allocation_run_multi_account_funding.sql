-- Atomic multi-account funding for an approved budget allocation run.
-- Financial writes remain exclusively behind allocate_budget_event.
begin;

create table if not exists public.budget_allocation_run_funding_lines (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  run_id uuid not null,
  run_line_id uuid not null,
  source_account_id uuid not null,
  envelope_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  funding_index integer not null check (funding_index > 0),
  event_id uuid,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  unique (run_id, funding_index),
  foreign key (run_id, household_id)
    references public.budget_allocation_runs(id, household_id) on delete cascade,
  foreign key (run_line_id)
    references public.budget_allocation_run_lines(id) on delete restrict,
  foreign key (source_account_id, household_id)
    references public.accounts(id, household_id) on delete restrict,
  foreign key (envelope_id, household_id)
    references public.envelopes(id, household_id) on delete restrict,
  foreign key (event_id, household_id)
    references public.financial_events(id, household_id) on delete restrict
);

alter table public.budget_allocation_run_funding_lines enable row level security;
revoke all on public.budget_allocation_run_funding_lines from public, anon, authenticated;
grant select on public.budget_allocation_run_funding_lines to authenticated;
drop policy if exists "members read budget allocation funding lines" on public.budget_allocation_run_funding_lines;
create policy "members read budget allocation funding lines"
  on public.budget_allocation_run_funding_lines
  for select using (public.is_household_member(household_id));

create or replace function public.apply_budget_allocation_run_with_funding(
  p_household_id uuid,
  p_run_id uuid,
  p_funding_lines jsonb,
  p_idempotency_key uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_remaining numeric;
  v_apply_key uuid;
  v_expected_total numeric;
  v_actual_total numeric;
  v_run_line record;
  v_funding record;
  v_line_total numeric;
  v_event_id uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_funding_lines is null or jsonb_typeof(p_funding_lines) <> 'array' then
    raise exception 'Funding lines must be an array';
  end if;

  select status, remaining_unallocated, application_idempotency_key, calculated_total
    into v_status, v_remaining, v_apply_key, v_expected_total
  from public.budget_allocation_runs
  where id = p_run_id and household_id = p_household_id
  for update;
  if not found then raise exception 'Budget run does not belong to household'; end if;
  if v_status = 'applied' then
    if v_apply_key = p_idempotency_key then return p_run_id; end if;
    raise exception 'Budget run is already applied';
  end if;
  if v_status <> 'approved' then raise exception 'Only an approved budget run can be applied'; end if;
  if v_remaining < 0 then raise exception 'An over-allocated budget run cannot be applied'; end if;

  select coalesce(sum((item.value ->> 'amount')::numeric), 0)
    into v_actual_total
  from jsonb_array_elements(p_funding_lines) item(value);
  if v_actual_total <> v_expected_total then
    raise exception 'Funding total must equal the budget run total';
  end if;

  for v_funding in
    select item.value, item.ordinality
    from jsonb_array_elements(p_funding_lines) with ordinality as item(value, ordinality)
  loop
    if nullif(v_funding.value ->> 'amount', '') is null
      or (v_funding.value ->> 'amount')::numeric <= 0 then
      raise exception 'Each funding amount must be positive';
    end if;
    perform public.assert_financial_event_ordinary_account(
      p_household_id,
      (v_funding.value ->> 'source_account_id')::uuid
    );
    if not exists (
      select 1 from public.budget_allocation_run_lines run_line
      where run_line.id = (v_funding.value ->> 'run_line_id')::uuid
        and run_line.run_id = p_run_id
        and run_line.household_id = p_household_id
        and run_line.envelope_id = (v_funding.value ->> 'envelope_id')::uuid
    ) then
      raise exception 'Funding must target an envelope allocation from this budget run';
    end if;
  end loop;

  for v_run_line in
    select run_line.id, run_line.envelope_id, run_line.planned_allocation
    from public.budget_allocation_run_lines run_line
    where run_line.run_id = p_run_id
      and run_line.household_id = p_household_id
      and run_line.planned_allocation > 0
  loop
    select coalesce(sum((item.value ->> 'amount')::numeric), 0)
      into v_line_total
    from jsonb_array_elements(p_funding_lines) item(value)
    where (item.value ->> 'run_line_id')::uuid = v_run_line.id;
    if v_line_total <> v_run_line.planned_allocation then
      raise exception 'Funding must equal the planned amount for every envelope';
    end if;
  end loop;

  for v_funding in
    select item.value, item.ordinality
    from jsonb_array_elements(p_funding_lines) with ordinality as item(value, ordinality)
    order by item.ordinality
  loop
    v_event_id := public.allocate_budget_event(
      p_household_id,
      now(),
      'Allocation budgétaire',
      (v_funding.value ->> 'amount')::numeric,
      (v_funding.value ->> 'source_account_id')::uuid,
      (v_funding.value ->> 'envelope_id')::uuid,
      'Budget run ' || p_run_id::text,
      md5(p_run_id::text || ':funding:' || v_funding.ordinality::text)::uuid
    );
    insert into public.budget_allocation_run_funding_lines(
      household_id, run_id, run_line_id, source_account_id, envelope_id,
      amount, funding_index, event_id, applied_at
    ) values (
      p_household_id, p_run_id,
      (v_funding.value ->> 'run_line_id')::uuid,
      (v_funding.value ->> 'source_account_id')::uuid,
      (v_funding.value ->> 'envelope_id')::uuid,
      (v_funding.value ->> 'amount')::numeric,
      v_funding.ordinality::integer, v_event_id, now()
    );
  end loop;

  update public.budget_allocation_runs
  set status = 'applied', applied_at = now(), application_idempotency_key = p_idempotency_key
  where id = p_run_id and household_id = p_household_id;
  return p_run_id;
end;
$$;

revoke all on function public.apply_budget_allocation_run_with_funding(uuid, uuid, jsonb, uuid)
  from public, anon;
grant execute on function public.apply_budget_allocation_run_with_funding(uuid, uuid, jsonb, uuid)
  to authenticated;

commit;
