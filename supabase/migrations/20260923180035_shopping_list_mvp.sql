-- Shopping List is an intention-only module. Its records never create a
-- financial event, GL posting, envelope movement, obligation or reservation.
begin;

create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  label text not null,
  estimated_amount numeric(14, 2),
  notes text,
  desired_date date,
  status text not null default 'planned',
  envelope_id uuid references public.envelopes(id),
  budget_goal_id uuid references public.budget_goals(id),
  final_priority integer,
  final_priority_set_by uuid references auth.users(id),
  final_priority_set_at timestamptz,
  purchased_financial_event_id uuid references public.financial_events(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  cancelled_by uuid references auth.users(id),
  cancelled_at timestamptz,
  cancellation_reason text,
  archived_by uuid references auth.users(id),
  archived_at timestamptz,
  constraint shopping_items_label_check
    check (char_length(trim(label)) between 1 and 160),
  constraint shopping_items_estimated_amount_check
    check (estimated_amount is null or estimated_amount > 0),
  constraint shopping_items_notes_check
    check (notes is null or char_length(trim(notes)) <= 2000),
  constraint shopping_items_status_check
    check (status in ('planned', 'purchased', 'cancelled', 'archived')),
  constraint shopping_items_final_priority_check
    check (final_priority is null or final_priority between 0 and 3),
  constraint shopping_items_final_priority_audit_check
    check (
      (final_priority is null and final_priority_set_by is null and final_priority_set_at is null)
      or (final_priority is not null and final_priority_set_by is not null and final_priority_set_at is not null)
    ),
  constraint shopping_items_purchase_link_check
    check (
      (status = 'purchased' and purchased_financial_event_id is not null)
      or (status <> 'purchased' and purchased_financial_event_id is null)
    ),
  constraint shopping_items_cancellation_audit_check
    check (
      (status = 'cancelled' and cancelled_by is not null and cancelled_at is not null)
      or (status <> 'cancelled' and cancelled_by is null and cancelled_at is null and cancellation_reason is null)
    ),
  constraint shopping_items_archive_audit_check
    check (
      (status = 'archived' and archived_by is not null and archived_at is not null)
      or (status <> 'archived' and archived_by is null and archived_at is null)
    ),
  constraint shopping_items_id_household_unique unique (id, household_id)
);

create index shopping_items_household_status_priority_idx
  on public.shopping_items(household_id, status, final_priority, desired_date, created_at);

create table public.shopping_item_member_priorities (
  shopping_item_id uuid not null,
  household_id uuid not null,
  member_user_id uuid not null references auth.users(id),
  priority integer not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (shopping_item_id, member_user_id),
  constraint shopping_item_member_priorities_item_household_fkey
    foreign key (shopping_item_id, household_id)
    references public.shopping_items(id, household_id) on delete cascade,
  constraint shopping_item_member_priorities_priority_check check (priority between 0 and 3)
);

create index shopping_item_member_priorities_household_idx
  on public.shopping_item_member_priorities(household_id, member_user_id);

create table public.shopping_item_history (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  shopping_item_id uuid not null,
  action text not null,
  changes jsonb not null default '{}'::jsonb,
  reason text,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint shopping_item_history_item_household_fkey
    foreign key (shopping_item_id, household_id)
    references public.shopping_items(id, household_id) on delete cascade,
  constraint shopping_item_history_action_check
    check (action in ('created', 'updated', 'member_priority_set', 'cancelled', 'archived')),
  constraint shopping_item_history_reason_check
    check (reason is null or char_length(trim(reason)) between 1 and 280)
);

create index shopping_item_history_item_created_idx
  on public.shopping_item_history(shopping_item_id, created_at desc);

alter table public.shopping_items enable row level security;
alter table public.shopping_item_member_priorities enable row level security;
alter table public.shopping_item_history enable row level security;

grant select on public.shopping_items, public.shopping_item_member_priorities,
  public.shopping_item_history to authenticated;
