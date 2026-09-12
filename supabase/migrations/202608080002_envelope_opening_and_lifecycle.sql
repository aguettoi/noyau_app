-- Initial envelope balances and lifecycle. Apply manually after envelope ledger.
begin;

create table if not exists public.envelope_import_sessions (
  id uuid primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict,
  source text not null default 'csv' check (source in ('csv', 'manual')),
  status text not null default 'completed' check (status in ('completed', 'undone')),
  created_at timestamptz not null default now(),
  undone_at timestamptz,
  undone_by uuid references auth.users(id) on delete restrict,
  summary jsonb not null default '{}'::jsonb
);

create table if not exists public.envelope_import_session_envelopes (
  import_session_id uuid not null references public.envelope_import_sessions(id) on delete restrict,
  envelope_id uuid not null references public.envelopes(id) on delete restrict,
  created_envelope boolean not null,
  primary key (import_session_id, envelope_id)
);

alter table public.envelope_import_sessions enable row level security;
revoke all on table public.envelope_import_sessions from public, anon, authenticated;
revoke all on table public.envelope_import_session_envelopes from public, anon, authenticated;
grant select on table public.envelope_import_sessions to authenticated;
grant select on table public.envelope_import_session_envelopes to authenticated;
drop policy if exists "members read envelope import sessions" on public.envelope_import_sessions;
create policy "members read envelope import sessions"
  on public.envelope_import_sessions for select
  using (public.is_household_member(household_id));
alter table public.envelope_import_session_envelopes enable row level security;
drop policy if exists "members read envelope import session envelopes" on public.envelope_import_session_envelopes;
create policy "members read envelope import session envelopes"
  on public.envelope_import_session_envelopes for select
  using (exists (
    select 1 from public.envelope_import_sessions sessions
    where sessions.id = import_session_id
      and public.is_household_member(sessions.household_id)
  ));

alter table public.envelopes
  add column if not exists notes text,
  add column if not exists import_session_id uuid references public.envelope_import_sessions(id) on delete restrict;
alter table public.envelope_movements
  add column if not exists import_session_id uuid references public.envelope_import_sessions(id) on delete restrict;

revoke insert, update, delete, truncate on public.envelopes from authenticated;
grant select on public.envelopes to authenticated;
drop policy if exists "members manage envelopes" on public.envelopes;
drop policy if exists "members read envelopes" on public.envelopes;
create policy "members read envelopes"
  on public.envelopes for select
  using (public.is_household_member(household_id));

create index if not exists envelopes_import_session_idx
  on public.envelopes(import_session_id) where import_session_id is not null;
create index if not exists envelope_movements_import_session_idx
  on public.envelope_movements(import_session_id) where import_session_id is not null;

do $$
begin
  alter table public.envelope_movements
    drop constraint if exists envelope_movements_movement_type_check;
  alter table public.envelope_movements
    add constraint envelope_movements_movement_type_check check (movement_type in (
      'allocation', 'consumption', 'transfer_out', 'transfer_in', 'refund',
      'adjustment', 'reversal', 'opening', 'opening_offset'
    ));
  alter table public.envelope_movements
    drop constraint if exists envelope_movements_type_direction_check;
  alter table public.envelope_movements
    add constraint envelope_movements_type_direction_check check (
      (movement_type in ('allocation', 'transfer_in', 'refund', 'opening') and direction = 'inflow')
      or (movement_type in ('consumption', 'transfer_out', 'opening_offset') and direction = 'outflow')
      or movement_type in ('adjustment', 'reversal')
    );
end;
$$;

