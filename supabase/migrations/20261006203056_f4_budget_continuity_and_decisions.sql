-- F4: budget continuity, revision-bound approvals and planning decisions.
-- Planning metadata never writes a FinancialEvent or a ledger entry.
begin;

alter table public.budget_periods
  add column if not exists copied_from_period_id uuid references public.budget_periods(id) on delete set null,
  add column if not exists configuration_revision integer not null default 1;

alter table public.priority_plan_items
  add constraint priority_plan_items_id_household_unique unique (id, household_id);

create table if not exists public.budget_run_approvals (
  run_id uuid not null,
  household_id uuid not null,
  member_user_id uuid not null,
  revision_hash text not null,
  approved_at timestamptz not null default now(),
  primary key (run_id, member_user_id),
  foreign key (run_id, household_id) references public.budget_allocation_runs(id, household_id) on delete cascade,
  foreign key (household_id, member_user_id) references public.household_members(household_id, user_id) on delete cascade
);

create table if not exists public.shopping_financing_plans (
  shopping_item_id uuid primary key,
  household_id uuid not null,
  strategy text not null check (strategy in ('surplus','projected_bonus','savings','selected_envelope','combined')),
  planned_amount numeric(14,2) check (planned_amount is null or planned_amount > 0),
  projected_bonus_amount numeric(14,2) check (projected_bonus_amount is null or projected_bonus_amount > 0),
  source_envelope_id uuid,
  scenario_id uuid,
  notes text,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  foreign key (shopping_item_id, household_id) references public.shopping_items(id, household_id) on delete cascade,
  foreign key (source_envelope_id, household_id) references public.envelopes(id, household_id) on delete restrict,
  foreign key (scenario_id, household_id) references public.budget_scenarios(id, household_id) on delete set null
);

create table if not exists public.priority_item_decisions (
  priority_plan_item_id uuid primary key,
  household_id uuid not null,
  decision text not null check (decision in ('buy_now','wait','fund_progressively')),
  scenario_id uuid,
  note text,
  decided_by uuid not null references auth.users(id),
  decided_at timestamptz not null default now(),
  revision integer not null default 1,
  foreign key (priority_plan_item_id, household_id) references public.priority_plan_items(id, household_id) on delete cascade,
  foreign key (scenario_id, household_id) references public.budget_scenarios(id, household_id) on delete set null
);

alter table public.budget_run_approvals enable row level security;
alter table public.shopping_financing_plans enable row level security;
alter table public.priority_item_decisions enable row level security;
revoke all on public.budget_run_approvals, public.shopping_financing_plans,
  public.priority_item_decisions from public, anon;
grant select on public.budget_run_approvals, public.shopping_financing_plans,
  public.priority_item_decisions to authenticated;

create policy "members read budget approvals" on public.budget_run_approvals
  for select to authenticated using (public.is_household_member(household_id));
create policy "members read shopping financing" on public.shopping_financing_plans
  for select to authenticated using (public.is_household_member(household_id));
create policy "members read priority decisions" on public.priority_item_decisions
  for select to authenticated using (public.is_household_member(household_id));

