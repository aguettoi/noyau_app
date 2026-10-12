-- R2.7 — classify the canonical envelope funding rule without conflating it
-- with a payment method or with the historical account × envelope position.
begin;

alter table public.envelopes
  add column if not exists recommendation_kind text not null default 'unconfigured',
  add column if not exists recommendation_definition jsonb not null default '{}'::jsonb;

alter table public.envelopes
  drop constraint if exists envelopes_recommendation_kind_check;
alter table public.envelopes
  add constraint envelopes_recommendation_kind_check check (
    recommendation_kind in (
      'unconfigured','single_account','scenario_split','member_beneficiary','system'
    )
  );

alter table public.envelope_recommendation_events
  add column if not exists previous_recommendation_kind text,
  add column if not exists recommendation_kind text,
  add column if not exists previous_recommendation_definition jsonb,
  add column if not exists recommendation_definition jsonb,
  add column if not exists change_source text not null default 'user';

create or replace function public.set_envelope_recommendation(
  p_envelope_id uuid,
  p_account_id uuid,
  p_payment_method_id uuid
) returns public.envelopes
language plpgsql security definer set search_path=public,auth as $$
declare
  v public.envelopes; v_household uuid; v_previous_account uuid;
  v_previous_method uuid; v_previous_kind text; v_previous_definition jsonb;
  v_kind text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select household_id,recommended_account_id,recommended_payment_method_id,
    recommendation_kind,recommendation_definition
  into v_household,v_previous_account,v_previous_method,
    v_previous_kind,v_previous_definition
  from public.envelopes where id=p_envelope_id and archived_at is null;
  if v_household is null or not public.is_household_member(v_household) then
    raise exception 'Envelope access denied';
  end if;
  if exists(select 1 from public.envelopes where id=p_envelope_id and is_system) then
    raise exception 'System envelope recommendation is not configurable';
  end if;
  if p_account_id is not null and not exists(
    select 1 from public.accounts where id=p_account_id and household_id=v_household
      and archived_at is null and not is_system
  ) then raise exception 'Account household mismatch or inactive'; end if;
  if p_payment_method_id is not null and not exists(
    select 1 from public.payment_methods where id=p_payment_method_id
      and household_id=v_household and active and archived_at is null
  ) then raise exception 'Payment method household mismatch or inactive'; end if;
  if p_payment_method_id is not null and exists(
    select 1 from public.payment_methods pm where pm.id=p_payment_method_id and (
      (pm.account_id is not null and pm.account_id is distinct from p_account_id)
      or (pm.holder_user_id is not null and p_account_id is not null
        and exists(select 1 from public.accounts a where a.id=p_account_id and a.ownership_type='individual')
        and not exists(select 1 from public.account_holders ah
          where ah.account_id=p_account_id and ah.user_id=pm.holder_user_id))
    )
  ) then raise exception 'Recommendation account or holder mismatch'; end if;

  v_kind:=case when p_account_id is null then 'unconfigured' else 'single_account' end;
  update public.envelopes set
    recommended_account_id=p_account_id,
    recommended_payment_method_id=p_payment_method_id,
    recommendation_kind=v_kind,
    recommendation_definition=case when p_account_id is null then '{}'::jsonb
      else jsonb_build_object('source','user_selection') end
  where id=p_envelope_id returning * into v;

  if v_previous_account is distinct from p_account_id
    or v_previous_method is distinct from p_payment_method_id
    or v_previous_kind is distinct from v_kind then
    insert into public.envelope_recommendation_events(
      household_id,envelope_id,previous_account_id,account_id,
      previous_payment_method_id,payment_method_id,actor_user_id,
      previous_recommendation_kind,recommendation_kind,
      previous_recommendation_definition,recommendation_definition,change_source
    ) values(
      v_household,p_envelope_id,v_previous_account,p_account_id,
      v_previous_method,p_payment_method_id,auth.uid(),
      v_previous_kind,v_kind,v_previous_definition,v.recommendation_definition,'user'
    );
  end if;
  return v;
