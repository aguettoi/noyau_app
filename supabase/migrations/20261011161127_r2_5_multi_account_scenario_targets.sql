-- R2.5: derive canonical month-end targets from the applicable Budget
-- Intelligence scenario, including structural multi-account envelopes.
-- This preview is planning-only and creates no financial or envelope entry.
begin;

create or replace function public.monthly_close_automatic_target_preview(
  p_household_id uuid, p_month_start date
) returns jsonb language plpgsql stable security definer
set search_path=public,auth as $$
declare v_scenario uuid; v_scenario_name text; v_rows jsonb; v_missing jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_month_start<>date_trunc('month',p_month_start)::date then
    raise exception 'Invalid month';
  end if;

  select p.scenario_id,s.name into v_scenario,v_scenario_name
  from public.budget_periods p
  join public.budget_scenarios s on s.id=p.scenario_id and s.household_id=p.household_id
  where p.household_id=p_household_id and p.status='active'
    and p.starts_on<=p_month_start and p.ends_on>=p_month_start
  order by p.starts_on desc limit 1;

  if v_scenario is null then
    select s.id,s.name into v_scenario,v_scenario_name
    from public.budget_scenarios s
    where s.household_id=p_household_id and s.active
      and (s.valid_from is null or s.valid_from<=p_month_start)
      and (s.valid_to is null or s.valid_to>=p_month_start)
    order by s.priority asc,s.is_default desc,s.created_at desc limit 1;
  end if;

  with envelope_state as (
    select e.id envelope_id,e.name envelope_name,b.balance,e.recommended_account_id
    from public.envelopes e
    join public.envelope_ledger_balances b
      on b.envelope_id=e.id and b.household_id=e.household_id
    where e.household_id=p_household_id and e.archived_at is null
  ), scenario_weights as (
    select st.envelope_id,st.funding_source_preference account_id,
      sum(st.amount) weight
    from public.budget_scenarios s
    join public.budget_scenario_steps st
      on st.scenario_version_id=s.current_version_id
      and st.household_id=s.household_id and st.active
    join public.accounts a on a.id=st.funding_source_preference
      and a.household_id=st.household_id and a.archived_at is null and not a.is_system
    where s.id=v_scenario and s.household_id=p_household_id
      and st.funding_source_preference is not null and st.amount>0
    group by st.envelope_id,st.funding_source_preference
  ), weighted as (
    select es.envelope_id,es.envelope_name,es.balance,sw.account_id,sw.weight,
      sum(sw.weight) over(partition by es.envelope_id) total_weight,
      row_number() over(partition by es.envelope_id order by sw.account_id) allocation_rank,
      count(*) over(partition by es.envelope_id) allocation_count
    from envelope_state es join scenario_weights sw on sw.envelope_id=es.envelope_id
    where es.recommended_account_id is null
  ), rounded as (
    select *,round(balance*weight/nullif(total_weight,0),2) rounded_amount
    from weighted
  ), target_rows as (
    select es.envelope_id,es.envelope_name,es.recommended_account_id account_id,
      es.balance target_amount,'Recommandation de l’enveloppe'::text source_label
    from envelope_state es where es.recommended_account_id is not null
    union all
    select r.envelope_id,r.envelope_name,r.account_id,
      case when r.allocation_rank=r.allocation_count then
        r.balance-coalesce(sum(r.rounded_amount) over(
          partition by r.envelope_id order by r.allocation_rank
          rows between unbounded preceding and 1 preceding),0)
      else r.rounded_amount end target_amount,
      'Scénario '||coalesce(v_scenario_name,'actif') source_label
    from rounded r
  ), missing_rows as (
    select es.envelope_id,es.envelope_name,es.balance
    from envelope_state es
    where es.balance<>0 and es.recommended_account_id is null
      and not exists(select 1 from scenario_weights sw where sw.envelope_id=es.envelope_id)
  )
  select
    coalesce((select jsonb_agg(jsonb_build_object(
      'envelope_id',envelope_id,'envelope_name',envelope_name,
      'account_id',account_id,'target_amount',target_amount,
      'source_label',source_label)
      order by envelope_name,account_id) from target_rows),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
      'envelope_id',envelope_id,'envelope_name',envelope_name,
      'balance',balance,'reason','Aucun compte cible canonique dans le scénario applicable')
      order by envelope_name) from missing_rows),'[]'::jsonb)
  into v_rows,v_missing;

  return jsonb_build_object(
    'scenario_id',v_scenario,'scenario_name',v_scenario_name,
    'targets',v_rows,'missing_mappings',v_missing,
    'complete',jsonb_array_length(v_missing)=0);
end $$;

revoke all on function public.monthly_close_automatic_target_preview(uuid,date)
  from public,anon;
grant execute on function public.monthly_close_automatic_target_preview(uuid,date)
  to authenticated;

comment on function public.monthly_close_automatic_target_preview(uuid,date) is
  'R2.5 planning-only preview. Uses the applicable Budget Intelligence scenario and splits multi-account envelopes proportionally to canonical scenario steps; creates no financial entry.';

commit;
