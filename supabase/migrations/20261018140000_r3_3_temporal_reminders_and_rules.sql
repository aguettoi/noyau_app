begin;

alter table public.user_alert_states
  add column if not exists snoozed_until timestamptz,
  add column if not exists last_action text
    check (last_action is null or last_action in ('read','dismissed','snoozed','not_yet'));

alter table public.notification_preferences
  drop constraint if exists notification_preferences_category_check;
alter table public.notification_preferences
  add constraint notification_preferences_category_check
  check (category in ('tasks','budget','finance','compensations','goals','home_auto','reminders'));

create table public.reminder_rules (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  recipient_user_id uuid,
  rule_type text not null check (rule_type in ('expected_occurrence','monthly_close','cashflow_risk','envelope_threshold','important_due_date')),
  enabled boolean not null default true,
  parameters jsonb not null default '{}'::jsonb,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  channel text not null default 'in_app' check (channel in ('in_app')),
  source_kind text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (household_id,recipient_user_id,rule_type),
  foreign key (household_id,recipient_user_id)
    references public.household_members(household_id,user_id)
);

create table public.financial_reminders (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  recipient_user_id uuid,
  source_kind text not null,
  source_id uuid not null,
  dedupe_key text not null,
  due_at timestamptz not null,
  timezone text not null,
  priority text not null check (priority in ('low','normal','high','urgent')),
  status text not null default 'active' check (status in ('active','resolved','cancelled')),
  title text not null,
  detail text not null,
  action_type text not null check (action_type in ('open_occurrence','open_monthly_close','open_projection')),
  certainty text check (certainty is null or certainty in ('certain','estimated','hypothetical')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (household_id,dedupe_key),
  foreign key (household_id,recipient_user_id)
    references public.household_members(household_id,user_id)
);

create table public.reminder_action_audit (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  alert_key text not null,
  action text not null check (action in ('read','dismissed','snoozed','not_yet')),
  snoozed_until timestamptz,
  acted_at timestamptz not null default now(),
  idempotency_key uuid not null,
  unique (user_id,idempotency_key),
  foreign key (household_id,user_id)
    references public.household_members(household_id,user_id)
);

create index financial_reminders_due_active_idx
  on public.financial_reminders(due_at,household_id)
  where status='active';
create index financial_reminders_recipient_idx
  on public.financial_reminders(recipient_user_id,due_at)
  where status='active';

alter table public.reminder_rules enable row level security;
alter table public.financial_reminders enable row level security;
alter table public.reminder_action_audit enable row level security;

create policy reminder_rules_read on public.reminder_rules for select to authenticated
  using (public.is_household_member(household_id));
create policy reminder_rules_write on public.reminder_rules for all to authenticated
  using (
    public.is_household_member(household_id)
    and (
      recipient_user_id=(select auth.uid())
      or exists(select 1 from public.household_members hm where hm.household_id=reminder_rules.household_id and hm.user_id=(select auth.uid()) and hm.role='owner' and hm.inactive_at is null)
    )
  )
  with check (
    public.is_household_member(household_id)
    and created_by=(select auth.uid())
    and (
      recipient_user_id=(select auth.uid())
      or exists(select 1 from public.household_members hm where hm.household_id=reminder_rules.household_id and hm.user_id=(select auth.uid()) and hm.role='owner' and hm.inactive_at is null)
    )
  );
create policy financial_reminders_read on public.financial_reminders for select to authenticated
  using (public.is_household_member(household_id) and (recipient_user_id is null or recipient_user_id=(select auth.uid())));
create policy reminder_action_audit_read on public.reminder_action_audit for select to authenticated
  using (user_id=(select auth.uid()) and public.is_household_member(household_id));

revoke all on public.reminder_rules,public.financial_reminders,public.reminder_action_audit from public,anon;
grant select,insert,update on public.reminder_rules to authenticated;
grant select on public.financial_reminders,public.reminder_action_audit to authenticated;

create or replace function public.act_on_financial_reminder(
  p_household_id uuid,
  p_alert_key text,
  p_action text,
  p_snoozed_until timestamptz,
  p_idempotency_key uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_existing public.reminder_action_audit;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Reminder access denied';
  end if;
  if p_action not in ('read','dismissed','snoozed','not_yet') then raise exception 'Invalid reminder action'; end if;
  if p_action in ('snoozed','not_yet') and (p_snoozed_until is null or p_snoozed_until<=now()) then
    raise exception 'A future snooze date is required';
  end if;
  if exists(select 1 from public.financial_reminders r where r.household_id=p_household_id and r.dedupe_key=p_alert_key and r.recipient_user_id is not null and r.recipient_user_id<>auth.uid()) then
    raise exception 'Reminder recipient mismatch';
  end if;
  insert into public.reminder_action_audit(household_id,user_id,alert_key,action,snoozed_until,idempotency_key)
  values(p_household_id,auth.uid(),p_alert_key,p_action,p_snoozed_until,p_idempotency_key)
  on conflict(user_id,idempotency_key) do nothing
  returning * into v_existing;
  if v_existing.id is null then return; end if;
  insert into public.user_alert_states(household_id,user_id,alert_key,read_at,dismissed_at,snoozed_until,last_action,updated_at)
  values(
    p_household_id,auth.uid(),p_alert_key,
    case when p_action='read' then now() end,
    case when p_action='dismissed' then now() end,
    case when p_action in ('snoozed','not_yet') then p_snoozed_until end,
    p_action,now()
  ) on conflict(household_id,user_id,alert_key) do update set
    read_at=case when excluded.last_action='read' then now() else user_alert_states.read_at end,
    dismissed_at=case when excluded.last_action='dismissed' then now() else null end,
    snoozed_until=excluded.snoozed_until,
    last_action=excluded.last_action,
    updated_at=now();
end $$;

revoke all on function public.act_on_financial_reminder(uuid,text,text,timestamptz,uuid) from public,anon;
grant execute on function public.act_on_financial_reminder(uuid,text,text,timestamptz,uuid) to authenticated;

create schema if not exists private;

create or replace function private.materialize_financial_reminders(p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path=public,private as $$
declare v_count integer:=0; v_added integer:=0;
begin
  update public.financial_reminders r set status='resolved',resolved_at=p_now
  from public.expected_financial_occurrence_overview o
  where r.source_kind='r3_1_occurrence' and r.source_id=o.id and r.status='active'
    and o.occurrence_status in ('realized','ignored');

  insert into public.financial_reminders(
    household_id,recipient_user_id,source_kind,source_id,dedupe_key,due_at,timezone,priority,title,detail,action_type,certainty
  )
  select o.household_id,o.concerned_member_id,'r3_1_occurrence',o.id,
    'r3.1:'||o.id::text||':'||phase.name,
    (((o.expected_on+phase.day_offset) + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone h.timezone),
    h.timezone,coalesce(rr.priority,'normal'),
    case phase.name when 'before' then o.label||' approche'
      when 'after' then o.label||' n''est pas encore rapproché'
      else o.label||' est attendu aujourd''hui' end,
    trim(to_char(o.expected_amount-o.confirmed_amount,'FM999999999990D00'))||' MAD restant à rapprocher.',
    'open_occurrence',i.certainty
  from public.expected_financial_occurrence_overview o
  join public.recurring_financial_intentions i on i.id=o.intention_id
  join public.households h on h.id=o.household_id
  left join lateral (
    select x.parameters,x.priority,x.enabled from public.reminder_rules x
    where x.household_id=o.household_id and x.rule_type='expected_occurrence'
      and (x.recipient_user_id=o.concerned_member_id or x.recipient_user_id is null)
    order by (x.recipient_user_id is not null) desc limit 1
  ) rr on true
  cross join lateral (values
    ('before',-coalesce((rr.parameters->>'before_days')::int,1)),
    ('day',0),
    ('after',coalesce((rr.parameters->>'after_days')::int,1))
  ) phase(name,day_offset)
  where o.occurrence_status in ('expected','partially_realized','overdue') and i.status='active'
    and coalesce(rr.enabled,true)
    and (((o.expected_on+phase.day_offset) + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone h.timezone)<=p_now
  on conflict(household_id,dedupe_key) do nothing;
  get diagnostics v_count=row_count;

  insert into public.financial_reminders(
    household_id,recipient_user_id,source_kind,source_id,dedupe_key,due_at,timezone,priority,title,detail,action_type
  )
  select p.household_id,null,'monthly_close',p.id,'monthly-close:'||p.id::text,
    (((p.ends_on-coalesce((rr.parameters->>'before_days')::int,3)) + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone h.timezone),
    h.timezone,coalesce(rr.priority,'high'),
    'La fin du mois approche','Vérifiez les éléments nécessaires sans imposer un inventaire global.','open_monthly_close'
  from public.budget_periods p join public.households h on h.id=p.household_id
  left join lateral (
    select x.parameters,x.priority,x.enabled from public.reminder_rules x
    where x.household_id=p.household_id and x.rule_type='monthly_close' and x.recipient_user_id is null
    limit 1
  ) rr on true
  where p.status='active' and coalesce(rr.enabled,true)
    and (((p.ends_on-coalesce((rr.parameters->>'before_days')::int,3)) + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone h.timezone)<=p_now
  on conflict(household_id,dedupe_key) do nothing;
  get diagnostics v_added=row_count;
  v_count:=v_count+v_added;
  return v_count;
end $$;

revoke all on function private.materialize_financial_reminders(timestamptz) from public,anon,authenticated;
grant execute on function private.materialize_financial_reminders(timestamptz) to service_role;

do $$
begin
  if exists(select 1 from pg_available_extensions where name='pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    if not exists(select 1 from cron.job where jobname='r3_3_materialize_financial_reminders') then
      perform cron.schedule('r3_3_materialize_financial_reminders','*/15 * * * *','select private.materialize_financial_reminders(now());');
    end if;
  end if;
end $$;

do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='financial_reminders') then
    alter publication supabase_realtime add table public.financial_reminders;
  end if;
end $$;

commit;
