-- R2.3: automatic envelope/account targets and reliability gates.
-- Planning remains non-financial; no FinancialEvent or ledger entry is created here.
begin;

alter table public.monthly_envelope_account_targets
  add column if not exists target_source text not null default 'manual_override'
    check (target_source in ('automatic','manual_override')),
  add column if not exists source_scenario_id uuid,
  add column if not exists source_label text,
  add column if not exists override_reason text;

alter table public.monthly_envelope_account_targets
  drop constraint if exists monthly_targets_source_scenario_household_fk,
  add constraint monthly_targets_source_scenario_household_fk
    foreign key (source_scenario_id, household_id)
    references public.budget_scenarios(id, household_id) on delete set null;

create or replace function public.r2_require_reliable_balances_before_snapshot()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
  if new.batch_kind='explicit_snapshot' then
    if exists(select 1 from public.account_reconciliation_cases c
      where c.household_id=new.household_id and c.status in ('open','partially_resolved','explained_pending')) then
      raise exception 'Account reconciliations must be resolved before matrix initialization';
    end if;
    if exists(select 1 from public.accounts a where a.household_id=new.household_id
      and a.archived_at is null and not a.is_system and a.kind in ('bank','cash','savings')
      and not exists(select 1 from public.account_balance_observations o
        where o.account_id=a.id and o.household_id=a.household_id
          and o.observed_at>=date_trunc('month',current_date))) then
      raise exception 'Current-month account inventories are required before matrix initialization';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.r2_require_reliable_balances_before_snapshot() from public,anon,authenticated;
drop trigger if exists r2_position_snapshot_reliability on public.envelope_account_position_batches;
create trigger r2_position_snapshot_reliability before insert on public.envelope_account_position_batches
for each row execute function public.r2_require_reliable_balances_before_snapshot();

create or replace function public.monthly_close_automatic_target_preview(
  p_household_id uuid, p_month_start date
) returns jsonb language plpgsql stable security definer
set search_path=public,auth as $$
declare v_scenario uuid; v_scenario_name text; v_rows jsonb; v_missing jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_month_start<>date_trunc('month',p_month_start)::date then raise exception 'Invalid month'; end if;

  select p.scenario_id,s.name into v_scenario,v_scenario_name
  from public.budget_periods p join public.budget_scenarios s on s.id=p.scenario_id and s.household_id=p.household_id
  where p.household_id=p_household_id and p.status='active'
    and p.starts_on<=p_month_start and p.ends_on>=p_month_start
  order by p.starts_on desc limit 1;
  if v_scenario is null then
    select s.id,s.name into v_scenario,v_scenario_name from public.budget_scenarios s
    where s.household_id=p_household_id and s.active
      and (s.valid_from is null or s.valid_from<=p_month_start)
      and (s.valid_to is null or s.valid_to>=p_month_start)
    order by s.priority asc,s.is_default desc,s.created_at desc limit 1;
  end if;

  with mapping as (
    select e.id envelope_id,e.name envelope_name,b.balance,
      coalesce(e.recommended_account_id,
        case when count(distinct st.funding_source_preference) filter(where st.funding_source_preference is not null)=1
          then min(st.funding_source_preference::text)::uuid end) account_id,
      case when e.recommended_account_id is not null then 'Recommandation de l’enveloppe'
        when count(distinct st.funding_source_preference) filter(where st.funding_source_preference is not null)=1
          then 'Scénario '||coalesce(v_scenario_name,'actif') else null end source_label
    from public.envelopes e
    join public.envelope_ledger_balances b on b.envelope_id=e.id and b.household_id=e.household_id
    left join public.budget_scenarios s on s.id=v_scenario and s.household_id=e.household_id
    left join public.budget_scenario_steps st on st.scenario_version_id=s.current_version_id
      and st.household_id=e.household_id and st.envelope_id=e.id and st.active
    where e.household_id=p_household_id and e.archived_at is null
    group by e.id,e.name,b.balance,e.recommended_account_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('envelope_id',envelope_id,'envelope_name',envelope_name,
    'account_id',account_id,'target_amount',balance,'source_label',source_label)
    order by envelope_name) filter(where account_id is not null),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('envelope_id',envelope_id,'envelope_name',envelope_name,
      'balance',balance,'reason','Aucun compte cible canonique unique') order by envelope_name)
      filter(where account_id is null and balance<>0),'[]'::jsonb)
  into v_rows,v_missing from mapping;

  return jsonb_build_object('scenario_id',v_scenario,'scenario_name',v_scenario_name,
    'targets',v_rows,'missing_mappings',v_missing,'complete',jsonb_array_length(v_missing)=0);
end $$;

