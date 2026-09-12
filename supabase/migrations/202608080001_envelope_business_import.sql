begin;

create or replace function public.import_household_envelopes(
  p_household_id uuid,
  p_names jsonb,
  p_import_session_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_normalized text;
  v_created integer := 0;
  v_existing integer := 0;
  v_ignored integer := 0;
  v_seen text[] := '{}';
  v_sheet_run_id uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if jsonb_typeof(p_names) <> 'array' then
    raise exception 'Envelope names must be an array';
  end if;
  if p_import_session_id is not null then
    select id into v_sheet_run_id
    from public.import_sheet_runs
    where import_session_id = p_import_session_id
      and importer_id = 'envelopes'
      and status = 'completed';
    if v_sheet_run_id is null then
      raise exception 'Envelope source import session is unavailable';
    end if;
  end if;

  for v_name in select trim(value) from jsonb_array_elements_text(p_names) value
  loop
    v_normalized := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
    if v_normalized = '' or v_normalized = any(v_seen) then
      v_ignored := v_ignored + 1;
      continue;
    end if;
    v_seen := array_append(v_seen, v_normalized);
    if exists (
      select 1 from public.envelopes
      where household_id = p_household_id
        and lower(regexp_replace(trim(name), '\s+', ' ', 'g')) = v_normalized
    ) then
      v_existing := v_existing + 1;
    else
      insert into public.envelopes (household_id, name)
      values (p_household_id, v_name);
      v_created := v_created + 1;
    end if;
  end loop;

  if v_sheet_run_id is not null then
    insert into public.import_operation_journal (
      import_sheet_run_id, operation_index, entity_type, operation,
      forward_payload, undo_payload, applied_at
    ) values (
      v_sheet_run_id, 1, 'envelopes', 'insert',
      jsonb_build_object('created', v_created, 'existing', v_existing, 'ignored', v_ignored),
      '{}'::jsonb, now()
    ) on conflict (import_sheet_run_id, operation_index) do update
      set forward_payload = excluded.forward_payload, applied_at = excluded.applied_at;
  end if;

  return jsonb_build_object('created', v_created, 'existing', v_existing, 'ignored', v_ignored);
end;
$$;

revoke all on function public.import_household_envelopes(uuid, jsonb, uuid) from public, anon;
grant execute on function public.import_household_envelopes(uuid, jsonb, uuid) to authenticated;

commit;