end $$;

revoke all on function public.set_envelope_recommendation(uuid,uuid,uuid)
  from public,anon;
grant execute on function public.set_envelope_recommendation(uuid,uuid,uuid)
  to authenticated;

-- Materialize only rules certified by the source workbook and the six imported
-- scenarios. Account ids are resolved at deployment; no generated id is embedded.
do $$
declare v_household uuid; v_actor uuid; v_changed integer;
begin
  select id into v_household from public.households
    where name='FINANCIEL PILOTE — FOYER RÉEL' and classification='operational';
  if v_household is null then raise exception 'R2.7 pilot household not found'; end if;
  select user_id into v_actor from public.household_members
    where household_id=v_household and role='owner' order by created_at limit 1;
  if v_actor is null then raise exception 'R2.7 pilot owner not found'; end if;

  create temporary table r2_7_config(
    envelope_name text primary key,account_name text,kind text,definition jsonb
  ) on commit drop;
  insert into r2_7_config values
    ('Traite maison','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Traite normale','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('TSC','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Syndic','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Eau elec abonnement','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Mouton','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Ecole Niece','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Parrents','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Imprévus','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Vignette','Islamique / Arreda Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Epargne','Islamique / Arreda Ibrahim','single_account',
      '{"source":"user_confirmed_r2_7","future_rule":"month_end_remainder","opening_location_confirmed":true,"opening_amount":"18548.56","opening_date":"2026-09-29"}'),
    ('Traite voiture','Banque Nora','single_account','{"source":"certified_scenarios"}'),
    ('Wifi','Banque Nora','single_account','{"source":"certified_scenarios"}'),
    ('Besoin perso','Banque Nora','single_account','{"source":"certified_scenarios"}'),
    ('Parrents Nora','Banque Nora','single_account','{"source":"certified_scenarios"}'),
    ('Vidange','Banque Nora','single_account','{"source":"certified_scenarios"}'),
    ('Entretien','Banque Nora','single_account','{"source":"certified_scenarios"}'),
    ('Assurance','Banque Nora','single_account','{"source":"certified_scenarios","corrects":"Espèces maison"}'),
    ('Nourriture','Espèces maison','single_account','{"source":"certified_scenarios","month_end_sweep_destination":"Epargne"}'),
    ('Navette','Espèces maison','single_account','{"source":"certified_scenarios","month_end_sweep_destination":"Epargne"}'),
    ('Voyages','AWB Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Sorties WE','AWB Ibrahim','single_account','{"source":"certified_scenarios","month_end_sweep_destination":"Epargne"}'),
    ('Fêtes religieuses','AWB Ibrahim','single_account','{"source":"certified_scenarios"}'),
    ('Habits',null,'scenario_split',
      '{"source":"certified_scenarios","strategy":"scenario_member_contributions","opening_split_status":"unconfirmed"}'),
    ('Reste epargne (primes Ibrahim et Nora)',null,'member_beneficiary',
      '{"source":"user_confirmed_r2_7","strategy":"actual_income_recipient_account","recurring":false,"opening_split_status":"unconfirmed"}'),
    ('À répartir',null,'system','{"source":"system","account_required":false}');

  if (select count(*) from r2_7_config)<>26
    or (select count(*) from r2_7_config where kind='single_account')<>23 then
    raise exception 'R2.7 configuration inventory mismatch';
  end if;
  if exists(select 1 from r2_7_config c left join public.envelopes e
    on e.household_id=v_household and e.name=c.envelope_name and e.archived_at is null
    where e.id is null) then raise exception 'R2.7 envelope mapping incomplete'; end if;
  if exists(select 1 from r2_7_config c left join public.accounts a
    on a.household_id=v_household and a.name=c.account_name and a.archived_at is null
      and not a.is_system where c.account_name is not null and a.id is null)
  then raise exception 'R2.7 account mapping incomplete'; end if;

  create temporary table r2_7_before on commit drop as
  select e.id,e.recommended_account_id,e.recommended_payment_method_id,
    e.recommendation_kind,e.recommendation_definition
  from public.envelopes e join r2_7_config c on c.envelope_name=e.name
  where e.household_id=v_household and e.archived_at is null;

  update public.envelopes e set
    recommended_account_id=a.id,
    recommended_payment_method_id=case when e.recommended_payment_method_id is null or exists(
      select 1 from public.payment_methods pm where pm.id=e.recommended_payment_method_id
        and pm.household_id=v_household and pm.active and pm.archived_at is null
        and (pm.account_id is null or pm.account_id=a.id)
    ) then e.recommended_payment_method_id else null end,
    recommendation_kind=c.kind,
    recommendation_definition=c.definition
  from r2_7_config c
  left join public.accounts a on a.household_id=v_household and a.name=c.account_name
    and a.archived_at is null and not a.is_system
  where e.household_id=v_household and e.name=c.envelope_name and e.archived_at is null;

  insert into public.envelope_recommendation_events(
    household_id,envelope_id,previous_account_id,account_id,
    previous_payment_method_id,payment_method_id,actor_user_id,
    previous_recommendation_kind,recommendation_kind,
    previous_recommendation_definition,recommendation_definition,change_source
  )
  select v_household,e.id,b.recommended_account_id,e.recommended_account_id,
    b.recommended_payment_method_id,e.recommended_payment_method_id,v_actor,
    b.recommendation_kind,e.recommendation_kind,
    b.recommendation_definition,e.recommendation_definition,'r2_7_certified_materialization'
  from public.envelopes e join r2_7_before b on b.id=e.id
  where b.recommended_account_id is distinct from e.recommended_account_id
    or b.recommended_payment_method_id is distinct from e.recommended_payment_method_id
    or b.recommendation_kind is distinct from e.recommendation_kind
    or b.recommendation_definition is distinct from e.recommendation_definition;

  get diagnostics v_changed=row_count;
  if v_changed<25 then raise exception 'R2.7 expected configuration changes were not recorded'; end if;
