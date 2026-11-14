-- A1/A2: explicit economic responsibility and generic monthly savings sweep.
-- Additive only: historical migrations and canonical financial ledgers stay intact.
begin;

create table public.economic_responsibility_assignments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  subject_kind text not null check (subject_kind in ('financial_event','reconciliation_observation')),
  subject_id uuid not null,
  responsibility_kind text not null check (responsibility_kind in ('household','member')),
  member_user_id uuid,
  reason text,
  effective_at timestamptz not null default now(),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  check ((responsibility_kind='household')=(member_user_id is null)),
  foreign key (household_id,created_by)
    references public.household_members(household_id,user_id) on delete restrict,
  foreign key (household_id,member_user_id)
    references public.household_members(household_id,user_id) on delete restrict,
  unique(household_id,subject_kind,subject_id,responsibility_kind,member_user_id)
);
create unique index economic_responsibility_one_household_idx
  on public.economic_responsibility_assignments(household_id,subject_kind,subject_id)
  where responsibility_kind='household';
alter table public.economic_responsibility_assignments enable row level security;
revoke all on public.economic_responsibility_assignments from public,anon;
grant select on public.economic_responsibility_assignments to authenticated;
create policy economic_responsibility_read
  on public.economic_responsibility_assignments for select to authenticated
  using(public.is_household_member(household_id));

create or replace function public.set_economic_responsibilities(
  p_household_id uuid,p_subject_kind text,p_subject_id uuid,
  p_responsibility_kind text,p_member_user_ids uuid[],p_reason text
) returns void language plpgsql security definer set search_path=public,auth as $$
declare v_member uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_subject_kind not in ('financial_event','reconciliation_observation')
    or p_responsibility_kind not in ('unassigned','household','member') then
    raise exception 'Invalid responsibility assignment';
  end if;
  if p_subject_kind='financial_event' and not exists(
    select 1 from public.financial_events where id=p_subject_id and household_id=p_household_id
  ) then raise exception 'Financial event access denied'; end if;
  if p_subject_kind='reconciliation_observation' and not exists(
    select 1 from public.account_balance_observations where id=p_subject_id and household_id=p_household_id
  ) then raise exception 'Reconciliation access denied'; end if;
  delete from public.economic_responsibility_assignments
    where household_id=p_household_id and subject_kind=p_subject_kind and subject_id=p_subject_id;
  if p_responsibility_kind='unassigned' then return; end if;
  if p_responsibility_kind='household' then
    insert into public.economic_responsibility_assignments(
      household_id,subject_kind,subject_id,responsibility_kind,reason,created_by
    ) values(p_household_id,p_subject_kind,p_subject_id,'household',nullif(trim(p_reason),''),auth.uid());
    return;
  end if;
  if coalesce(cardinality(p_member_user_ids),0)=0 then
    raise exception 'At least one explicit member is required';
  end if;
  foreach v_member in array p_member_user_ids loop
    if not exists(select 1 from public.household_members where household_id=p_household_id and user_id=v_member) then
      raise exception 'Responsible member access denied';
    end if;
    insert into public.economic_responsibility_assignments(
      household_id,subject_kind,subject_id,responsibility_kind,member_user_id,reason,created_by
    ) values(p_household_id,p_subject_kind,p_subject_id,'member',v_member,nullif(trim(p_reason),''),auth.uid())
    on conflict do nothing;
  end loop;
end $$;
revoke all on function public.set_economic_responsibilities(uuid,text,uuid,text,uuid[],text) from public,anon;
grant execute on function public.set_economic_responsibilities(uuid,text,uuid,text,uuid[],text) to authenticated;