create or replace function public.refresh_monthly_automatic_targets(
  p_household_id uuid,p_month_start date,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_preview jsonb; v_row jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.household_members
    where household_id=p_household_id and user_id=auth.uid() and role='owner') then
    raise exception 'Owner access denied';
  end if;
  if exists(select 1 from public.monthly_close_periods where household_id=p_household_id
    and month_start=p_month_start and status='closed') then raise exception 'Closed month targets are immutable'; end if;
  v_preview:=public.monthly_close_automatic_target_preview(p_household_id,p_month_start);
  delete from public.monthly_envelope_account_targets where household_id=p_household_id
    and month_start=p_month_start and target_source='automatic';
  for v_row in select * from jsonb_array_elements(v_preview->'targets') loop
    insert into public.monthly_envelope_account_targets(household_id,month_start,envelope_id,account_id,
      target_amount,created_by,target_source,source_scenario_id,source_label)
    values(p_household_id,p_month_start,(v_row->>'envelope_id')::uuid,(v_row->>'account_id')::uuid,
      (v_row->>'target_amount')::numeric,auth.uid(),'automatic',(v_preview->>'scenario_id')::uuid,
      v_row->>'source_label')
    on conflict(household_id,month_start,envelope_id,account_id) do update set
      target_amount=case when monthly_envelope_account_targets.target_source='manual_override'
        then monthly_envelope_account_targets.target_amount else excluded.target_amount end,
      target_source=case when monthly_envelope_account_targets.target_source='manual_override'
        then 'manual_override' else 'automatic' end,
      source_scenario_id=case when monthly_envelope_account_targets.target_source='manual_override'
        then monthly_envelope_account_targets.source_scenario_id else excluded.source_scenario_id end,
      source_label=case when monthly_envelope_account_targets.target_source='manual_override'
        then monthly_envelope_account_targets.source_label else excluded.source_label end,
      created_at=now();
  end loop;
  return v_preview;
end $$;

create or replace function public.set_monthly_envelope_account_target_override(
  p_household_id uuid,p_month_start date,p_envelope_id uuid,p_account_id uuid,
  p_target_amount numeric,p_reason text,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
  if auth.uid() is null or not exists(select 1 from public.household_members
    where household_id=p_household_id and user_id=auth.uid() and role='owner') then raise exception 'Owner access denied'; end if;
  if p_month_start<>date_trunc('month',p_month_start)::date or p_target_amount<0
    or nullif(trim(p_reason),'') is null then raise exception 'Invalid manual override'; end if;
  if not exists(select 1 from public.envelopes where id=p_envelope_id and household_id=p_household_id and archived_at is null)
    or not exists(select 1 from public.accounts where id=p_account_id and household_id=p_household_id and archived_at is null and not is_system)
    then raise exception 'Target reference denied'; end if;
  if exists(select 1 from public.monthly_close_periods where household_id=p_household_id
    and month_start=p_month_start and status='closed') then raise exception 'Closed month targets are immutable'; end if;
  insert into public.monthly_envelope_account_target_events(household_id,month_start,envelope_id,account_id,target_amount,idempotency_key,created_by)
  values(p_household_id,p_month_start,p_envelope_id,p_account_id,p_target_amount,p_idempotency_key,auth.uid())
  on conflict(household_id,idempotency_key) do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.monthly_envelope_account_target_events
    where household_id=p_household_id and idempotency_key=p_idempotency_key; return v_id; end if;
  insert into public.monthly_envelope_account_targets(household_id,month_start,envelope_id,account_id,
    target_amount,created_by,target_source,source_label,override_reason)
  values(p_household_id,p_month_start,p_envelope_id,p_account_id,p_target_amount,auth.uid(),
    'manual_override','Dérogation manuelle pour ce mois',trim(p_reason))
  on conflict(household_id,month_start,envelope_id,account_id) do update set
    target_amount=excluded.target_amount,created_by=excluded.created_by,created_at=now(),
    target_source='manual_override',source_scenario_id=null,source_label=excluded.source_label,
    override_reason=excluded.override_reason;
  return v_id;
end $$;

revoke all on function public.monthly_close_automatic_target_preview(uuid,date),
  public.refresh_monthly_automatic_targets(uuid,date,uuid),
  public.set_monthly_envelope_account_target_override(uuid,date,uuid,uuid,numeric,text,uuid)
  from public,anon;
grant execute on function public.monthly_close_automatic_target_preview(uuid,date),
  public.refresh_monthly_automatic_targets(uuid,date,uuid),
  public.set_monthly_envelope_account_target_override(uuid,date,uuid,uuid,numeric,text,uuid)
  to authenticated;

commit;
