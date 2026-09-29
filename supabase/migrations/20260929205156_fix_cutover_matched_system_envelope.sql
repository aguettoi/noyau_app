-- Align explicit Cutover B1 envelope matching with the canonical system_code
-- column. The previous additive wrapper referenced the non-existent system_key.
begin;

create or replace function public.execute_cutover_opening_import(
  p_household_id uuid,
  p_cutover_id uuid,
  p_source_fingerprint text,
  p_effective_date date,
  p_plan jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_account jsonb;
  v_envelope jsonb;
  v_expected_id uuid;
  v_materialized jsonb;
  v_run_id uuid;
  v_reconciled jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.assert_household_access(p_household_id);

  if exists (
    select 1 from public.cutover_opening_runs
    where household_id=p_household_id
      and source_fingerprint=p_source_fingerprint
      and effective_date=p_effective_date
      and scope='opening_positions'
  ) then
    v_materialized := public.execute_cutover_opening_import_materialize(
      p_household_id,p_cutover_id,p_source_fingerprint,p_effective_date,p_plan
    );
    v_run_id := (v_materialized->>'run_id')::uuid;
    v_reconciled := public.reconcile_cutover_opening_run(v_run_id);
    update public.cutover_opening_runs set result=v_reconciled where id=v_run_id;
    return v_reconciled;
  end if;

  for v_account in select value from jsonb_array_elements(p_plan->'accounts') loop
    if v_account->>'conflict_decision' = 'conflict' then
      raise exception 'A conflicting account reference cannot be materialized';
    elsif v_account->>'conflict_decision' = 'match' then
      v_expected_id := nullif(v_account->>'matched_account_id','')::uuid;
      if v_expected_id is null then
        raise exception 'An account match requires matched_account_id';
      end if;
      if not exists (
        select 1 from public.accounts
        where id=v_expected_id and household_id=p_household_id
          and lower(name)=lower(v_account->>'name') and not is_system
      ) then
        raise exception 'The confirmed matched_account_id is not the planned account';
      end if;
      if (
        select count(*) from public.accounts
        where household_id=p_household_id
          and lower(name)=lower(v_account->>'name') and not is_system
      ) <> 1 then
        raise exception 'The account name does not identify exactly one confirmed reference';
      end if;
      perform 1 from public.accounts where id=v_expected_id for update;
    elsif v_account ? 'matched_account_id' then
      raise exception 'An account create decision cannot carry matched_account_id';
    end if;
  end loop;

  for v_envelope in select value from jsonb_array_elements(p_plan->'envelopes') loop
    if v_envelope->>'reference_conflict' is not null
       or v_envelope->>'conflict_decision' = 'conflict' then
      raise exception 'A conflicting envelope reference cannot be materialized';
    elsif coalesce((v_envelope->>'is_to_allocate')::boolean,false)
       or v_envelope->>'conflict_decision' = 'match' then
      v_expected_id := nullif(v_envelope->>'matched_envelope_id','')::uuid;
      if v_expected_id is null then
        raise exception 'An envelope match requires matched_envelope_id';
      end if;
      if not exists (
        select 1 from public.envelopes
        where id=v_expected_id and household_id=p_household_id
          and (
            (coalesce((v_envelope->>'is_to_allocate')::boolean,false)
              and is_system and system_code='to_allocate')
            or (not coalesce((v_envelope->>'is_to_allocate')::boolean,false)
              and not is_system and lower(name)=lower(v_envelope->>'name'))
          )
      ) then
        raise exception 'The confirmed matched_envelope_id is not the planned envelope';
      end if;
      if not coalesce((v_envelope->>'is_to_allocate')::boolean,false)
         and (
           select count(*) from public.envelopes
           where household_id=p_household_id
             and not is_system and lower(name)=lower(v_envelope->>'name')
         ) <> 1 then
        raise exception 'The envelope name does not identify exactly one confirmed reference';
      end if;
      perform 1 from public.envelopes where id=v_expected_id for update;
    elsif v_envelope ? 'matched_envelope_id' then
      raise exception 'An envelope create decision cannot carry matched_envelope_id';
    end if;
  end loop;

  v_materialized := public.execute_cutover_opening_import_materialize(
    p_household_id,p_cutover_id,p_source_fingerprint,p_effective_date,p_plan
  );
  v_run_id := (v_materialized->>'run_id')::uuid;
  v_reconciled := public.reconcile_cutover_opening_run(v_run_id);
  update public.cutover_opening_runs set result=v_reconciled where id=v_run_id;
  return v_reconciled;
end;
$$;

revoke all on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)
  from public, anon;
grant execute on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)
  to authenticated;

commit;
