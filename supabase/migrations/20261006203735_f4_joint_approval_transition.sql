begin;
create or replace function public.approve_budget_allocation_run(p_household_id uuid, p_run_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text; v_remaining numeric; v_hash text; v_mode text; v_required integer; v_count integer;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select status, remaining_unallocated into v_status, v_remaining from public.budget_allocation_runs
    where id=p_run_id and household_id=p_household_id for update;
  if not found then raise exception 'Budget run does not belong to household'; end if;
  if v_status not in ('simulated','approved') then raise exception 'Only a simulated budget run can be approved'; end if;
  if v_remaining < 0 then raise exception 'An over-allocated budget run cannot be approved'; end if;
  v_hash := public.budget_run_revision_hash(p_run_id,p_household_id);
  insert into public.budget_run_approvals(run_id,household_id,member_user_id,revision_hash)
    values(p_run_id,p_household_id,auth.uid(),v_hash)
    on conflict(run_id,member_user_id) do update set revision_hash=excluded.revision_hash, approved_at=now();
  select budget_validation_mode into v_mode from public.households where id=p_household_id;
  select count(*) into v_required from public.household_members where household_id=p_household_id;
  select count(*) into v_count from public.budget_run_approvals where run_id=p_run_id and household_id=p_household_id and revision_hash=v_hash;
  if v_mode='authorized_member' or v_count>=v_required then
    update public.budget_allocation_runs set status='approved',approved_by=auth.uid(),approved_at=now()
      where id=p_run_id and household_id=p_household_id and status='simulated';
  end if;
end;
$$;
revoke all on function public.approve_budget_allocation_run(uuid,uuid) from public,anon;
grant execute on function public.approve_budget_allocation_run(uuid,uuid) to authenticated;
commit;