create table public.monthly_envelope_sweep_rules (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  source_envelope_id uuid not null,
  destination_envelope_id uuid not null,
  active boolean not null default true,
  effective_from date not null default current_date,
  effective_until date,
  reason text not null default 'Reliquat mensuel positif',
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (source_envelope_id,household_id) references public.envelopes(id,household_id) on delete restrict,
  foreign key (destination_envelope_id,household_id) references public.envelopes(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict,
  check (source_envelope_id<>destination_envelope_id),
  check (effective_until is null or effective_until>=effective_from)
);
create unique index monthly_envelope_sweep_rules_active_source_idx
  on public.monthly_envelope_sweep_rules(household_id,source_envelope_id)
  where active;
create index monthly_envelope_sweep_rules_destination_idx
  on public.monthly_envelope_sweep_rules(household_id,destination_envelope_id) where active;
alter table public.monthly_envelope_sweep_rules enable row level security;
revoke all on public.monthly_envelope_sweep_rules from public,anon;
grant select on public.monthly_envelope_sweep_rules to authenticated;
create policy monthly_envelope_sweep_rules_read
  on public.monthly_envelope_sweep_rules for select to authenticated
  using(public.is_household_member(household_id));

-- Pilot materialisation is data seeding only. Runtime functions below never use names.
insert into public.monthly_envelope_sweep_rules(
  household_id,source_envelope_id,destination_envelope_id,effective_from,reason,created_by
)
select h.id,s.id,d.id,date '2026-09-01','Reliquat mensuel positif',owner.user_id
from public.households h
join public.household_members owner on owner.household_id=h.id and owner.role='owner'
join public.envelopes d on d.household_id=h.id and d.name='Epargne' and d.archived_at is null
join public.envelopes s on s.household_id=h.id and s.name in ('Navette','Nourriture','Sorties WE') and s.archived_at is null
where h.name='FINANCIEL PILOTE — FOYER RÉEL' and h.classification='operational'
on conflict do nothing;

create or replace function public.set_monthly_envelope_sweep_rule(
  p_household_id uuid,p_source_envelope_id uuid,p_destination_envelope_id uuid,
  p_active boolean,p_effective_from date,p_effective_until date,p_reason text
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if p_source_envelope_id=p_destination_envelope_id then raise exception 'Sweep source and destination must differ'; end if;
  if not exists(select 1 from public.envelopes where id=p_source_envelope_id and household_id=p_household_id and archived_at is null and not is_system)
    or not exists(select 1 from public.envelopes where id=p_destination_envelope_id and household_id=p_household_id and archived_at is null and not is_system)
  then raise exception 'Sweep envelopes must be active ordinary household envelopes'; end if;
  update public.monthly_envelope_sweep_rules set
    destination_envelope_id=p_destination_envelope_id,active=p_active,
    effective_from=p_effective_from,effective_until=p_effective_until,
    reason=coalesce(nullif(trim(p_reason),''),'Reliquat mensuel positif'),updated_at=now()
  where household_id=p_household_id and source_envelope_id=p_source_envelope_id and active
  returning id into v_id;
  if v_id is null then
    insert into public.monthly_envelope_sweep_rules(
      household_id,source_envelope_id,destination_envelope_id,active,effective_from,effective_until,reason,created_by
    ) values(p_household_id,p_source_envelope_id,p_destination_envelope_id,p_active,p_effective_from,p_effective_until,
      coalesce(nullif(trim(p_reason),''),'Reliquat mensuel positif'),auth.uid()) returning id into v_id;
  end if;
  return v_id;
end $$;
revoke all on function public.set_monthly_envelope_sweep_rule(uuid,uuid,uuid,boolean,date,date,text) from public,anon;
grant execute on function public.set_monthly_envelope_sweep_rule(uuid,uuid,uuid,boolean,date,date,text) to authenticated;

create or replace function public.monthly_savings_sweep_preview(p_household_id uuid,p_month_start date)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if p_month_start<>date_trunc('month',p_month_start)::date then raise exception 'Invalid month'; end if;
  select jsonb_build_object(
    'month_start',p_month_start,
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'rule_id',r.id,'source_envelope_id',s.id,'source_name',s.name,
      'destination_envelope_id',d.id,'destination_name',d.name,
      'before_amount',coalesce(b.balance,0),'proposed_amount',greatest(coalesce(b.balance,0),0),
      'after_amount',least(coalesce(b.balance,0),0),'reason',r.reason,
      'scope','household','creates_bank_transfer',false,'creates_gl',false
    ) order by s.name) filter(where r.id is not null),'[]'::jsonb),
    'total',coalesce(sum(greatest(coalesce(b.balance,0),0)) filter(where r.id is not null),0),
    'creates_bank_transfer',false,'creates_gl',false,'creates_competing_financial_event',false
  ) into v_result
  from public.monthly_envelope_sweep_rules r
  join public.envelopes s on s.id=r.source_envelope_id and s.household_id=r.household_id and s.archived_at is null
  join public.envelopes d on d.id=r.destination_envelope_id and d.household_id=r.household_id and d.archived_at is null
  left join public.envelope_ledger_balances b on b.envelope_id=s.id
  where r.household_id=p_household_id and r.active and r.effective_from<=p_month_start
    and (r.effective_until is null or r.effective_until>=p_month_start);
  return v_result;
