-- Savings goals are planning metadata. They never create financial events,
-- ledger postings or envelope movements: progress is derived by the client
-- from the canonical envelope ledger.
begin;

alter table public.budget_goals
  add column if not exists goal_type text not null default 'custom',
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists closed_at timestamptz,
  add column if not exists closed_by uuid references auth.users(id),
  add column if not exists closure_reason text;

alter table public.budget_goals
  drop constraint if exists budget_goals_goal_type_check,
  add constraint budget_goals_goal_type_check
    check (goal_type in (
      'car', 'travel', 'major_purchase', 'home_down_payment',
      'emergency_fund', 'custom'
    )),
  drop constraint if exists budget_goals_closed_status_check,
  add constraint budget_goals_closed_status_check check (
    (status in ('completed', 'cancelled') and closed_at is not null and closed_by is not null)
    or (status not in ('completed', 'cancelled') and closed_at is null and closed_by is null)
  ),
  drop constraint if exists budget_goals_closure_reason_length_check,
  add constraint budget_goals_closure_reason_length_check
    check (closure_reason is null or char_length(trim(closure_reason)) between 1 and 280);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.budget_goals'::regclass
      and conname = 'budget_goals_id_household_unique'
  ) then
    alter table public.budget_goals
      add constraint budget_goals_id_household_unique unique (id, household_id);
  end if;
end;
$$;

-- A non-closed goal owns one ordinary envelope. Closed goals remain immutable
-- historical records and release the envelope for a later goal if desired.
create unique index if not exists budget_goals_one_open_goal_per_envelope
  on public.budget_goals(household_id, funding_envelope_id)
  where funding_envelope_id is not null
    and status in ('planned', 'active', 'paused');

create table if not exists public.budget_goal_history (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  goal_id uuid not null,
  action text not null check (action in (
    'created', 'updated', 'activated', 'paused', 'resumed', 'completed', 'cancelled'
  )),
  changes jsonb not null default '{}'::jsonb,
  reason text,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (goal_id, household_id)
    references public.budget_goals(id, household_id) on delete restrict,
  check (reason is null or char_length(trim(reason)) between 1 and 280)
);

create index if not exists budget_goal_history_goal_created_idx
  on public.budget_goal_history(goal_id, created_at desc);

alter table public.budget_goal_history enable row level security;
revoke all on public.budget_goal_history from public, anon;
grant select on public.budget_goal_history to authenticated;
drop policy if exists "members read budget goal history" on public.budget_goal_history;
create policy "members read budget goal history"
  on public.budget_goal_history for select
  using (public.is_household_member(household_id));

-- Goal mutations go through server-owned functions so the actor is auth.uid()
-- rather than an identifier supplied by Flutter.
revoke insert, update, delete on public.budget_goals from authenticated;

