-- Realtime transports invalidation signals only. Financial/private row payloads
-- are never subscribed by the client, including DELETE events.
create table public.household_realtime_invalidations (
  household_id uuid not null references public.households(id) on delete cascade,
  topic text not null,
  revision bigint generated always as identity,
  changed_at timestamptz not null default now(),
  primary key (household_id, topic)
);

alter table public.household_realtime_invalidations enable row level security;
revoke all on table public.household_realtime_invalidations
  from public, anon, authenticated;
grant select on table public.household_realtime_invalidations to authenticated;

create policy household_realtime_invalidations_read
on public.household_realtime_invalidations
for select to authenticated
using (public.is_household_member(household_id));

create or replace function private.emit_household_realtime_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_household_id uuid;
begin
  v_household_id := case when tg_op = 'DELETE' then old.household_id
                         else new.household_id end;
  insert into public.household_realtime_invalidations (
    household_id, topic, changed_at
  ) values (v_household_id, tg_table_name, now())
  on conflict (household_id, topic) do update
    set changed_at = excluded.changed_at,
        revision = public.household_realtime_invalidations.revision + 1;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.emit_household_realtime_invalidation()
  from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'accounts', 'envelopes', 'financial_events', 'obligations',
    'member_compensations', 'budget_goals', 'shopping_items',
    'priority_plans', 'household_tasks', 'wealth_assets',
    'envelope_account_initial_position_drafts',
    'envelope_account_initial_position_unknowns',
    'recurring_financial_intentions', 'expected_financial_occurrences',
    'expected_financial_occurrence_matches', 'financial_reminders',
    'reminder_rules', 'user_alert_states', 'notification_preferences'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function private.emit_household_realtime_invalidation()',
      'l1_safe_realtime_' || v_table,
      v_table
    );
  end loop;
end;
$$;

alter publication supabase_realtime
  add table public.household_realtime_invalidations;