end $$;

-- The sweep is an economic envelope transfer. It deliberately creates no GL
-- posting and mirrors the analytical account x envelope position on the same
-- physical account. A later physical transfer to Arreda remains a separate,
-- explicit account transfer.
alter table public.envelope_account_position_batches
  drop constraint if exists envelope_account_position_batches_batch_kind_check;
alter table public.envelope_account_position_batches
  add constraint envelope_account_position_batches_batch_kind_check check (
    batch_kind in ('explicit_snapshot','monthly_reallocation','canonical_event','monthly_savings_sweep')
  );

create table public.monthly_savings_sweeps (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  month_start date not null check (month_start=date_trunc('month',month_start)::date),
  source_envelope_id uuid not null references public.envelopes(id) on delete restrict,
  destination_envelope_id uuid not null references public.envelopes(id) on delete restrict,
  amount numeric(14,2) not null check (amount>=0),
  financial_event_id uuid references public.financial_events(id) on delete restrict,
  position_batch_id uuid references public.envelope_account_position_batches(id) on delete restrict,
  idempotency_key uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(household_id,month_start,source_envelope_id),
  unique(household_id,idempotency_key),
  check ((amount=0 and financial_event_id is null) or (amount>0 and financial_event_id is not null))
);
create index monthly_savings_sweeps_household_month_idx
  on public.monthly_savings_sweeps(household_id,month_start);
alter table public.monthly_savings_sweeps enable row level security;
revoke all on public.monthly_savings_sweeps from public,anon;
grant select on public.monthly_savings_sweeps to authenticated;
create policy monthly_savings_sweeps_read on public.monthly_savings_sweeps
  for select to authenticated using(public.is_household_member(household_id));

create or replace function public.r2_7_deterministic_uuid(p_value text)
returns uuid language sql immutable strict set search_path=public as $$
  select (substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||
    substr(md5(p_value),14,3)||'-a'||substr(md5(p_value),18,3)||'-'||
    substr(md5(p_value),21,12))::uuid