end $$;

create or replace function public.execute_monthly_savings_sweep(p_household_id uuid,p_month_start date)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_role text; v_rule record; v_amount numeric(14,2); v_key uuid; v_event uuid;
  v_batch uuid; v_position record; v_snapshot jsonb; v_items jsonb:='[]'::jsonb; v_replayed boolean:=true;
begin
  select role into v_role from public.household_members where household_id=p_household_id and user_id=auth.uid();
  if v_role is null then raise exception 'Household access denied'; end if;
  if p_month_start<>date_trunc('month',p_month_start)::date then raise exception 'Invalid month'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_household_id::text||p_month_start::text,0));
  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then raise exception 'Current account x envelope positions must be reliable before savings sweep'; end if;
  for v_rule in
    select r.id rule_id,r.source_envelope_id,r.destination_envelope_id,r.reason,
      s.name source_name,d.name destination_name,coalesce(b.balance,0)::numeric(14,2) balance
    from public.monthly_envelope_sweep_rules r
    join public.envelopes s on s.id=r.source_envelope_id and s.household_id=r.household_id and s.archived_at is null
    join public.envelopes d on d.id=r.destination_envelope_id and d.household_id=r.household_id and d.archived_at is null
    left join public.envelope_ledger_balances b on b.envelope_id=s.id
    where r.household_id=p_household_id and r.active and r.effective_from<=p_month_start
      and (r.effective_until is null or r.effective_until>=p_month_start)
    order by r.id
  loop
    v_key:=public.r2_7_deterministic_uuid('monthly-savings-sweep|'||p_household_id||'|'||p_month_start||'|'||v_rule.rule_id);
    if exists(select 1 from public.monthly_savings_sweeps where household_id=p_household_id and month_start=p_month_start and source_envelope_id=v_rule.source_envelope_id) then
      select amount,financial_event_id into v_amount,v_event from public.monthly_savings_sweeps
        where household_id=p_household_id and month_start=p_month_start and source_envelope_id=v_rule.source_envelope_id;
      v_items:=v_items||jsonb_build_array(jsonb_build_object('source_envelope_id',v_rule.source_envelope_id,
        'destination_envelope_id',v_rule.destination_envelope_id,'amount',v_amount,'financial_event_id',v_event,'replayed',true));
      continue;
    end if;
    v_replayed:=false; v_amount:=greatest(v_rule.balance,0); v_event:=null; v_batch:=null;
    if v_amount>0 then
      v_event:=public.create_envelope_transfer_event(p_household_id,(p_month_start+interval '1 month')::timestamptz,
        'Reliquat mensuel '||v_rule.source_name||' vers '||v_rule.destination_name,v_amount,
        v_rule.source_envelope_id,v_rule.destination_envelope_id,v_rule.reason,v_key);
      v_batch:=public.r2_7_deterministic_uuid('position-batch|'||v_key);
      insert into public.envelope_account_position_batches(id,household_id,batch_kind,month_start,idempotency_key,note,created_by)
        values(v_batch,p_household_id,'monthly_savings_sweep',p_month_start,v_key,'Projection analytique sur les mêmes comptes physiques',auth.uid());
      for v_position in select account_id,amount from public.envelope_account_current_positions
        where household_id=p_household_id and envelope_id=v_rule.source_envelope_id and amount>0 order by account_id
      loop
        insert into public.envelope_account_position_entries(household_id,batch_id,financial_event_id,account_id,envelope_id,amount,created_by) values
          (p_household_id,v_batch,v_event,v_position.account_id,v_rule.source_envelope_id,-v_position.amount,auth.uid()),
          (p_household_id,v_batch,v_event,v_position.account_id,v_rule.destination_envelope_id,v_position.amount,auth.uid());
      end loop;
    end if;
    insert into public.monthly_savings_sweeps(household_id,month_start,source_envelope_id,destination_envelope_id,amount,
      financial_event_id,position_batch_id,idempotency_key,created_by)
      values(p_household_id,p_month_start,v_rule.source_envelope_id,v_rule.destination_envelope_id,v_amount,v_event,v_batch,v_key,auth.uid());
    v_items:=v_items||jsonb_build_array(jsonb_build_object('source_envelope_id',v_rule.source_envelope_id,
      'destination_envelope_id',v_rule.destination_envelope_id,'amount',v_amount,'financial_event_id',v_event,'replayed',false));
  end loop;
  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then raise exception 'Savings sweep position invariant failed'; end if;
  return jsonb_build_object('month_start',p_month_start,'items',v_items,'replayed',v_replayed,
    'creates_bank_transfer',false,'creates_gl',false,'snapshot_fingerprint',v_snapshot->>'fingerprint');
