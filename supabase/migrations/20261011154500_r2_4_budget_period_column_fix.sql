begin;

create or replace function public.monthly_close_automatic_target_preview(
  p_household_id uuid,
  p_month_start date
) returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare
  v_month date := date_trunc('month',p_month_start)::date;
  v_scenario uuid;
  v_version uuid;
  v_name text;
  v_targets jsonb;
  v_missing jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_month_start<>v_month then raise exception 'Invalid month'; end if;

  select bp.scenario_id into v_scenario
  from public.budget_periods bp
  where bp.household_id=p_household_id and bp.status='active'
    and bp.starts_on<=v_month and bp.ends_on>=v_month
  order by bp.starts_on desc limit 1;
  if v_scenario is null then
    select bs.id into v_scenario from public.budget_scenarios bs
    where bs.household_id=p_household_id and bs.active
      and (bs.valid_from is null or bs.valid_from<=v_month)
      and (bs.valid_to is null or bs.valid_to>=v_month)
    order by bs.priority asc,bs.is_default desc,bs.created_at desc limit 1;
  end if;
  select bs.name,bs.current_version_id into v_name,v_version
  from public.budget_scenarios bs where bs.id=v_scenario and bs.household_id=p_household_id;

  with step_account as (
    select st.envelope_id,st.funding_source_preference account_id,
      st.allocation_method,
      sum(case st.allocation_method when 'fixed' then st.amount when 'percentage' then st.percentage else 0 end) weight
    from public.budget_scenario_steps st
    where st.household_id=p_household_id and st.scenario_version_id=v_version and st.active
    group by st.envelope_id,st.funding_source_preference,st.allocation_method
  ), step_summary as (
    select st.envelope_id,
      count(*) filter(where st.funding_source_preference is null) missing_sources,
      count(distinct st.funding_source_preference) filter(where st.funding_source_preference is not null) account_count,
      count(distinct st.allocation_method) methods,
      min(st.allocation_method) method
    from public.budget_scenario_steps st
    where st.household_id=p_household_id and st.scenario_version_id=v_version and st.active
    group by st.envelope_id
  ), candidates as (
    select e.id envelope_id,e.name envelope_name,b.balance,
      e.recommended_account_id account_id,1::numeric weight,'Recommandation de l’enveloppe' source_label
    from public.envelopes e join public.envelope_ledger_balances b on b.envelope_id=e.id and b.household_id=e.household_id
    where e.household_id=p_household_id and e.archived_at is null and not e.is_system
      and e.recommended_account_id is not null
    union all
    select e.id,e.name,b.balance,sa.account_id,
      case when ss.account_count=1 then 1 else sa.weight end,
      case when ss.account_count=1 then 'Scénario — compte unique'
        else 'Scénario — répartition multi-comptes' end
    from public.envelopes e join public.envelope_ledger_balances b on b.envelope_id=e.id and b.household_id=e.household_id
    join step_summary ss on ss.envelope_id=e.id
    join step_account sa on sa.envelope_id=e.id and sa.account_id is not null
    where e.household_id=p_household_id and e.archived_at is null and not e.is_system
      and e.recommended_account_id is null and ss.missing_sources=0
      and (ss.account_count=1 or (ss.account_count>1 and ss.methods=1 and ss.method in ('fixed','percentage') and sa.weight>0))
  ), weighted as (
    select c.*,sum(c.weight) over(partition by c.envelope_id) total_weight,
      row_number() over(partition by c.envelope_id order by c.account_id) rn,
      count(*) over(partition by c.envelope_id) cnt
    from candidates c
  ), amounts as (
    select w.*,round(w.balance*w.weight/nullif(w.total_weight,0),2) rounded_amount
    from weighted w
  ), final_targets as (
    select a.*,
      case when rn=cnt then balance-coalesce(sum(rounded_amount) over(
        partition by envelope_id order by account_id rows between unbounded preceding and 1 preceding
      ),0) else rounded_amount end target_amount
    from amounts a
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'envelope_id',envelope_id,'envelope_name',envelope_name,'account_id',account_id,
    'target_amount',target_amount,'source_label',source_label
  ) order by envelope_name,account_id),'[]'::jsonb) into v_targets from final_targets;

  with mapped as (
    select distinct (value->>'envelope_id')::uuid envelope_id from jsonb_array_elements(v_targets)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'envelope_id',e.id,'envelope_name',e.name,'balance',b.balance,
    'reason','Aucun rattachement canonique unique ou aucune répartition multi-comptes exploitable'
  ) order by e.name),'[]'::jsonb) into v_missing
  from public.envelopes e join public.envelope_ledger_balances b on b.envelope_id=e.id and b.household_id=e.household_id
  left join mapped m on m.envelope_id=e.id
  where e.household_id=p_household_id and e.archived_at is null and not e.is_system
    and b.balance<>0 and m.envelope_id is null;

  return jsonb_build_object(
    'month_start',v_month,'scenario_id',v_scenario,'scenario_name',v_name,
    'targets',v_targets,'missing_mappings',v_missing,
    'complete',jsonb_array_length(v_missing)=0
  );
end; $$;

revoke all on function public.monthly_close_automatic_target_preview(uuid,date) from public,anon;
grant execute on function public.monthly_close_automatic_target_preview(uuid,date) to authenticated;

commit;
