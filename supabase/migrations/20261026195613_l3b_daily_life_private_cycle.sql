-- L3B: daily household life. Additive only; no financial ledger writes.
alter table public.household_tasks
  add column if not exists room text,
  add column if not exists estimated_minutes integer check (estimated_minutes is null or estimated_minutes between 1 and 1440),
  add column if not exists workload text check (workload is null or workload in ('light','normal','heavy'));

create table public.household_grocery_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  label text not null check (length(trim(label)) between 1 and 160),
  quantity numeric(12,3) not null default 1 check (quantity > 0),
  unit text,
  assignee_user_id uuid,
  status text not null default 'needed' check (status in ('needed','picked','cancelled')),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (household_id,assignee_user_id)
    references public.household_members(household_id,user_id)
);
create index household_grocery_items_active_idx
  on public.household_grocery_items(household_id,status,created_at);
alter table public.household_grocery_items enable row level security;
create policy household_grocery_items_read on public.household_grocery_items
  for select to authenticated using (public.is_household_member(household_id));
create policy household_grocery_items_create on public.household_grocery_items
  for insert to authenticated with check (
    public.is_household_member(household_id) and created_by=(select auth.uid())
  );
create policy household_grocery_items_update on public.household_grocery_items
  for update to authenticated using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
revoke all on public.household_grocery_items from public,anon;
grant select,insert,update on public.household_grocery_items to authenticated;

create table public.household_home_records (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  kind text not null check (kind in ('contract','warranty','maintenance')),
  label text not null check (length(trim(label)) between 1 and 160),
  provider text,
  reference text,
  responsible_user_id uuid,
  starts_on date,
  due_on date,
  renewal text not null default 'none' check (renewal in ('none','monthly','yearly')),
  notes text,
  archived_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (household_id,responsible_user_id)
    references public.household_members(household_id,user_id)
);
create index household_home_records_due_idx
  on public.household_home_records(household_id,due_on) where archived_at is null;
alter table public.household_home_records enable row level security;
create policy household_home_records_read on public.household_home_records
  for select to authenticated using (public.is_household_member(household_id));
create policy household_home_records_create on public.household_home_records
  for insert to authenticated with check (
    public.is_household_member(household_id) and created_by=(select auth.uid())
  );
create policy household_home_records_update on public.household_home_records
  for update to authenticated using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
revoke all on public.household_home_records from public,anon;
grant select,insert,update on public.household_home_records to authenticated;

-- Full cycle events remain owner-only. Shared calendar projection never contains
-- notes, symptoms or flow details.
create table public.member_cycle_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  owner_user_id uuid not null,
  starts_on date not null,
  ends_on date,
  phase text not null default 'period' check (phase in ('period','follicular','ovulation','luteal','other')),
  flow text check (flow is null or flow in ('light','medium','heavy')),
  symptoms text[] not null default '{}',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  foreign key (household_id,owner_user_id)
    references public.household_members(household_id,user_id)
);
create index member_cycle_events_owner_idx
  on public.member_cycle_events(household_id,owner_user_id,starts_on desc);
create table public.member_cycle_calendar_shares (
  household_id uuid not null references public.households(id) on delete cascade,
  owner_user_id uuid not null,
  recipient_user_id uuid not null,
  granted_at timestamptz not null default now(),
  primary key(household_id,owner_user_id,recipient_user_id),
  foreign key (household_id,owner_user_id) references public.household_members(household_id,user_id),
  foreign key (household_id,recipient_user_id) references public.household_members(household_id,user_id),
  check (owner_user_id<>recipient_user_id)
);
alter table public.member_cycle_events enable row level security;
alter table public.member_cycle_calendar_shares enable row level security;
create policy member_cycle_events_owner_read on public.member_cycle_events
  for select to authenticated using (owner_user_id=(select auth.uid()));
create policy member_cycle_events_owner_create on public.member_cycle_events
  for insert to authenticated with check (
    owner_user_id=(select auth.uid()) and public.is_household_member(household_id)
  );