create or replace function public.budget_run_revision_hash(p_run_id uuid, p_household_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select encode(extensions.digest(concat_ws('|', r.id::text, r.budget_period_id::text,
    r.scenario_id::text, coalesce(r.scenario_version_id::text, ''),
    r.available_resources::text, r.calculated_total::text,
    r.remaining_unallocated::text, r.summary::text,
    coalesce(string_agg(concat_ws(':', l.id::text, l.envelope_id::text,
      l.planned_allocation::text, l.priority::text, coalesce(l.contribution::text,'')),
      '|' order by l.priority, l.id), '')), 'sha256'), 'hex')
  from public.budget_allocation_runs r
  left join public.budget_allocation_run_lines l on l.run_id = r.id and l.household_id = r.household_id
  where r.id = p_run_id and r.household_id = p_household_id
  group by r.id;
$$;

create or replace function public.prepare_budget_period_v2(
  p_household_id uuid, p_starts_on date, p_mode text, p_source_period_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_period_id uuid; v_source public.budget_periods%rowtype;
  v_new_scenario uuid; v_new_version uuid; v_source_row record;
  v_source_map jsonb := '{}'::jsonb; v_new_source uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if date_trunc('month', p_starts_on)::date <> p_starts_on then raise exception 'Period must start on the first day of a month'; end if;
  if p_mode not in ('empty','copy_previous') then raise exception 'Invalid preparation mode'; end if;
  select id into v_period_id from public.budget_periods where household_id=p_household_id and starts_on=p_starts_on;
  if found then return v_period_id; end if;
  if p_mode = 'copy_previous' then
    select * into v_source from public.budget_periods where id=p_source_period_id and household_id=p_household_id;
    if not found then raise exception 'Source period does not belong to household'; end if;
    if v_source.scenario_id is not null then
      insert into public.budget_scenarios(household_id,name,description,active,priority,valid_from,valid_to,trigger_type,trigger_definition,notes,created_by,is_default)
      select household_id, name || ' — ' || to_char(p_starts_on,'YYYY-MM'), description, true, priority,
        p_starts_on, (p_starts_on + interval '1 month - 1 day')::date, trigger_type, trigger_definition,
        concat_ws(E'\n',notes,'Copié depuis la période '||v_source.starts_on::text), auth.uid(), false
      from public.budget_scenarios where id=v_source.scenario_id and household_id=p_household_id
      returning id into v_new_scenario;
      insert into public.budget_scenario_rules(household_id,scenario_id,envelope_id,allocation_method,amount,percentage,minimum_amount,maximum_amount,priority,rollover_policy,rollover_cap,funding_source_preference,contribution_rule,contribution_definition,notes,active,funding_mode,funding_member_user_id,funding_definition)
      select household_id,v_new_scenario,envelope_id,allocation_method,amount,percentage,minimum_amount,maximum_amount,priority,rollover_policy,rollover_cap,funding_source_preference,contribution_rule,contribution_definition,notes,active,funding_mode,funding_member_user_id,funding_definition
      from public.budget_scenario_rules where scenario_id=v_source.scenario_id and household_id=p_household_id;
      insert into public.budget_scenario_member_incomes(household_id,scenario_id,member_user_id,net_recurring_income,other_recurring_income,exceptional_income,exceptional_treatment,notes)
      select household_id,v_new_scenario,member_user_id,net_recurring_income,other_recurring_income,exceptional_income,exceptional_treatment,notes
      from public.budget_scenario_member_incomes where scenario_id=v_source.scenario_id and household_id=p_household_id;
      insert into public.budget_scenario_versions(household_id,scenario_id,version,notes,created_by)
      select p_household_id,v_new_scenario,1,concat('Copie indépendante de la version ',v.version),auth.uid()
      from public.budget_scenarios s join public.budget_scenario_versions v on v.id=s.current_version_id
      where s.id=v_source.scenario_id and s.household_id=p_household_id returning id into v_new_version;
      if v_new_version is not null then
        for v_source_row in select src.* from public.budget_scenario_sources src join public.budget_scenarios s on s.current_version_id=src.scenario_version_id where s.id=v_source.scenario_id and s.household_id=p_household_id loop
          insert into public.budget_scenario_sources(household_id,scenario_version_id,source_type,name,expected_amount,member_user_id,exceptional_treatment,active)
          values(p_household_id,v_new_version,v_source_row.source_type,v_source_row.name,v_source_row.expected_amount,v_source_row.member_user_id,v_source_row.exceptional_treatment,v_source_row.active)
          returning id into v_new_source;
          v_source_map := v_source_map || jsonb_build_object(v_source_row.id::text,v_new_source::text);
        end loop;
        insert into public.budget_scenario_steps(household_id,scenario_version_id,step_order,group_name,source_id,envelope_id,allocation_method,amount,percentage,contribution_key,member_user_id,key_definition,insufficient_funds_policy,funding_source_preference,active)
        select p_household_id,v_new_version,st.step_order,st.group_name,(v_source_map->>st.source_id::text)::uuid,st.envelope_id,st.allocation_method,st.amount,st.percentage,st.contribution_key,st.member_user_id,st.key_definition,st.insufficient_funds_policy,st.funding_source_preference,st.active
        from public.budget_scenario_steps st join public.budget_scenarios s on s.current_version_id=st.scenario_version_id where s.id=v_source.scenario_id and s.household_id=p_household_id;
        update public.budget_scenarios set current_version_id=v_new_version where id=v_new_scenario;
      end if;
    end if;
  end if;
  insert into public.budget_periods(household_id, starts_on, ends_on, status, scenario_id, created_by, copied_from_period_id)
  values (p_household_id, p_starts_on, (p_starts_on + interval '1 month - 1 day')::date,
    'draft', case when p_mode='empty' then null else v_new_scenario end, auth.uid(),
    case when p_mode='copy_previous' then v_source.id else null end)
  returning id into v_period_id;
  return v_period_id;
end;
$$;

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
    update public.budget_allocation_runs set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_run_id and household_id=p_household_id;
  else
    update public.budget_allocation_runs set status='simulated',approved_by=null,approved_at=null where id=p_run_id and household_id=p_household_id;
  end if;
end;
$$;

create or replace function public.assert_budget_run_approved_for_current_revision()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_mode text; v_hash text; v_required integer; v_count integer;
begin
  if new.status <> 'applied' or old.status='applied' then return new; end if;
  v_hash:=public.budget_run_revision_hash(new.id,new.household_id);
  select budget_validation_mode into v_mode from public.households where id=new.household_id;
  select count(*) into v_required from public.household_members where household_id=new.household_id;
  select count(*) into v_count from public.budget_run_approvals where run_id=new.id and household_id=new.household_id and revision_hash=v_hash;
  if v_count < (case when v_mode='joint_required' then v_required else 1 end) then raise exception 'Budget approvals are incomplete or obsolete'; end if;
  return new;
end;
$$;
drop trigger if exists budget_run_apply_requires_approval on public.budget_allocation_runs;
create trigger budget_run_apply_requires_approval before update of status on public.budget_allocation_runs
for each row execute function public.assert_budget_run_approved_for_current_revision();

create or replace function public.set_shopping_financing_plan(
 p_household_id uuid,p_shopping_item_id uuid,p_strategy text,p_planned_amount numeric,
 p_projected_bonus_amount numeric default null,p_source_envelope_id uuid default null,
 p_scenario_id uuid default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 if not exists(select 1 from public.shopping_items where id=p_shopping_item_id and household_id=p_household_id and status='planned') then raise exception 'Shopping item unavailable'; end if;
 insert into public.shopping_financing_plans(shopping_item_id,household_id,strategy,planned_amount,projected_bonus_amount,source_envelope_id,scenario_id,notes,updated_by)
 values(p_shopping_item_id,p_household_id,p_strategy,p_planned_amount,p_projected_bonus_amount,p_source_envelope_id,p_scenario_id,p_notes,auth.uid())
 on conflict(shopping_item_id) do update set strategy=excluded.strategy,planned_amount=excluded.planned_amount,
 projected_bonus_amount=excluded.projected_bonus_amount,source_envelope_id=excluded.source_envelope_id,
 scenario_id=excluded.scenario_id,notes=excluded.notes,updated_by=auth.uid(),updated_at=now();
 return p_shopping_item_id;
end; $$;

create or replace function public.set_priority_item_decision(
 p_household_id uuid,p_priority_plan_item_id uuid,p_decision text,p_scenario_id uuid default null,p_note text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 if not exists(select 1 from public.priority_plan_items where id=p_priority_plan_item_id and household_id=p_household_id) then raise exception 'Priority item unavailable'; end if;
 insert into public.priority_item_decisions(priority_plan_item_id,household_id,decision,scenario_id,note,decided_by)
 values(p_priority_plan_item_id,p_household_id,p_decision,p_scenario_id,p_note,auth.uid())
 on conflict(priority_plan_item_id) do update set decision=excluded.decision,scenario_id=excluded.scenario_id,note=excluded.note,
 decided_by=auth.uid(),decided_at=now(),revision=public.priority_item_decisions.revision+1;
 return p_priority_plan_item_id;
end; $$;

revoke all on function public.budget_run_revision_hash(uuid,uuid), public.prepare_budget_period_v2(uuid,date,text,uuid),
 public.approve_budget_allocation_run(uuid,uuid), public.set_shopping_financing_plan(uuid,uuid,text,numeric,numeric,uuid,uuid,text),
 public.set_priority_item_decision(uuid,uuid,text,uuid,text) from public,anon;
grant execute on function public.prepare_budget_period_v2(uuid,date,text,uuid), public.approve_budget_allocation_run(uuid,uuid),
 public.set_shopping_financing_plan(uuid,uuid,text,numeric,numeric,uuid,uuid,text),
 public.set_priority_item_decision(uuid,uuid,text,uuid,text) to authenticated;

commit;