create or replace function public.assert_budget_goal_envelope(
  p_household_id uuid,
  p_envelope_id uuid,
  p_goal_id uuid default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_system boolean;
  v_archived_at timestamptz;
begin
  select is_system, archived_at
    into v_is_system, v_archived_at
  from public.envelopes
  where id = p_envelope_id
    and household_id = p_household_id
  for key share;

  if not found then
    raise exception 'L''enveloppe sélectionnée n''est pas valide.';
  end if;
  if v_is_system then
    raise exception 'Une enveloppe système ne peut pas financer un objectif.';
  end if;
  if v_archived_at is not null then
    raise exception 'Une enveloppe archivée ne peut pas financer un objectif.';
  end if;
  if exists (
    select 1
    from public.budget_goals
    where household_id = p_household_id
      and funding_envelope_id = p_envelope_id
      and status in ('planned', 'active', 'paused')
      and (p_goal_id is null or id <> p_goal_id)
  ) then
    raise exception 'Cette enveloppe finance déjà un objectif non clôturé.';
  end if;
end;
$$;

create or replace function public.create_budget_goal(
  p_household_id uuid,
  p_name text,
  p_goal_type text,
  p_target_amount numeric,
  p_target_date date,
  p_priority integer,
  p_funding_envelope_id uuid,
  p_monthly_target numeric,
  p_notes text,
  p_status text default 'planned'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_goal_id uuid;
  v_actor_id uuid := auth.uid();
  v_status text := coalesce(nullif(trim(p_status), ''), 'planned');
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;
  if char_length(trim(coalesce(p_name, ''))) not between 1 and 120 then
    raise exception 'Le nom de l''objectif doit contenir entre 1 et 120 caractères.';
  end if;
  if p_goal_type not in ('car', 'travel', 'major_purchase', 'home_down_payment', 'emergency_fund', 'custom') then
    raise exception 'Le type d''objectif est invalide.';
  end if;
  if p_target_amount is null or p_target_amount <= 0 then
    raise exception 'La cible financière doit être strictement positive.';
  end if;
  if p_monthly_target is not null and p_monthly_target < 0 then
    raise exception 'La cible mensuelle ne peut pas être négative.';
  end if;
  if v_status not in ('planned', 'active', 'paused') then
    raise exception 'Le statut initial de l''objectif est invalide.';
  end if;
  if p_funding_envelope_id is null then
    raise exception 'Une enveloppe dédiée est obligatoire.';
  end if;

  perform public.assert_budget_goal_envelope(
    p_household_id, p_funding_envelope_id, null
  );

  insert into public.budget_goals(
    household_id, name, goal_type, target_amount, target_date, priority,
    status, funding_envelope_id, monthly_target, notes,
    created_by, created_at, updated_by, updated_at
  ) values (
    p_household_id, trim(p_name), p_goal_type, p_target_amount, p_target_date,
    coalesce(p_priority, 0), v_status, p_funding_envelope_id,
    p_monthly_target, nullif(trim(coalesce(p_notes, '')), ''),
    v_actor_id, now(), v_actor_id, now()
  ) returning id into v_goal_id;

  insert into public.budget_goal_history(
    household_id, goal_id, action, changes, actor_id
  ) values (
    p_household_id, v_goal_id, 'created',
    jsonb_build_object(
      'name', trim(p_name), 'goal_type', p_goal_type,
      'target_amount', p_target_amount, 'target_date', p_target_date,
      'priority', coalesce(p_priority, 0), 'status', v_status,
      'funding_envelope_id', p_funding_envelope_id,
      'monthly_target', p_monthly_target
    ), v_actor_id
  );
  return v_goal_id;
end;
$$;

create or replace function public.update_budget_goal(
  p_household_id uuid,
  p_goal_id uuid,
  p_name text,
  p_goal_type text,
  p_target_amount numeric,
  p_target_date date,
  p_priority integer,
  p_funding_envelope_id uuid,
  p_monthly_target numeric,
  p_notes text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_goal public.budget_goals%rowtype;
  v_changes jsonb;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;
  select * into v_goal
  from public.budget_goals
  where id = p_goal_id and household_id = p_household_id
  for update;
  if not found then raise exception 'Objectif introuvable.'; end if;
  if v_goal.status in ('completed', 'cancelled') then
    raise exception 'Un objectif clôturé ne peut plus être modifié.';
  end if;
  if char_length(trim(coalesce(p_name, ''))) not between 1 and 120 then
    raise exception 'Le nom de l''objectif doit contenir entre 1 et 120 caractères.';
  end if;
  if p_goal_type not in ('car', 'travel', 'major_purchase', 'home_down_payment', 'emergency_fund', 'custom') then
    raise exception 'Le type d''objectif est invalide.';
  end if;
  if p_target_amount is null or p_target_amount <= 0 then
    raise exception 'La cible financière doit être strictement positive.';
  end if;
  if p_monthly_target is not null and p_monthly_target < 0 then
    raise exception 'La cible mensuelle ne peut pas être négative.';
  end if;
  if p_funding_envelope_id is null then
    raise exception 'Une enveloppe dédiée est obligatoire.';
  end if;
  perform public.assert_budget_goal_envelope(
    p_household_id, p_funding_envelope_id, p_goal_id
  );

  v_changes := jsonb_build_object(
    'before', jsonb_build_object(
      'name', v_goal.name, 'goal_type', v_goal.goal_type,
      'target_amount', v_goal.target_amount, 'target_date', v_goal.target_date,
      'priority', v_goal.priority, 'funding_envelope_id', v_goal.funding_envelope_id,
      'monthly_target', v_goal.monthly_target, 'notes', v_goal.notes
    ),
    'after', jsonb_build_object(
      'name', trim(p_name), 'goal_type', p_goal_type,
      'target_amount', p_target_amount, 'target_date', p_target_date,
      'priority', coalesce(p_priority, 0), 'funding_envelope_id', p_funding_envelope_id,
      'monthly_target', p_monthly_target,
      'notes', nullif(trim(coalesce(p_notes, '')), '')
    )
  );
  if v_changes -> 'before' = v_changes -> 'after' then return; end if;

  update public.budget_goals set
    name = trim(p_name), goal_type = p_goal_type,
    target_amount = p_target_amount, target_date = p_target_date,
    priority = coalesce(p_priority, 0), funding_envelope_id = p_funding_envelope_id,
    monthly_target = p_monthly_target,
    notes = nullif(trim(coalesce(p_notes, '')), ''),
    updated_by = v_actor_id, updated_at = now()
  where id = p_goal_id and household_id = p_household_id;

  insert into public.budget_goal_history(
    household_id, goal_id, action, changes, actor_id
  ) values (p_household_id, p_goal_id, 'updated', v_changes, v_actor_id);
end;
$$;

create or replace function public.set_budget_goal_status(
  p_household_id uuid,
  p_goal_id uuid,
  p_status text,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_goal public.budget_goals%rowtype;
  v_action text;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;
  select * into v_goal
  from public.budget_goals
  where id = p_goal_id and household_id = p_household_id
  for update;
  if not found then raise exception 'Objectif introuvable.'; end if;
  if p_status not in ('active', 'paused', 'completed', 'cancelled') then
    raise exception 'Le statut demandé est invalide.';
  end if;
  if v_goal.status = p_status then return; end if;
  if v_goal.status in ('completed', 'cancelled') then
    raise exception 'Un objectif clôturé ne peut pas être réouvert.';
  end if;
  if p_status = 'active' then
    perform public.assert_budget_goal_envelope(
      p_household_id, v_goal.funding_envelope_id, p_goal_id
    );
    v_action := case when v_goal.status = 'paused' then 'resumed' else 'activated' end;
  elsif p_status = 'paused' then
    v_action := 'paused';
  elsif p_status = 'completed' then
    v_action := 'completed';
  else
    v_action := 'cancelled';
  end if;
  if p_status in ('completed', 'cancelled')
    and char_length(trim(coalesce(p_reason, ''))) > 280 then
    raise exception 'Le motif ne peut pas dépasser 280 caractères.';
  end if;

  update public.budget_goals set
    status = p_status,
    updated_by = v_actor_id,
    updated_at = now(),
    closed_at = case when p_status in ('completed', 'cancelled') then now() else null end,
    closed_by = case when p_status in ('completed', 'cancelled') then v_actor_id else null end,
    closure_reason = case when p_status in ('completed', 'cancelled') then nullif(trim(coalesce(p_reason, '')), '') else null end
  where id = p_goal_id and household_id = p_household_id;

  insert into public.budget_goal_history(
    household_id, goal_id, action, changes, reason, actor_id
  ) values (
    p_household_id, p_goal_id, v_action,
    jsonb_build_object('from_status', v_goal.status, 'to_status', p_status),
    nullif(trim(coalesce(p_reason, '')), ''), v_actor_id
  );
end;
$$;

revoke all on function public.assert_budget_goal_envelope(uuid, uuid, uuid) from public;
grant execute on function public.create_budget_goal(uuid, text, text, numeric, date, integer, uuid, numeric, text, text) to authenticated;
grant execute on function public.update_budget_goal(uuid, uuid, text, text, numeric, date, integer, uuid, numeric, text) to authenticated;
grant execute on function public.set_budget_goal_status(uuid, uuid, text, text) to authenticated;

commit;