revoke insert, update, delete on public.shopping_items,
  public.shopping_item_member_priorities, public.shopping_item_history from anon, authenticated;

create policy "members read shopping items" on public.shopping_items
  for select to authenticated using (public.is_household_member(household_id));
create policy "members read shopping priorities" on public.shopping_item_member_priorities
  for select to authenticated using (public.is_household_member(household_id));
create policy "members read shopping history" on public.shopping_item_history
  for select to authenticated using (public.is_household_member(household_id));

create or replace function public.assert_shopping_item_links(
  p_household_id uuid,
  p_envelope_id uuid,
  p_budget_goal_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_envelope public.envelopes%rowtype;
  v_goal public.budget_goals%rowtype;
begin
  if p_envelope_id is not null then
    select * into v_envelope from public.envelopes
    where id = p_envelope_id and household_id = p_household_id
    for key share;
    if not found then raise exception 'L''enveloppe sélectionnée n''est pas valide.'; end if;
    if v_envelope.is_system then raise exception 'Une enveloppe système ne peut pas être liée à un achat prévu.'; end if;
    if v_envelope.archived_at is not null then raise exception 'Une enveloppe archivée ne peut pas être liée à un achat prévu.'; end if;
  end if;

  if p_budget_goal_id is not null then
    select * into v_goal from public.budget_goals
    where id = p_budget_goal_id and household_id = p_household_id
    for key share;
    if not found then raise exception 'L''objectif sélectionné n''est pas valide.'; end if;
    if v_goal.status = 'cancelled' then raise exception 'Un objectif annulé ne peut pas être lié à un achat prévu.'; end if;
    if p_envelope_id is not null
      and v_goal.funding_envelope_id is not null
      and v_goal.funding_envelope_id <> p_envelope_id then
      raise exception 'L''enveloppe doit correspondre à celle qui finance l''objectif.';
    end if;
  end if;
end;
$$;

create or replace function public.create_shopping_item(
  p_household_id uuid,
  p_label text,
  p_estimated_amount numeric default null,
  p_notes text default null,
  p_desired_date date default null,
  p_envelope_id uuid default null,
  p_budget_goal_id uuid default null,
  p_final_priority integer default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_item_id uuid;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;
  if char_length(trim(coalesce(p_label, ''))) not between 1 and 160 then
    raise exception 'Le libellé doit contenir entre 1 et 160 caractères.';
  end if;
  if p_estimated_amount is not null and p_estimated_amount <= 0 then
    raise exception 'Le montant estimé doit être strictement positif.';
  end if;
  if p_final_priority is not null and p_final_priority not between 0 and 3 then
    raise exception 'La priorité finale doit être comprise entre 0 et 3.';
  end if;
  if char_length(trim(coalesce(p_notes, ''))) > 2000 then
    raise exception 'Les notes ne peuvent pas dépasser 2 000 caractères.';
  end if;
  perform public.assert_shopping_item_links(p_household_id, p_envelope_id, p_budget_goal_id);
  insert into public.shopping_items(
    household_id, label, estimated_amount, notes, desired_date, envelope_id,
    budget_goal_id, final_priority, final_priority_set_by, final_priority_set_at,
    created_by, updated_by
  ) values (
    p_household_id, trim(p_label), p_estimated_amount,
    nullif(trim(coalesce(p_notes, '')), ''), p_desired_date, p_envelope_id,
    p_budget_goal_id, p_final_priority,
    case when p_final_priority is null then null else v_actor_id end,
    case when p_final_priority is null then null else now() end,
    v_actor_id, v_actor_id
  ) returning id into v_item_id;
  insert into public.shopping_item_history(household_id, shopping_item_id, action, changes, actor_id)
  values (p_household_id, v_item_id, 'created', jsonb_build_object('label', trim(p_label)), v_actor_id);
  return v_item_id;
end;
$$;

create or replace function public.update_shopping_item(
  p_household_id uuid,
  p_item_id uuid,
  p_label text,
  p_estimated_amount numeric default null,
  p_notes text default null,
  p_desired_date date default null,
  p_envelope_id uuid default null,
  p_budget_goal_id uuid default null,
  p_final_priority integer default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_item public.shopping_items%rowtype;
  v_changes jsonb;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  select * into v_item from public.shopping_items where id = p_item_id and household_id = p_household_id for update;
  if not found then raise exception 'Article introuvable.'; end if;
  if v_item.status in ('purchased', 'archived') then raise exception 'Cet article ne peut plus être modifié.'; end if;
  if char_length(trim(coalesce(p_label, ''))) not between 1 and 160 then raise exception 'Le libellé doit contenir entre 1 et 160 caractères.'; end if;
  if p_estimated_amount is not null and p_estimated_amount <= 0 then raise exception 'Le montant estimé doit être strictement positif.'; end if;
  if p_final_priority is not null and p_final_priority not between 0 and 3 then raise exception 'La priorité finale doit être comprise entre 0 et 3.'; end if;
  if char_length(trim(coalesce(p_notes, ''))) > 2000 then raise exception 'Les notes ne peuvent pas dépasser 2 000 caractères.'; end if;
  perform public.assert_shopping_item_links(p_household_id, p_envelope_id, p_budget_goal_id);
  v_changes := jsonb_build_object('before', jsonb_build_object('label', v_item.label, 'estimated_amount', v_item.estimated_amount, 'notes', v_item.notes, 'desired_date', v_item.desired_date, 'envelope_id', v_item.envelope_id, 'budget_goal_id', v_item.budget_goal_id, 'final_priority', v_item.final_priority), 'after', jsonb_build_object('label', trim(p_label), 'estimated_amount', p_estimated_amount, 'notes', nullif(trim(coalesce(p_notes, '')), ''), 'desired_date', p_desired_date, 'envelope_id', p_envelope_id, 'budget_goal_id', p_budget_goal_id, 'final_priority', p_final_priority));
  if v_changes -> 'before' = v_changes -> 'after' then return; end if;
  update public.shopping_items set label = trim(p_label), estimated_amount = p_estimated_amount,
    notes = nullif(trim(coalesce(p_notes, '')), ''), desired_date = p_desired_date,
    envelope_id = p_envelope_id, budget_goal_id = p_budget_goal_id,
    final_priority = p_final_priority,
    final_priority_set_by = case when p_final_priority is null then null else v_actor_id end,
    final_priority_set_at = case when p_final_priority is null then null else now() end,
    updated_by = v_actor_id, updated_at = now()
  where id = p_item_id and household_id = p_household_id;
  insert into public.shopping_item_history(household_id, shopping_item_id, action, changes, actor_id)
  values (p_household_id, p_item_id, 'updated', v_changes, v_actor_id);
end;
$$;

create or replace function public.set_shopping_item_member_priority(
  p_household_id uuid,
  p_item_id uuid,
  p_member_user_id uuid,
  p_priority integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_item public.shopping_items%rowtype;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  if p_member_user_id <> v_actor_id then raise exception 'Chaque membre peut définir uniquement sa propre priorité.'; end if;
  if p_priority not between 0 and 3 then raise exception 'La priorité doit être comprise entre 0 et 3.'; end if;
  if not exists (select 1 from public.household_members where household_id = p_household_id and user_id = p_member_user_id) then raise exception 'Le membre sélectionné n''appartient pas au foyer.'; end if;
  select * into v_item from public.shopping_items where id = p_item_id and household_id = p_household_id for update;
  if not found then raise exception 'Article introuvable.'; end if;
  if v_item.status in ('purchased', 'archived') then raise exception 'Cet article ne peut plus être priorisé.'; end if;
  insert into public.shopping_item_member_priorities(shopping_item_id, household_id, member_user_id, priority, created_by, updated_by)
  values (p_item_id, p_household_id, p_member_user_id, p_priority, v_actor_id, v_actor_id)
  on conflict (shopping_item_id, member_user_id) do update set priority = excluded.priority, updated_by = v_actor_id, updated_at = now();
  insert into public.shopping_item_history(household_id, shopping_item_id, action, changes, actor_id)
  values (p_household_id, p_item_id, 'member_priority_set', jsonb_build_object('member_user_id', p_member_user_id, 'priority', p_priority), v_actor_id);
end;
$$;

create or replace function public.cancel_shopping_item(
  p_household_id uuid,
  p_item_id uuid,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = public
as $$
declare v_actor_id uuid := auth.uid(); v_item public.shopping_items%rowtype;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  select * into v_item from public.shopping_items where id = p_item_id and household_id = p_household_id for update;
  if not found then raise exception 'Article introuvable.'; end if;
  if v_item.status <> 'planned' then raise exception 'Seul un article prévu peut être annulé.'; end if;
  if char_length(trim(coalesce(p_reason, ''))) > 280 then raise exception 'Le motif ne peut pas dépasser 280 caractères.'; end if;
  update public.shopping_items set status = 'cancelled', cancelled_by = v_actor_id, cancelled_at = now(), cancellation_reason = nullif(trim(coalesce(p_reason, '')), ''), updated_by = v_actor_id, updated_at = now() where id = p_item_id;
  insert into public.shopping_item_history(household_id, shopping_item_id, action, reason, actor_id)
  values (p_household_id, p_item_id, 'cancelled', nullif(trim(coalesce(p_reason, '')), ''), v_actor_id);
end;
$$;

create or replace function public.archive_shopping_item(
  p_household_id uuid,
  p_item_id uuid,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = public
as $$
declare v_actor_id uuid := auth.uid(); v_item public.shopping_items%rowtype;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  select * into v_item from public.shopping_items where id = p_item_id and household_id = p_household_id for update;
  if not found then raise exception 'Article introuvable.'; end if;
  if v_item.status = 'archived' then return; end if;
  if v_item.status = 'purchased' then raise exception 'Un achat matérialisé ne peut pas être archivé par ce MVP.'; end if;
  if char_length(trim(coalesce(p_reason, ''))) > 280 then raise exception 'Le motif ne peut pas dépasser 280 caractères.'; end if;
  update public.shopping_items set status = 'archived', archived_by = v_actor_id, archived_at = now(), updated_by = v_actor_id, updated_at = now() where id = p_item_id;
  insert into public.shopping_item_history(household_id, shopping_item_id, action, reason, actor_id)
  values (p_household_id, p_item_id, 'archived', nullif(trim(coalesce(p_reason, '')), ''), v_actor_id);
end;
$$;

revoke all on function public.assert_shopping_item_links(uuid, uuid, uuid) from public;
revoke all on function public.create_shopping_item(uuid, text, numeric, text, date, uuid, uuid, integer) from public;
revoke all on function public.update_shopping_item(uuid, uuid, text, numeric, text, date, uuid, uuid, integer) from public;
revoke all on function public.set_shopping_item_member_priority(uuid, uuid, uuid, integer) from public;
revoke all on function public.cancel_shopping_item(uuid, uuid, text) from public;
revoke all on function public.archive_shopping_item(uuid, uuid, text) from public;
grant execute on function public.create_shopping_item(uuid, text, numeric, text, date, uuid, uuid, integer) to authenticated;
grant execute on function public.update_shopping_item(uuid, uuid, text, numeric, text, date, uuid, uuid, integer) to authenticated;
grant execute on function public.set_shopping_item_member_priority(uuid, uuid, uuid, integer) to authenticated;
grant execute on function public.cancel_shopping_item(uuid, uuid, text) to authenticated;
grant execute on function public.archive_shopping_item(uuid, uuid, text) to authenticated;

commit;
