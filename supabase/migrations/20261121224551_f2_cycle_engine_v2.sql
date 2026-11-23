-- F2 Cycle engine v2: explicit abstention, explainable forecast metadata and
-- optional owner-only LH/BBT observations. No intimate measurement is exposed
-- by the shared projection.

alter table public.member_cycle_private_entries
  drop constraint if exists member_cycle_private_entries_category_check;

alter table public.member_cycle_private_entries
  add column if not exists observed_at timestamptz,
  add column if not exists measurement_value numeric,
  add column if not exists measurement_unit text,
  add column if not exists test_result text,
  add constraint member_cycle_private_entries_category_check check (category in (
    'symptom','mood','sleep','energy','stress','libido','skin','appetite',
    'digestion','discharge','temperature','basal_temperature','lh_test','weight',
    'spotting','contraception','intimacy'
  )),
  add constraint member_cycle_private_entries_structured_measurement_check check (
    (category = 'lh_test' and test_result in ('negative','positive')
      and measurement_value is null and measurement_unit is null)
    or (category = 'basal_temperature' and test_result is null
      and measurement_unit in ('celsius','fahrenheit')
      and ((measurement_unit = 'celsius' and measurement_value between 30 and 45)
        or (measurement_unit = 'fahrenheit' and measurement_value between 86 and 113)))
    or (category not in ('lh_test','basal_temperature')
      and test_result is null)
  );

comment on column public.member_cycle_private_entries.observed_at is
  'Optional owner-only observation timestamp for LH/BBT. Never projected or shared.';
comment on column public.member_cycle_private_entries.measurement_value is
  'Owner-only structured measurement. Never projected, exported or shared.';
comment on column public.member_cycle_private_entries.test_result is
  'Owner-only LH result. It is not proof of ovulation.';

create function public.read_authorized_cycle_timeline_v2(p_household_id uuid)
returns table(
  event_key text,
  owner_user_id uuid,
  starts_on date,
  ends_on date,
  phase text,
  projection_kind text,
  confidence text,
  engine_version text,
  sample_size integer,
  variability_days integer,
  uncertainty_days integer,
  regularity text
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
  all_intervals as (
    select owner_user_id, starts_on,
      starts_on - lag(starts_on) over (
        partition by owner_user_id order by starts_on
      ) as interval_days
    from period_starts
  ),
  ranked_intervals as (
    select owner_user_id, starts_on, interval_days,
      row_number() over (partition by owner_user_id order by starts_on desc) as recent_rank
    from all_intervals
    where interval_days is not null
  ),
  interval_quality as (
    select owner_user_id,
      count(*)::integer as total_intervals,
      count(*) filter (where interval_days between 15 and 90)::integer as valid_intervals,
      count(*) filter (where interval_days not between 15 and 90)::integer as invalid_intervals,
      max(starts_on) as latest_start
    from ranked_intervals
    group by owner_user_id
  ),
  recent_valid as (
    select owner_user_id, interval_days
    from ranked_intervals
    where interval_days between 15 and 90 and recent_rank <= 8
  ),
  forecast_stats as (
    select quality.owner_user_id,
      count(recent.interval_days)::integer as sample_size,
      round(avg(recent.interval_days))::integer as average_days,
      ceil(coalesce(stddev_pop(recent.interval_days), 0))::integer as variability_days,
      (max(recent.interval_days) - min(recent.interval_days))::integer as interval_range,
      quality.total_intervals,
      quality.invalid_intervals,
      quality.latest_start
    from interval_quality quality
    left join recent_valid recent on recent.owner_user_id = quality.owner_user_id
    group by quality.owner_user_id, quality.total_intervals,
      quality.invalid_intervals, quality.latest_start
  ),
  forecasts as (
    select owner_user_id, sample_size, average_days, variability_days,
      latest_start + average_days as next_center,
      greatest(2, variability_days + case when sample_size < 3 then 2 else 0 end)
        as uncertainty_days,
      case
        when sample_size >= 5 and variability_days <= 3 then 'high'
        when sample_size >= 3 and variability_days <= 7 then 'medium'
        else 'low'
      end as forecast_confidence,
      case
        when variability_days <= 3 then 'regular'
        when variability_days <= 7 then 'variable'
        else 'irregular'
      end as forecast_regularity
    from forecast_stats
    where sample_size >= 2
      and average_days is not null
      and variability_days <= 14
      and interval_range <= 30
      and invalid_intervals <= greatest(1, total_intervals / 3)
  )
  select event.id::text, event.owner_user_id, event.starts_on, event.ends_on,
    event.phase, 'observation'::text, null::text, null::text,
    null::integer, null::integer, null::integer, null::text
  from public.member_cycle_events event
  join authorized_observation_owners allowed
    on allowed.owner_user_id = event.owner_user_id
  where event.household_id = p_household_id
    and event.archived_at is null
  union all
  select 'forecast:' || owner_user_id::text || ':period', owner_user_id,
    next_center - uncertainty_days, next_center + uncertainty_days,
    'period', 'forecast', forecast_confidence, 'cycle-sql-v2.0.0',
    sample_size, variability_days, uncertainty_days, forecast_regularity
  from forecasts
  union all
  select 'forecast:' || owner_user_id::text || ':ovulation', owner_user_id,
    next_center - 14 - (uncertainty_days + 1),
    next_center - 14 + (uncertainty_days + 1),
    'ovulation', 'forecast', forecast_confidence, 'cycle-sql-v2.0.0',
    sample_size, variability_days, uncertainty_days, forecast_regularity
  from forecasts
  union all
  select 'forecast:' || owner_user_id::text || ':fertile_window', owner_user_id,
    next_center - 14 - (uncertainty_days + 5),
    next_center - 14 + (uncertainty_days + 1),
    'fertile_window', 'forecast', forecast_confidence, 'cycle-sql-v2.0.0',
    sample_size, variability_days, uncertainty_days, forecast_regularity
  from forecasts;
$$;

revoke all on function public.read_authorized_cycle_timeline(uuid)
  from authenticated;
revoke all on function public.read_authorized_cycle_timeline_v2(uuid)
  from public, anon;
grant execute on function public.read_authorized_cycle_timeline_v2(uuid)
  to authenticated;

comment on function public.read_authorized_cycle_timeline_v2(uuid) is
  'F2 v2 minimized projection with explicit abstention and explainable non-medical estimates.';
