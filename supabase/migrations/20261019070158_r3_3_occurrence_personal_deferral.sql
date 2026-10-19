begin;

-- Personal deferral belongs to the source, while read/dismiss remain phase-local.
create or replace function private.defer_reminder_source()
returns trigger language plpgsql security definer set search_path=public,private as $$
declare v_source_id uuid;
begin
  if new.last_action not in ('snoozed','not_yet') or new.snoozed_until is null then
    return new;
  end if;
  select source_id into v_source_id from public.financial_reminders
  where household_id=new.household_id and dedupe_key=new.alert_key
    and source_kind='r3_1_occurrence'
    and (recipient_user_id is null or recipient_user_id=new.user_id);
  if v_source_id is null then return new; end if;
  insert into public.user_alert_states(household_id,user_id,alert_key,snoozed_until,last_action,updated_at)
  values(new.household_id,new.user_id,'reminder-source:r3_1_occurrence:'||v_source_id,
    new.snoozed_until,new.last_action,new.updated_at)
  on conflict(household_id,user_id,alert_key) do update set
    snoozed_until=excluded.snoozed_until,last_action=excluded.last_action,updated_at=excluded.updated_at;
  return new;
end $$;
revoke all on function private.defer_reminder_source() from public,anon,authenticated;
create trigger user_alert_states_source_deferral after insert or update on public.user_alert_states
for each row execute function private.defer_reminder_source();

-- Preserve existing audited deferrals, including when their old phase is cancelled.
insert into public.user_alert_states(household_id,user_id,alert_key,snoozed_until,last_action,updated_at)
select distinct on (a.household_id,a.user_id,r.source_id)
  a.household_id,a.user_id,'reminder-source:r3_1_occurrence:'||r.source_id,
  a.snoozed_until,a.action,a.acted_at
from public.reminder_action_audit a
join public.financial_reminders r on r.household_id=a.household_id and r.dedupe_key=a.alert_key
where r.source_kind='r3_1_occurrence' and a.action in ('snoozed','not_yet')
order by a.household_id,a.user_id,r.source_id,a.acted_at desc,a.id desc
on conflict(household_id,user_id,alert_key) do nothing;

-- Arrival order/retries must never reactivate an obsolete phase.
create or replace function private.keep_latest_reminder_phase()
returns trigger language plpgsql security definer set search_path=public,private as $$
begin
  if new.source_kind='r3_1_occurrence' then
    update public.financial_reminders r set status='cancelled',resolved_at=coalesce(r.resolved_at,now())
    where r.household_id=new.household_id and r.source_kind=new.source_kind and r.source_id=new.source_id
      and r.status='active' and exists (
        select 1 from public.financial_reminders newer
        where newer.household_id=r.household_id and newer.source_kind=r.source_kind
          and newer.source_id=r.source_id and newer.due_at>r.due_at
      );
  end if;
  return new;
end $$;

-- Server read boundary: RLS + personal source snooze + current business source.
create function public.visible_financial_reminders(p_household_id uuid)
returns setof public.financial_reminders
language sql stable security invoker set search_path=public as $$
  select r.* from public.financial_reminders r
  where r.household_id=p_household_id and public.is_household_member(r.household_id)
    and r.status='active' and r.due_at<=now()
    and (r.recipient_user_id is null or r.recipient_user_id=auth.uid())
    and not exists (
      select 1 from public.user_alert_states s
      where s.household_id=r.household_id and s.user_id=auth.uid()
        and ((s.alert_key=r.dedupe_key and (s.dismissed_at is not null
          or (r.source_kind<>'r3_1_occurrence' and s.snoozed_until>now())))
          or (r.source_kind='r3_1_occurrence'
            and s.alert_key='reminder-source:r3_1_occurrence:'||r.source_id
            and s.snoozed_until>now()))
    )
    and (r.source_kind<>'r3_1_occurrence' or (
      exists (select 1 from public.expected_financial_occurrence_overview o
        join public.recurring_financial_intentions i on i.id=o.intention_id
        where o.id=r.source_id and o.household_id=r.household_id
          and o.occurrence_status in ('expected','overdue','partially_realized') and i.status='active')
      and not exists (select 1 from public.financial_reminders newer
        where newer.household_id=r.household_id and newer.source_kind=r.source_kind
          and newer.source_id=r.source_id and newer.due_at>r.due_at and newer.due_at<=now())
    ))
  order by r.due_at;
$$;
revoke all on function public.visible_financial_reminders(uuid) from public,anon;
grant execute on function public.visible_financial_reminders(uuid) to authenticated;
commit;
