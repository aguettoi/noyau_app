-- PostgreSQL identity columns generated ALWAYS cannot be assigned an
-- arithmetic expression. DEFAULT advances the identity sequence while
-- preserving the expurgated one-row-per-household/topic invalidation model.
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
  insert into public.household_realtime_invalidations(
    household_id, topic, changed_at
  ) values (v_household_id, tg_table_name, now())
  on conflict (household_id, topic) do update
    set changed_at = excluded.changed_at,
        revision = default;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.emit_household_realtime_invalidation()
  from public, anon, authenticated, service_role;

create or replace function private.emit_account_privacy_consent_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id uuid := case when tg_op = 'DELETE' then old.request_id
                            else new.request_id end;
  v_household_id uuid;
begin
  select r.household_id into v_household_id
  from public.account_privacy_requests r where r.id = v_request_id;
  if v_household_id is not null then
    insert into public.household_realtime_invalidations(
      household_id, topic, changed_at
    ) values (v_household_id, 'account_privacy_requests', now())
    on conflict (household_id, topic) do update
      set changed_at = excluded.changed_at,
          revision = default;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.emit_account_privacy_consent_invalidation()
  from public, anon, authenticated, service_role;