$$;
revoke all on function public.r2_7_deterministic_uuid(text) from public,anon,authenticated;

create or replace function public.monthly_savings_sweep_preview(
  p_household_id uuid,p_month_start date
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_month_start<>date_trunc('month',p_month_start)::date then raise exception 'Invalid month'; end if;
  select jsonb_build_object(
    'month_start',p_month_start,
    'destination','Epargne',
    'sources',coalesce(jsonb_agg(jsonb_build_object(
      'envelope_id',e.id,'name',e.name,'balance',coalesce(b.balance,0),
      'sweep_amount',greatest(coalesce(b.balance,0),0)
    ) order by e.name),'[]'::jsonb),
    'total',coalesce(sum(greatest(coalesce(b.balance,0),0)),0),
    'creates_bank_transfer',false
  ) into v_result
  from public.envelopes e
  left join public.envelope_ledger_balances b on b.envelope_id=e.id
  where e.household_id=p_household_id and e.archived_at is null
    and e.recommendation_definition->>'month_end_sweep_destination'='Epargne';
  return v_result;
end $$;

create or replace function public.execute_monthly_savings_sweep(
  p_household_id uuid,p_month_start date
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_role text; v_destination uuid; v_source record; v_amount numeric(14,2);
  v_key uuid; v_event uuid; v_batch uuid; v_position record; v_snapshot jsonb;
  v_items jsonb:='[]'::jsonb; v_replayed boolean:=true;
begin
  select role into v_role from public.household_members
    where household_id=p_household_id and user_id=auth.uid();
  if v_role is null then raise exception 'Household access denied'; end if;
  if p_month_start<>date_trunc('month',p_month_start)::date then raise exception 'Invalid month'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_household_id::text||p_month_start::text,0));
  select id into v_destination from public.envelopes
    where household_id=p_household_id and name='Epargne' and archived_at is null and not is_system;
  if v_destination is null then raise exception 'Epargne envelope is missing'; end if;
  if (select count(*) from public.envelopes where household_id=p_household_id and archived_at is null
      and recommendation_definition->>'month_end_sweep_destination'='Epargne')<>3 then
    raise exception 'Savings sweep configuration must contain exactly three sources';
  end if;

  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then
    raise exception 'Current account x envelope positions must be reliable before savings sweep';
  end if;

  for v_source in
    select e.id,e.name,coalesce(b.balance,0)::numeric(14,2) balance
    from public.envelopes e left join public.envelope_ledger_balances b on b.envelope_id=e.id
    where e.household_id=p_household_id and e.archived_at is null
      and e.recommendation_definition->>'month_end_sweep_destination'='Epargne'
    order by e.name
  loop
    v_key:=public.r2_7_deterministic_uuid(
      'monthly-savings-sweep|'||p_household_id||'|'||p_month_start||'|'||v_source.id);
    if exists(select 1 from public.monthly_savings_sweeps where household_id=p_household_id
      and month_start=p_month_start and source_envelope_id=v_source.id) then
      select amount,financial_event_id into v_amount,v_event from public.monthly_savings_sweeps
        where household_id=p_household_id and month_start=p_month_start and source_envelope_id=v_source.id;
      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'source',v_source.name,'amount',v_amount,'financial_event_id',v_event,'replayed',true));
      continue;
    end if;
    v_replayed:=false;
    v_amount:=greatest(v_source.balance,0);
    v_event:=null; v_batch:=null;
    if v_amount>0 then
      v_event:=public.create_envelope_transfer_event(
        p_household_id,(p_month_start+interval '1 month')::timestamptz,
        'Reliquat mensuel '||v_source.name||' vers Epargne',v_amount,
        v_source.id,v_destination,'Sweep R2.7 sans transfert bancaire',v_key);
      v_batch:=public.r2_7_deterministic_uuid('position-batch|'||v_key);
      insert into public.envelope_account_position_batches(
        id,household_id,batch_kind,month_start,idempotency_key,note,created_by
      ) values(v_batch,p_household_id,'monthly_savings_sweep',p_month_start,v_key,
        'Projection du sweep sur les mêmes comptes physiques',auth.uid());
      for v_position in
        select account_id,amount from public.envelope_account_current_positions
        where household_id=p_household_id and envelope_id=v_source.id and amount>0 order by account_id
      loop
        insert into public.envelope_account_position_entries(
          household_id,batch_id,financial_event_id,account_id,envelope_id,amount,created_by
        ) values
          (p_household_id,v_batch,v_event,v_position.account_id,v_source.id,-v_position.amount,auth.uid()),
          (p_household_id,v_batch,v_event,v_position.account_id,v_destination,v_position.amount,auth.uid());
      end loop;
    end if;
    insert into public.monthly_savings_sweeps(
      household_id,month_start,source_envelope_id,destination_envelope_id,amount,
      financial_event_id,position_batch_id,idempotency_key,created_by
    ) values(p_household_id,p_month_start,v_source.id,v_destination,v_amount,
      v_event,v_batch,v_key,auth.uid());
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'source',v_source.name,'amount',v_amount,'financial_event_id',v_event,'replayed',false));
  end loop;
  v_snapshot:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_snapshot->>'reliable')::boolean then raise exception 'Savings sweep position invariant failed'; end if;
  return jsonb_build_object('month_start',p_month_start,'items',v_items,'replayed',v_replayed,
    'creates_bank_transfer',false,'snapshot_fingerprint',v_snapshot->>'fingerprint');
