-- Atomic application of a persisted budget run. Apply only after the 080002 foundation.
begin;

alter table public.budget_allocation_runs
  add column if not exists approved_at timestamptz,
  add column if not exists application_idempotency_key uuid;
alter table public.budget_allocation_run_lines
  add column if not exists applied_event_id uuid,
  add column if not exists applied_at timestamptz;

create unique index if not exists budget_allocation_runs_household_application_idempotency_unique
  on public.budget_allocation_runs(household_id, application_idempotency_key)
  where application_idempotency_key is not null;

create or replace function public.approve_budget_allocation_run(
  p_household_id uuid,
  p_run_id uuid
) returns void language plpgsql security definer set search_path = public as $$
declare v_status text; v_remaining numeric;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select status, remaining_unallocated into v_status, v_remaining from public.budget_allocation_runs
    where id = p_run_id and household_id = p_household_id for update;
  if not found then raise exception 'Budget run does not belong to household'; end if;
  if v_status <> 'simulated' then raise exception 'Only a simulated budget run can be approved'; end if;
  if v_remaining < 0 then raise exception 'An over-allocated budget run cannot be approved'; end if;
  update public.budget_allocation_runs set status = 'approved', approved_by = auth.uid(), approved_at = now()
    where id = p_run_id and household_id = p_household_id;
end;
$$;

create or replace function public.apply_budget_allocation_run(
  p_household_id uuid,
  p_run_id uuid,
  p_source_account_id uuid,
  p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_status text; v_remaining numeric; v_line record; v_event_id uuid; v_apply_key uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select status, remaining_unallocated, application_idempotency_key into v_status, v_remaining, v_apply_key
    from public.budget_allocation_runs where id = p_run_id and household_id = p_household_id for update;
  if not found then raise exception 'Budget run does not belong to household'; end if;
  if v_status = 'applied' then
    if v_apply_key = p_idempotency_key then return p_run_id; end if;
    raise exception 'Budget run is already applied';
  end if;
  if v_status <> 'approved' then raise exception 'Only an approved budget run can be applied'; end if;
  if v_remaining < 0 then raise exception 'An over-allocated budget run cannot be applied'; end if;
  perform public.assert_financial_event_ordinary_account(p_household_id, p_source_account_id);
  for v_line in select id, envelope_id, planned_allocation from public.budget_allocation_run_lines
    where run_id = p_run_id and household_id = p_household_id and planned_allocation > 0 order by priority, id
  loop
    v_event_id := public.allocate_budget_event(
      p_household_id, now(), 'Allocation budgétaire', v_line.planned_allocation,
      p_source_account_id, v_line.envelope_id, 'Budget run ' || p_run_id::text,
      md5(p_run_id::text || ':' || v_line.id::text)::uuid
    );
    update public.budget_allocation_run_lines set applied_event_id = v_event_id, applied_at = now()
      where id = v_line.id and household_id = p_household_id;
  end loop;
  update public.budget_allocation_runs set status = 'applied', applied_at = now(), application_idempotency_key = p_idempotency_key
    where id = p_run_id and household_id = p_household_id;
  return p_run_id;
end;
$$;

revoke all on function public.approve_budget_allocation_run(uuid, uuid), public.apply_budget_allocation_run(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.approve_budget_allocation_run(uuid, uuid), public.apply_budget_allocation_run(uuid, uuid, uuid, uuid) to authenticated;
commit;
