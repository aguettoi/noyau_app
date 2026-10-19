begin;
-- Order simultaneous phases by business progression, independently of arrival order.
create or replace function private.keep_latest_reminder_phase()
returns trigger language plpgsql security definer set search_path=public,private as $$
begin
  if new.source_kind='r3_1_occurrence' then
    update public.financial_reminders r set status='cancelled',resolved_at=coalesce(r.resolved_at,now())
    where r.household_id=new.household_id and r.source_kind=new.source_kind and r.source_id=new.source_id
      and r.status='active' and exists (
        select 1 from public.financial_reminders newer
        where newer.household_id=r.household_id and newer.source_kind=r.source_kind
          and newer.source_id=r.source_id and (newer.due_at,case split_part(newer.dedupe_key,':',3) when 'after' then 2 when 'day' then 1 else 0 end)
          >(r.due_at,case split_part(r.dedupe_key,':',3) when 'after' then 2 when 'day' then 1 else 0 end)
      );
  end if;
  return new;
end $$;

-- Server read boundary: RLS + personal source snooze + current business source.
create or replace function public.visible_financial_reminders(p_household_id uuid)
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
          and newer.source_id=r.source_id and (newer.due_at,case split_part(newer.dedupe_key,':',3) when 'after' then 2 when 'day' then 1 else 0 end)
          >(r.due_at,case split_part(r.dedupe_key,':',3) when 'after' then 2 when 'day' then 1 else 0 end) and newer.due_at<=now())
    ))
  order by r.due_at;
$$;
commit;

