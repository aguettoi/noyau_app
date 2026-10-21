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
    set changed_at = excluded.changed_at;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.emit_household_realtime_invalidation()
  from public, anon, authenticated;