create policy member_cycle_events_owner_update on public.member_cycle_events
  for update to authenticated using (owner_user_id=(select auth.uid()))
  with check (owner_user_id=(select auth.uid()));
create policy member_cycle_shares_participants_read on public.member_cycle_calendar_shares
  for select to authenticated using (
    owner_user_id=(select auth.uid()) or recipient_user_id=(select auth.uid())
  );
create policy member_cycle_shares_owner_manage on public.member_cycle_calendar_shares
  for all to authenticated using (owner_user_id=(select auth.uid()))
  with check (
    owner_user_id=(select auth.uid()) and public.is_household_member(household_id)
  );
revoke all on public.member_cycle_events,public.member_cycle_calendar_shares from public,anon;
grant select,insert,update on public.member_cycle_events to authenticated;
grant select,insert,delete on public.member_cycle_calendar_shares to authenticated;

create function public.read_shared_cycle_calendar(p_household_id uuid)
returns table(event_id uuid,owner_user_id uuid,starts_on date,ends_on date,phase text)
language sql security definer set search_path=''
stable
as $$
  select e.id,e.owner_user_id,e.starts_on,e.ends_on,e.phase
  from public.member_cycle_events e
  where e.household_id=p_household_id and e.archived_at is null
    and exists(select 1 from public.household_members me
      where me.household_id=p_household_id and me.user_id=auth.uid() and me.inactive_at is null)
    and (e.owner_user_id=auth.uid() or exists(select 1
      from public.member_cycle_calendar_shares s
      where s.household_id=e.household_id and s.owner_user_id=e.owner_user_id
        and s.recipient_user_id=auth.uid()));
$$;
revoke all on function public.read_shared_cycle_calendar(uuid) from public,anon;
grant execute on function public.read_shared_cycle_calendar(uuid) to authenticated;

-- Daily entry reminder state uses the existing personal alert state. It never
-- writes FinancialEvent/GL/envelope ledgers.
create function public.act_on_daily_entry_reminder(
  p_household_id uuid,p_alert_key text,p_action text,p_snoozed_until timestamptz default null
) returns void language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not exists(select 1 from public.household_members m
    where m.household_id=p_household_id and m.user_id=auth.uid() and m.inactive_at is null)
    or p_alert_key !~ '^daily-entry:[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or p_action not in ('done','not_yet') then raise exception 'Daily reminder action denied'; end if;
  if p_action='not_yet' and (p_snoozed_until is null or p_snoozed_until <= now()) then
    raise exception 'A future snooze date is required';
  end if;
  insert into public.user_alert_states(household_id,user_id,alert_key,read_at,dismissed_at,snoozed_until,last_action,updated_at)
  values(p_household_id,auth.uid(),p_alert_key,
    case when p_action='done' then now() end,
    case when p_action='done' then now() end,
    case when p_action='not_yet' then p_snoozed_until end,p_action,now())
  on conflict(household_id,user_id,alert_key) do update set
    read_at=excluded.read_at,dismissed_at=excluded.dismissed_at,
    snoozed_until=excluded.snoozed_until,last_action=excluded.last_action,updated_at=now();
end $$;
revoke all on function public.act_on_daily_entry_reminder(uuid,text,text,timestamptz) from public,anon;
grant execute on function public.act_on_daily_entry_reminder(uuid,text,text,timestamptz) to authenticated;

-- Categories remain the canonical finance reference; expose only the existing
-- household-scoped table, not a second reference engine.
grant select,insert,update on public.categories to authenticated;

alter table public.notification_preferences drop constraint if exists notification_preferences_category_check;
alter table public.notification_preferences add constraint notification_preferences_category_check
  check (category in ('tasks','budget','finance','goals','home_auto','compensations','reminders','groceries','home','cycle'));

create trigger l3b_safe_realtime_household_grocery_items
after insert or update or delete on public.household_grocery_items
for each row execute function private.emit_household_realtime_invalidation();
create trigger l3b_safe_realtime_household_home_records
after insert or update or delete on public.household_home_records
for each row execute function private.emit_household_realtime_invalidation();

