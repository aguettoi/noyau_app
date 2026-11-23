-- F2 owner-only structured LH/BBT observations must be complete and must not
-- leak structured fields into unrelated private journal categories.

alter table public.member_cycle_private_entries
  drop constraint if exists member_cycle_private_entries_structured_measurement_check;

alter table public.member_cycle_private_entries
  add constraint member_cycle_private_entries_structured_measurement_check check (
    (category = 'lh_test'
      and observed_at is not null
      and test_result is not null
      and test_result in ('negative','positive')
      and measurement_value is null
      and measurement_unit is null)
    or (category = 'basal_temperature'
      and observed_at is not null
      and test_result is null
      and measurement_value is not null
      and measurement_unit in ('celsius','fahrenheit')
      and ((measurement_unit = 'celsius' and measurement_value between 30 and 45)
        or (measurement_unit = 'fahrenheit' and measurement_value between 86 and 113)))
    or (category not in ('lh_test','basal_temperature')
      and observed_at is null
      and test_result is null
      and measurement_value is null
      and measurement_unit is null)
  );
