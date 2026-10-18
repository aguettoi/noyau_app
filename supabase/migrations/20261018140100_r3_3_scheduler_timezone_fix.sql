begin;

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
    (((o.expected_on+phase.day_offset) + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone tz.timezone),
    tz.timezone,coalesce(rr.priority,'normal'),
    case phase.name when 'before' then o.label||' approche'
      when 'after' then o.label||' n''est pas encore rapproché'
      else o.label||' est attendu aujourd''hui' end,
    trim(to_char(o.expected_amount-o.confirmed_amount,'FM999999999990D00'))||' MAD restant à rapprocher.',
    'open_occurrence',i.certainty
  from public.expected_financial_occurrence_overview o
  join public.recurring_financial_intentions i on i.id=o.intention_id
  cross join lateral (
    select coalesce((select p.timezone from public.household_members hm join public.profiles p on p.id=hm.user_id
      where hm.household_id=o.household_id and hm.inactive_at is null order by (hm.role='owner') desc,hm.created_at limit 1),'Africa/Casablanca') timezone
  ) tz
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
    and (((o.expected_on+phase.day_offset) + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone tz.timezone)<=p_now
  on conflict(household_id,dedupe_key) do nothing;
  get diagnostics v_count=row_count;

  insert into public.financial_reminders(
    household_id,recipient_user_id,source_kind,source_id,dedupe_key,due_at,timezone,priority,title,detail,action_type
  )
  select p.household_id,null,'monthly_close',p.id,'monthly-close:'||p.id::text,
    (((p.ends_on-coalesce((rr.parameters->>'before_days')::int,3)) + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone tz.timezone),
    tz.timezone,coalesce(rr.priority,'high'),
    'La fin du mois approche','Vérifiez les éléments nécessaires sans imposer un inventaire global.','open_monthly_close'
  from public.budget_periods p
  cross join lateral (
    select coalesce((select pr.timezone from public.household_members hm join public.profiles pr on pr.id=hm.user_id
      where hm.household_id=p.household_id and hm.inactive_at is null order by (hm.role='owner') desc,hm.created_at limit 1),'Africa/Casablanca') timezone
  ) tz
  left join lateral (
    select x.parameters,x.priority,x.enabled from public.reminder_rules x
    where x.household_id=p.household_id and x.rule_type='monthly_close' and x.recipient_user_id is null
    limit 1
  ) rr on true
  where p.status='active' and coalesce(rr.enabled,true)
    and (((p.ends_on-coalesce((rr.parameters->>'before_days')::int,3)) + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone tz.timezone)<=p_now
  on conflict(household_id,dedupe_key) do nothing;
  get diagnostics v_added=row_count;
  return v_count+v_added;
end $$;

revoke all on function private.materialize_financial_reminders(timestamptz) from public,anon,authenticated;
grant execute on function private.materialize_financial_reminders(timestamptz) to service_role;

commit;