create or replace function public.assert_envelope_opening_group(
  p_movement_group_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_opening_count integer;
  v_offset_count integer;
  v_opening_amount numeric(14, 2);
  v_offset_amount numeric(14, 2);
  v_system_code text;
begin
  select count(*) filter (where movement_type = 'opening'),
         count(*) filter (where movement_type = 'opening_offset'),
         max(amount) filter (where movement_type = 'opening'),
         max(amount) filter (where movement_type = 'opening_offset')
    into v_opening_count, v_offset_count, v_opening_amount, v_offset_amount
  from public.envelope_movements
  where movement_group_id = p_movement_group_id;
  if v_opening_count = 0 and v_offset_count = 0 then
    return;
  end if;
  if v_opening_count <> 1 or v_offset_count <> 1
     or v_opening_amount <> v_offset_amount
     or exists (
       select 1 from public.envelope_movements
       where movement_group_id = p_movement_group_id
         and movement_type not in ('opening', 'opening_offset')
     ) then
    raise exception 'Opening group must contain one balanced opening and offset';
  end if;
  select envelopes.system_code into v_system_code
  from public.envelope_movements movements
  join public.envelopes on envelopes.id = movements.envelope_id
  where movements.movement_group_id = p_movement_group_id
    and movements.movement_type = 'opening_offset';
  if v_system_code is distinct from 'to_allocate' then
    raise exception 'Opening offset must use À répartir';
  end if;
end;
$$;

create or replace function public.assert_envelope_opening_group_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_envelope_opening_group(new.movement_group_id);
  return null;
end;
$$;

drop trigger if exists envelope_movements_opening_group_valid on public.envelope_movements;
create constraint trigger envelope_movements_opening_group_valid
after insert on public.envelope_movements
deferrable initially deferred
for each row execute function public.assert_envelope_opening_group_trigger();

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
  v_session_id uuid := coalesce(p_import_session_id, gen_random_uuid());
  v_item jsonb;
  v_name text;
  v_normalized text;
  v_notes text;
  v_status text;
  v_opening numeric(14, 2);
  v_envelope_id uuid;
  v_to_allocate_id uuid;
  v_group_id uuid;
  v_created integer := 0;
  v_existing integer := 0;
  v_initialized_existing integer := 0;
  v_ignored integer := 0;
  v_seen text[] := '{}';
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if jsonb_typeof(p_names) <> 'array' then
    raise exception 'Envelope rows must be an array';
  end if;
  insert into public.envelope_import_sessions(id, household_id, created_by, source)
  values (v_session_id, p_household_id, auth.uid(), 'csv')
  on conflict (id) do nothing;
  if exists (
    select 1 from public.envelope_import_sessions
    where id = v_session_id and household_id <> p_household_id
  ) then
    raise exception 'Import session does not belong to household';
  end if;
  if exists (
    select 1 from public.envelope_import_sessions
    where id = v_session_id and household_id = p_household_id
      and summary <> '{}'::jsonb
  ) then
    return (
      select summary || jsonb_build_object('import_session_id', v_session_id)
      from public.envelope_import_sessions where id = v_session_id
    );
  end if;

  for v_item in select value from jsonb_array_elements(p_names) value
  loop
    if jsonb_typeof(v_item) = 'string' then
      v_name := trim(v_item #>> '{}');
      v_opening := 0;
      v_status := 'actif';
      v_notes := null;
    elsif jsonb_typeof(v_item) = 'object' then
      v_name := trim(coalesce(v_item->>'name', ''));
      v_status := lower(trim(coalesce(v_item->>'status', 'actif')));
      v_notes := nullif(trim(coalesce(v_item->>'notes', '')), '');
      begin
        v_opening := coalesce(nullif(replace(trim(coalesce(v_item->>'opening_balance', '')), ',', '.'), '')::numeric, 0);
      exception when invalid_text_representation then
        raise exception 'Invalid opening balance for envelope %', v_name;
      end;
    else
      raise exception 'Envelope row must be a string or object';
    end if;
    v_normalized := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
    if v_normalized = '' or v_normalized = any(v_seen) then
      v_ignored := v_ignored + 1;
      continue;
    end if;
    if v_opening < 0 then
      raise exception 'Opening balance cannot be negative';
    end if;
    if v_status not in ('actif', 'inactif') then
      raise exception 'Envelope status must be actif or inactif';
    end if;
    v_seen := array_append(v_seen, v_normalized);
    select id into v_envelope_id from public.envelopes
      where household_id = p_household_id
        and lower(regexp_replace(trim(name), '\s+', ' ', 'g')) = v_normalized
      limit 1;
    if found then
      if v_opening = 0 then
        v_existing := v_existing + 1;
        continue;
      end if;
      if exists (
        select 1 from public.envelope_movements
        where household_id = p_household_id and envelope_id = v_envelope_id
      ) or exists (
        select 1 from public.envelope_import_session_envelopes
        where envelope_id = v_envelope_id
      ) or exists (
        select 1 from public.envelopes where id = v_envelope_id and is_system
      ) then
        raise exception 'Existing envelope % cannot receive a retrospective opening balance', v_name;
      end if;
      update public.envelopes set
        notes = v_notes,
        archived_at = case when v_status = 'inactif' then now() else null end
      where id = v_envelope_id;
      insert into public.envelope_import_session_envelopes(
        import_session_id, envelope_id, created_envelope
      ) values (v_session_id, v_envelope_id, false);
      v_initialized_existing := v_initialized_existing + 1;
    else
      insert into public.envelopes(
        household_id, name, notes, archived_at, import_session_id
      ) values (
        p_household_id, regexp_replace(v_name, '\s+', ' ', 'g'), v_notes,
        case when v_status = 'inactif' then now() else null end, v_session_id
      ) returning id into v_envelope_id;
      insert into public.envelope_import_session_envelopes(
        import_session_id, envelope_id, created_envelope
      ) values (v_session_id, v_envelope_id, true);
      v_created := v_created + 1;
    end if;
    if v_opening > 0 then
      v_to_allocate_id := public.ensure_household_system_envelope(p_household_id, 'to_allocate');
      v_group_id := gen_random_uuid();
      insert into public.envelope_movements(
        household_id, envelope_id, movement_group_id, movement_type, direction,
        amount, occurred_at, description, created_by, import_session_id
      ) values
        (p_household_id, v_envelope_id, v_group_id, 'opening', 'inflow',
          v_opening, now(), 'Solde initial importé', auth.uid(), v_session_id),
        (p_household_id, v_to_allocate_id, v_group_id, 'opening_offset', 'outflow',
          v_opening, now(), 'Contrepartie du solde initial importé', auth.uid(), v_session_id);
    end if;
  end loop;
  update public.envelope_import_sessions
  set summary = jsonb_build_object(
    'created', v_created, 'initialized_existing', v_initialized_existing,
    'existing', v_existing, 'ignored', v_ignored, 'errors', '[]'::jsonb
  )
  where id = v_session_id;
  return jsonb_build_object(
    'created', v_created, 'initialized_existing', v_initialized_existing,
    'existing', v_existing, 'ignored', v_ignored,
    'errors', '[]'::jsonb, 'import_session_id', v_session_id
  );
end;
$$;

create or replace function public.update_household_envelope(
  p_household_id uuid,
  p_envelope_id uuid,
  p_name text,
  p_notes text,
  p_archived boolean
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Envelope name is required';
  end if;
  if exists (
    select 1 from public.envelopes
    where household_id = p_household_id and id <> p_envelope_id
      and lower(regexp_replace(trim(name), '\s+', ' ', 'g')) = lower(regexp_replace(trim(p_name), '\s+', ' ', 'g'))
  ) then raise exception 'Envelope name already exists'; end if;
  update public.envelopes set name = regexp_replace(trim(p_name), '\s+', ' ', 'g'),
    notes = nullif(trim(coalesce(p_notes, '')), ''),
    archived_at = case when p_archived then coalesce(archived_at, now()) else null end
  where id = p_envelope_id and household_id = p_household_id and not is_system;
  if not found then raise exception 'Envelope not found or protected'; end if;
end;
$$;

create or replace function public.delete_household_envelope(
  p_household_id uuid, p_envelope_id uuid
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if exists (select 1 from public.envelope_movements where envelope_id = p_envelope_id and household_id = p_household_id) then
    raise exception 'Envelope with ledger history must be archived';
  end if;
  delete from public.envelopes where id = p_envelope_id and household_id = p_household_id and not is_system;
  if not found then raise exception 'Envelope not found or protected'; end if;
end;
$$;

create or replace function public.create_household_envelope(
  p_household_id uuid,
  p_name text,
  p_opening_balance numeric default 0,
  p_notes text default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_result jsonb; v_session_id uuid := gen_random_uuid();
begin
  v_result := public.import_household_envelopes(
    p_household_id,
    jsonb_build_array(jsonb_build_object(
      'name', p_name, 'opening_balance', p_opening_balance,
      'status', 'actif', 'notes', p_notes
    )),
    v_session_id
  );
  update public.envelope_import_sessions set source = 'manual'
  where id = v_session_id;
  return v_result;
end;
$$;

create or replace function public.undo_last_envelope_import(
  p_household_id uuid
) returns integer
language plpgsql security definer set search_path = public
as $$
declare v_session_id uuid; v_count integer := 0; v_movement record;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  select id into v_session_id from public.envelope_import_sessions
  where household_id = p_household_id and source = 'csv' and status = 'completed'
  order by created_at desc limit 1;
  if v_session_id is null then return 0; end if;
  if exists (
    select 1 from public.envelope_movements movements
    join public.envelope_import_session_envelopes session_envelopes
      on session_envelopes.envelope_id = movements.envelope_id
    where session_envelopes.import_session_id = v_session_id
      and movements.import_session_id is distinct from v_session_id
  ) then
    raise exception 'Import cannot be undone after later envelope activity';
  end if;
  for v_movement in
    select * from public.envelope_movements
    where import_session_id = v_session_id and movement_type in ('opening', 'opening_offset')
  loop
    insert into public.envelope_movements(
      household_id, envelope_id, movement_group_id, movement_type, direction,
      amount, occurred_at, description, reversal_of, created_by
    ) values (
      v_movement.household_id, v_movement.envelope_id, gen_random_uuid(), 'reversal',
      case when v_movement.direction = 'inflow' then 'outflow' else 'inflow' end,
      v_movement.amount, now(), 'Annulation du solde initial importé', v_movement.id, auth.uid()
    );
  end loop;
  update public.envelopes envelopes set archived_at = now()
  from public.envelope_import_session_envelopes session_envelopes
  where session_envelopes.import_session_id = v_session_id
    and session_envelopes.envelope_id = envelopes.id
    and session_envelopes.created_envelope
    and envelopes.household_id = p_household_id
    and not envelopes.is_system;
  get diagnostics v_count = row_count;
  update public.envelope_import_sessions
  set status = 'undone', undone_at = now(), undone_by = auth.uid()
  where id = v_session_id;
  return v_count;
end;
$$;

revoke all on function public.import_household_envelopes(uuid, jsonb, uuid),
  public.update_household_envelope(uuid, uuid, text, text, boolean),
  public.delete_household_envelope(uuid, uuid),
  public.create_household_envelope(uuid, text, numeric, text),
  public.undo_last_envelope_import(uuid) from public, anon;
grant execute on function public.import_household_envelopes(uuid, jsonb, uuid),
  public.update_household_envelope(uuid, uuid, text, text, boolean),
  public.delete_household_envelope(uuid, uuid),
  public.create_household_envelope(uuid, text, numeric, text),
  public.undo_last_envelope_import(uuid) to authenticated;

commit;
