begin;
-- Read-only phase validity bounds use the canonical source date, rule and timezone.
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
        left join lateral (
          select rule.parameters from public.reminder_rules rule
          where rule.household_id=o.household_id and rule.rule_type='expected_occurrence'
            and (rule.recipient_user_id=o.concerned_member_id or rule.recipient_user_id is null)
          order by (rule.recipient_user_id is not null) desc limit 1
        ) rr on true
        where o.id=r.source_id and o.household_id=r.household_id
          and o.occurrence_status in ('expected','overdue','partially_realized') and i.status='active'
          -- The next phase may be due before the next cron tick. Never show
          -- an obsolete phase while waiting for canonical materialization.
          and case split_part(r.dedupe_key,':',3)
            when 'before' then now() < ((o.expected_on + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone r.timezone)
            when 'day' then now() < (((o.expected_on+coalesce((rr.parameters->>'after_days')::int,1))
              + make_time(coalesce((rr.parameters->>'hour')::int,20),0,0)) at time zone r.timezone)
            when 'after' then true else false end)
      and not exists (select 1 from public.financial_reminders newer
        where newer.household_id=r.household_id and newer.source_kind=r.source_kind
          and newer.source_id=r.source_id and (newer.due_at,case split_part(newer.dedupe_key,':',3) when 'after' then 2 when 'day' then 1 else 0 end)
          >(r.due_at,case split_part(r.dedupe_key,':',3) when 'after' then 2 when 'day' then 1 else 0 end) and newer.due_at<=now())
    ))
  order by r.due_at;
$$;
commit;



