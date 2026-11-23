-- F2: forecast consent is independent from the existing dates/phases share.
-- Forecasts are derived from owner observations and exposed only through the
-- minimized projection below. No symptom, note, flow or private journal value
-- is returned by this contract.
create table public.member_cycle_forecast_shares (
  household_id uuid not null references public.households(id) on delete cascade,
  owner_user_id uuid not null,
  recipient_user_id uuid not null,
  granted_at timestamptz not null default now(),
  primary key (household_id, owner_user_id, recipient_user_id),
  foreign key (household_id, owner_user_id)
    references public.household_members(household_id, user_id),
  foreign key (household_id, recipient_user_id)
    references public.household_members(household_id, user_id),
  check (owner_user_id <> recipient_user_id)
);

alter table public.member_cycle_forecast_shares enable row level security;

create policy member_cycle_forecast_shares_participants_read
  on public.member_cycle_forecast_shares for select to authenticated
  using (
    owner_user_id = (select auth.uid())
    or recipient_user_id = (select auth.uid())
  );

create policy member_cycle_forecast_shares_owner_create
  on public.member_cycle_forecast_shares for insert to authenticated
  with check (
    owner_user_id = (select auth.uid())
    and public.is_household_member(household_id)
    and exists (
      select 1 from public.household_members recipient
      where recipient.household_id = member_cycle_forecast_shares.household_id
        and recipient.user_id = member_cycle_forecast_shares.recipient_user_id
        and recipient.inactive_at is null
    )
  );

create policy member_cycle_forecast_shares_owner_delete
  on public.member_cycle_forecast_shares for delete to authenticated
  using (owner_user_id = (select auth.uid()));

revoke all on public.member_cycle_forecast_shares from public, anon;
grant select, insert, delete on public.member_cycle_forecast_shares
  to authenticated;

comment on table public.member_cycle_forecast_shares is
  'F2 explicit per-recipient consent for derived Cycle forecasts. Independent from dates/phases sharing.';

-- One canonical, minimized projection feeds Cycle, Dashboard and household
-- calendar. The caller gets their own observations/forecasts, observations
-- explicitly shared through the historical dates/phases consent, and forecasts
-- explicitly shared through the distinct F2 consent.
create function public.read_authorized_cycle_timeline(p_household_id uuid)
returns table(
  event_key text,
  owner_user_id uuid,
  starts_on date,
  ends_on date,
  phase text,
  projection_kind text,
  confidence text
)
language sql
security definer
set search_path = ''
stable
as $$
  with caller as (
    select (select auth.uid()) as user_id
    where exists (
      select 1 from public.household_members member
      where member.household_id = p_household_id
        and member.user_id = (select auth.uid())
        and member.inactive_at is null
    )
  ),
  authorized_observation_owners as (
    select caller.user_id as owner_user_id from caller
    union
    select share.owner_user_id
    from public.member_cycle_calendar_shares share, caller
    where share.household_id = p_household_id
      and share.recipient_user_id = caller.user_id
  ),
  authorized_forecast_owners as (
    select caller.user_id as owner_user_id from caller
    union
    select share.owner_user_id
    from public.member_cycle_forecast_shares share, caller
    where share.household_id = p_household_id
      and share.recipient_user_id = caller.user_id
  ),
  period_starts as (
    select event.owner_user_id, event.starts_on
    from public.member_cycle_events event
    join authorized_forecast_owners allowed
      on allowed.owner_user_id = event.owner_user_id
    where event.household_id = p_household_id
      and event.archived_at is null
      and event.phase = 'period'
  ),
  intervals as (
    select owner_user_id, starts_on,
      starts_on - lag(starts_on) over (
        partition by owner_user_id order by starts_on
      ) as interval_days
    from period_starts
  ),
  forecast_stats as (
    select owner_user_id,
      count(interval_days) filter (where interval_days between 15 and 90) as sample_size,
      round(avg(interval_days) filter (where interval_days between 15 and 90))::integer as average_days,
      ceil(coalesce(stddev_pop(interval_days) filter (
        where interval_days between 15 and 90
      ), 0))::integer as variability_days,
      max(starts_on) as latest_start
    from intervals
    group by owner_user_id
  ),
  forecasts as (
    select owner_user_id, sample_size, average_days, variability_days,
      latest_start + average_days as next_center,
      greatest(
        case when sample_size < 2 then 7 else 2 end,
        variability_days
      ) as uncertainty_days,
      case
        when sample_size >= 5 and variability_days <= 3 then 'high'
        when sample_size >= 3 and variability_days <= 7 then 'medium'
        when sample_size >= 2 then 'low'
        else 'insufficient'
      end as forecast_confidence
    from forecast_stats
    where sample_size >= 1 and average_days is not null
  )
  select event.id::text, event.owner_user_id, event.starts_on, event.ends_on,
    event.phase, 'observation'::text, null::text
  from public.member_cycle_events event
  join authorized_observation_owners allowed
    on allowed.owner_user_id = event.owner_user_id
  where event.household_id = p_household_id
    and event.archived_at is null
  union all
  select 'forecast:' || owner_user_id::text || ':period', owner_user_id,
    next_center - uncertainty_days,
    next_center + uncertainty_days,
    'period', 'forecast', forecast_confidence
  from forecasts
  union all
  select 'forecast:' || owner_user_id::text || ':ovulation', owner_user_id,
    next_center - 14 - (uncertainty_days + 1),
    next_center - 14 + (uncertainty_days + 1),
    'ovulation', 'forecast', forecast_confidence
  from forecasts;
$$;

revoke all on function public.read_authorized_cycle_timeline(uuid)
  from public, anon;
grant execute on function public.read_authorized_cycle_timeline(uuid)
  to authenticated;

comment on function public.read_authorized_cycle_timeline(uuid) is
  'Minimized F2 Cycle projection. Observations and forecasts obey independent per-recipient consents.';

create trigger f2_safe_realtime_member_cycle_forecast_shares
after insert or update or delete on public.member_cycle_forecast_shares
for each row execute function private.emit_household_realtime_invalidation();