end $$;

-- Active destinations carry a configurable role and cannot be archived/deleted.
create or replace function public.update_household_envelope(p_household_id uuid,p_envelope_id uuid,p_name text,p_notes text,p_archived boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Envelope name is required'; end if;
  if p_archived and exists(select 1 from public.monthly_envelope_sweep_rules where household_id=p_household_id and destination_envelope_id=p_envelope_id and active) then
    raise exception 'Active savings sweep destination must be reassigned or disabled before archival';
  end if;
  if exists(select 1 from public.envelopes where household_id=p_household_id and id<>p_envelope_id
    and lower(regexp_replace(trim(name),'\s+',' ','g'))=lower(regexp_replace(trim(p_name),'\s+',' ','g'))) then
    raise exception 'Envelope name already exists';
  end if;
  update public.envelopes set name=regexp_replace(trim(p_name),'\s+',' ','g'),notes=nullif(trim(coalesce(p_notes,'')),''),
    archived_at=case when p_archived then coalesce(archived_at,now()) else null end
    where id=p_envelope_id and household_id=p_household_id and not is_system;
  if not found then raise exception 'Envelope not found or protected'; end if;
end $$;

create or replace function public.delete_household_envelope(p_household_id uuid,p_envelope_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if exists(select 1 from public.monthly_envelope_sweep_rules where household_id=p_household_id and destination_envelope_id=p_envelope_id and active) then
    raise exception 'Active savings sweep destination must be reassigned or disabled before deletion';
  end if;
  if exists(select 1 from public.envelope_movements where envelope_id=p_envelope_id and household_id=p_household_id) then
    raise exception 'Envelope with ledger history must be archived';
  end if;
  delete from public.envelopes where id=p_envelope_id and household_id=p_household_id and not is_system;
  if not found then raise exception 'Envelope not found or protected'; end if;
end $$;

revoke all on function public.monthly_savings_sweep_preview(uuid,date),public.execute_monthly_savings_sweep(uuid,date) from public,anon;
grant execute on function public.monthly_savings_sweep_preview(uuid,date),public.execute_monthly_savings_sweep(uuid,date) to authenticated;

comment on table public.economic_responsibility_assignments is
  'Explicit economic responsibility only. Recorder, account holder, payment method and envelope never imply responsibility.';
comment on table public.monthly_envelope_sweep_rules is
  'Household-configurable analytical source-to-destination sweep rules keyed only by canonical IDs.';

commit;