end $$;

create or replace function public.close_monthly_period(
  p_household_id uuid,p_month_start date,p_override_warnings boolean,p_reason text,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_period public.monthly_close_periods%rowtype; v_snapshot jsonb; v_role text; v_sweep jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select * into v_period from public.monthly_close_periods where household_id=p_household_id and month_start=p_month_start for update;
  if v_period.status='closed' then return v_period.id; end if;
  select role into v_role from public.household_members where household_id=p_household_id and user_id=auth.uid();
  v_snapshot:=public.monthly_close_snapshot(p_household_id,p_month_start);
  if (v_snapshot->>'hard_blockers')::int>0 then raise exception 'Monthly close has hard blockers'; end if;
  if (v_snapshot->>'warnings')::int>0 and not p_override_warnings then raise exception 'Monthly close has warnings'; end if;
  if p_override_warnings and (v_role<>'owner' or nullif(trim(p_reason),'') is null) then raise exception 'Owner reason required for warning override'; end if;
  v_sweep:=public.execute_monthly_savings_sweep(p_household_id,p_month_start);
  v_snapshot:=v_snapshot||jsonb_build_object('savings_sweep',v_sweep);
  if v_period.id is null then
    insert into public.monthly_close_periods(household_id,month_start,status,created_by)
      values(p_household_id,p_month_start,'closed',auth.uid()) returning * into v_period;
  else update public.monthly_close_periods set status='closed' where id=v_period.id; end if;
  insert into public.monthly_close_events(household_id,period_id,event_kind,reason,snapshot,idempotency_key,created_by)
    values(p_household_id,v_period.id,case when p_override_warnings then 'warning_override' else 'closed' end,
      nullif(trim(p_reason),''),v_snapshot,p_idempotency_key,auth.uid())
    on conflict(household_id,idempotency_key) do nothing;
  return v_period.id;
end $$;

revoke all on function public.monthly_savings_sweep_preview(uuid,date),
  public.execute_monthly_savings_sweep(uuid,date) from public,anon;
grant execute on function public.monthly_savings_sweep_preview(uuid,date),
  public.execute_monthly_savings_sweep(uuid,date) to authenticated;

comment on column public.envelopes.recommendation_kind is
  'Structural funding rule: single account, scenario split, member beneficiary, system, or unconfigured.';
comment on column public.envelopes.recommendation_definition is
  'Non-financial, auditable rule metadata. Never represents a GL or envelope-ledger position.';

commit;

