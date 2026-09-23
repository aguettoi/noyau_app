-- PRIOS is planning metadata only. It orders existing Shopping List items and
-- savings goals; it never creates financial events, ledger postings, envelope
-- movements, obligations, or budget allocations.
begin;

create table public.priority_plans (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  status text not null default 'planned',
  monthly_capacity numeric(14, 2),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  constraint priority_plans_name_check check (char_length(trim(name)) between 1 and 120),
  constraint priority_plans_status_check check (status in ('planned', 'active', 'paused', 'archived')),
  constraint priority_plans_monthly_capacity_check check (monthly_capacity is null or monthly_capacity > 0),
  constraint priority_plans_notes_check check (notes is null or char_length(trim(notes)) <= 2000),
  constraint priority_plans_id_household_unique unique (id, household_id)
);

create index priority_plans_household_status_idx
  on public.priority_plans(household_id, status, updated_at desc);

create table public.priority_plan_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  plan_id uuid not null,
  rank integer not null,
  shopping_item_id uuid,
  budget_goal_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  constraint priority_plan_items_one_source_check
    check (num_nonnulls(shopping_item_id, budget_goal_id) = 1),
  constraint priority_plan_items_rank_check check (rank > 0),
  constraint priority_plan_items_plan_household_fkey
    foreign key (plan_id, household_id)
    references public.priority_plans(id, household_id) on delete cascade,
  constraint priority_plan_items_shopping_household_fkey
    foreign key (shopping_item_id, household_id)
    references public.shopping_items(id, household_id) on delete restrict,
  constraint priority_plan_items_goal_household_fkey
    foreign key (budget_goal_id, household_id)
    references public.budget_goals(id, household_id) on delete restrict,
  constraint priority_plan_items_rank_unique unique (plan_id, rank) deferrable initially immediate
);

create unique index priority_plan_items_one_shopping_per_plan
  on public.priority_plan_items(plan_id, shopping_item_id)
  where shopping_item_id is not null;
create unique index priority_plan_items_one_goal_per_plan
  on public.priority_plan_items(plan_id, budget_goal_id)
  where budget_goal_id is not null;
create index priority_plan_items_plan_rank_idx
  on public.priority_plan_items(plan_id, rank);

create table public.priority_plan_history (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  plan_id uuid not null,
  action text not null check (action in (
    'created', 'updated', 'activated', 'paused', 'archived',
    'item_added', 'item_removed', 'items_reordered'
  )),
  changes jsonb not null default '{}'::jsonb,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (plan_id, household_id)
    references public.priority_plans(id, household_id) on delete cascade
);

create index priority_plan_history_plan_created_idx
  on public.priority_plan_history(plan_id, created_at desc);

alter table public.priority_plans enable row level security;
alter table public.priority_plan_items enable row level security;
alter table public.priority_plan_history enable row level security;

grant select on public.priority_plans, public.priority_plan_items,
  public.priority_plan_history to authenticated;
revoke insert, update, delete on public.priority_plans, public.priority_plan_items,
  public.priority_plan_history from anon, authenticated;

create policy "members read priority plans" on public.priority_plans
  for select to authenticated using (public.is_household_member(household_id));
create policy "members read priority plan items" on public.priority_plan_items
  for select to authenticated using (public.is_household_member(household_id));
create policy "members read priority plan history" on public.priority_plan_history
  for select to authenticated using (public.is_household_member(household_id));

create or replace function public.assert_priority_plan_source(
  p_household_id uuid,
  p_plan_id uuid,
  p_shopping_item_id uuid,
  p_budget_goal_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_linked_goal_id uuid;
  v_shopping_status text;
  v_goal_status text;
begin
  if num_nonnulls(p_shopping_item_id, p_budget_goal_id) <> 1 then
    raise exception 'Une priorité doit référencer soit un achat, soit un objectif.';
  end if;

  if p_shopping_item_id is not null then
    select budget_goal_id, status into v_linked_goal_id, v_shopping_status
    from public.shopping_items
    where id = p_shopping_item_id and household_id = p_household_id
    for key share;
    if not found then raise exception 'L''achat sélectionné n''est pas valide.'; end if;
    if v_shopping_status <> 'planned' then
      raise exception 'Seul un achat prévu peut être ajouté aux priorités.';
    end if;
    if exists (
      select 1 from public.priority_plan_items
      where plan_id = p_plan_id and shopping_item_id = p_shopping_item_id
    ) then
      raise exception 'Cet achat est déjà présent dans le plan.';
    end if;
    if v_linked_goal_id is not null and exists (
      select 1 from public.priority_plan_items
      where plan_id = p_plan_id and budget_goal_id = v_linked_goal_id
    ) then
      raise exception 'Cet achat est déjà relié à un objectif présent dans le plan.';
    end if;
    return;
  end if;

  select status into v_goal_status
  from public.budget_goals
  where id = p_budget_goal_id and household_id = p_household_id
  for key share;
  if not found then raise exception 'L''objectif sélectionné n''est pas valide.'; end if;
  if v_goal_status in ('completed', 'cancelled') then
    raise exception 'Un objectif clôturé ne peut pas être ajouté aux priorités.';
  end if;
  if exists (
    select 1 from public.priority_plan_items
    where plan_id = p_plan_id and budget_goal_id = p_budget_goal_id
  ) then
    raise exception 'Cet objectif est déjà présent dans le plan.';
  end if;
  if exists (
    select 1
    from public.priority_plan_items item
    join public.shopping_items shopping
      on shopping.id = item.shopping_item_id
      and shopping.household_id = item.household_id
    where item.plan_id = p_plan_id
      and shopping.budget_goal_id = p_budget_goal_id
  ) then
    raise exception 'Un achat déjà lié à cet objectif est présent dans le plan.';
  end if;
end;
$$;

create or replace function public.create_priority_plan(
  p_household_id uuid,
  p_name text,
  p_monthly_capacity numeric default null,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_plan_id uuid;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;
  if char_length(trim(coalesce(p_name, ''))) not between 1 and 120 then
    raise exception 'Le nom du plan doit contenir entre 1 et 120 caractères.';
  end if;
  if p_monthly_capacity is not null and p_monthly_capacity <= 0 then
    raise exception 'La capacité mensuelle doit être strictement positive.';
  end if;
  if char_length(trim(coalesce(p_notes, ''))) > 2000 then
    raise exception 'Les notes ne peuvent pas dépasser 2 000 caractères.';
  end if;
  insert into public.priority_plans(
    household_id, name, monthly_capacity, notes, created_by, updated_by
  ) values (
    p_household_id, trim(p_name), p_monthly_capacity,
    nullif(trim(coalesce(p_notes, '')), ''), v_actor_id, v_actor_id
  ) returning id into v_plan_id;
  insert into public.priority_plan_history(household_id, plan_id, action, changes, actor_id)
  values (p_household_id, v_plan_id, 'created', jsonb_build_object(
    'name', trim(p_name), 'monthly_capacity', p_monthly_capacity
  ), v_actor_id);
  return v_plan_id;
end;
$$;

create or replace function public.update_priority_plan(
  p_household_id uuid,
  p_plan_id uuid,
  p_name text,
  p_monthly_capacity numeric default null,
  p_notes text default null
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_plan public.priority_plans%rowtype;
  v_changes jsonb;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  select * into v_plan from public.priority_plans where id = p_plan_id and household_id = p_household_id for update;
  if not found then raise exception 'Plan introuvable.'; end if;
  if v_plan.status = 'archived' then raise exception 'Un plan archivé ne peut plus être modifié.'; end if;
  if char_length(trim(coalesce(p_name, ''))) not between 1 and 120 then raise exception 'Le nom du plan doit contenir entre 1 et 120 caractères.'; end if;
  if p_monthly_capacity is not null and p_monthly_capacity <= 0 then raise exception 'La capacité mensuelle doit être strictement positive.'; end if;
  if char_length(trim(coalesce(p_notes, ''))) > 2000 then raise exception 'Les notes ne peuvent pas dépasser 2 000 caractères.'; end if;
  v_changes := jsonb_build_object('before', jsonb_build_object('name', v_plan.name, 'monthly_capacity', v_plan.monthly_capacity, 'notes', v_plan.notes), 'after', jsonb_build_object('name', trim(p_name), 'monthly_capacity', p_monthly_capacity, 'notes', nullif(trim(coalesce(p_notes, '')), '')));
  if v_changes -> 'before' = v_changes -> 'after' then return; end if;
  update public.priority_plans set name = trim(p_name), monthly_capacity = p_monthly_capacity,
    notes = nullif(trim(coalesce(p_notes, '')), ''), updated_by = v_actor_id, updated_at = now()
  where id = p_plan_id and household_id = p_household_id;
  insert into public.priority_plan_history(household_id, plan_id, action, changes, actor_id)
  values (p_household_id, p_plan_id, 'updated', v_changes, v_actor_id);
end;
$$;

create or replace function public.set_priority_plan_status(
  p_household_id uuid,
  p_plan_id uuid,
  p_status text
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_plan public.priority_plans%rowtype;
  v_action text;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  if p_status not in ('active', 'paused', 'archived') then raise exception 'Le statut demandé est invalide.'; end if;
  select * into v_plan from public.priority_plans where id = p_plan_id and household_id = p_household_id for update;
  if not found then raise exception 'Plan introuvable.'; end if;
  if v_plan.status = p_status then return; end if;
  if v_plan.status = 'archived' then raise exception 'Un plan archivé ne peut pas être réactivé.'; end if;
  v_action := case p_status when 'active' then 'activated' when 'paused' then 'paused' else 'archived' end;
  update public.priority_plans set status = p_status, updated_by = v_actor_id, updated_at = now()
  where id = p_plan_id and household_id = p_household_id;
  insert into public.priority_plan_history(household_id, plan_id, action, changes, actor_id)
  values (p_household_id, p_plan_id, v_action, jsonb_build_object('from_status', v_plan.status, 'to_status', p_status), v_actor_id);
end;
$$;

create or replace function public.add_priority_plan_item(
  p_household_id uuid,
  p_plan_id uuid,
  p_shopping_item_id uuid default null,
  p_budget_goal_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_plan public.priority_plans%rowtype;
  v_item_id uuid;
  v_rank integer;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  select * into v_plan from public.priority_plans where id = p_plan_id and household_id = p_household_id for update;
  if not found then raise exception 'Plan introuvable.'; end if;
  if v_plan.status = 'archived' then raise exception 'Un plan archivé ne peut pas être modifié.'; end if;
  perform public.assert_priority_plan_source(p_household_id, p_plan_id, p_shopping_item_id, p_budget_goal_id);
  select coalesce(max(rank), 0) + 1 into v_rank from public.priority_plan_items where plan_id = p_plan_id;
  insert into public.priority_plan_items(household_id, plan_id, rank, shopping_item_id, budget_goal_id, created_by, updated_by)
  values (p_household_id, p_plan_id, v_rank, p_shopping_item_id, p_budget_goal_id, v_actor_id, v_actor_id)
  returning id into v_item_id;
  update public.priority_plans set updated_by = v_actor_id, updated_at = now() where id = p_plan_id;
  insert into public.priority_plan_history(household_id, plan_id, action, changes, actor_id)
  values (p_household_id, p_plan_id, 'item_added', jsonb_build_object('item_id', v_item_id, 'shopping_item_id', p_shopping_item_id, 'budget_goal_id', p_budget_goal_id, 'rank', v_rank), v_actor_id);
  return v_item_id;
end;
$$;

create or replace function public.remove_priority_plan_item(
  p_household_id uuid,
  p_plan_id uuid,
  p_item_id uuid
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_plan public.priority_plans%rowtype;
  v_item public.priority_plan_items%rowtype;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  select * into v_plan from public.priority_plans where id = p_plan_id and household_id = p_household_id for update;
  if not found then raise exception 'Plan introuvable.'; end if;
  if v_plan.status = 'archived' then raise exception 'Un plan archivé ne peut pas être modifié.'; end if;
  select * into v_item from public.priority_plan_items where id = p_item_id and plan_id = p_plan_id and household_id = p_household_id for update;
  if not found then raise exception 'Priorité introuvable.'; end if;
  delete from public.priority_plan_items where id = p_item_id and plan_id = p_plan_id;
  update public.priority_plan_items set rank = rank + 1000000 where plan_id = p_plan_id and rank > v_item.rank;
  update public.priority_plan_items set rank = rank - 1000001, updated_by = v_actor_id, updated_at = now() where plan_id = p_plan_id and rank > 1000000;
  update public.priority_plans set updated_by = v_actor_id, updated_at = now() where id = p_plan_id;
  insert into public.priority_plan_history(household_id, plan_id, action, changes, actor_id)
  values (p_household_id, p_plan_id, 'item_removed', jsonb_build_object('item_id', p_item_id, 'shopping_item_id', v_item.shopping_item_id, 'budget_goal_id', v_item.budget_goal_id), v_actor_id);
end;
$$;

create or replace function public.reorder_priority_plan_items(
  p_household_id uuid,
  p_plan_id uuid,
  p_item_ids uuid[]
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_plan public.priority_plans%rowtype;
  v_count integer;
  v_index integer;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then raise exception 'Accès non autorisé au foyer.'; end if;
  select * into v_plan from public.priority_plans where id = p_plan_id and household_id = p_household_id for update;
  if not found then raise exception 'Plan introuvable.'; end if;
  if v_plan.status = 'archived' then raise exception 'Un plan archivé ne peut pas être modifié.'; end if;
  if cardinality(p_item_ids) is null then p_item_ids := '{}'::uuid[]; end if;
  if cardinality(p_item_ids) <> cardinality(array(select distinct unnest(p_item_ids))) then raise exception 'Chaque priorité ne peut apparaître qu''une seule fois.'; end if;
  select count(*) into v_count from public.priority_plan_items where plan_id = p_plan_id and household_id = p_household_id;
  if v_count <> cardinality(p_item_ids) or v_count <> (select count(*) from public.priority_plan_items where plan_id = p_plan_id and id = any(p_item_ids)) then
    raise exception 'L''ordre transmis ne correspond pas aux priorités du plan.';
  end if;
  update public.priority_plan_items set rank = rank + 1000000 where plan_id = p_plan_id;
  for v_index in 1..v_count loop
    update public.priority_plan_items set rank = v_index, updated_by = v_actor_id, updated_at = now()
    where id = p_item_ids[v_index] and plan_id = p_plan_id;
  end loop;
  update public.priority_plans set updated_by = v_actor_id, updated_at = now() where id = p_plan_id;
  insert into public.priority_plan_history(household_id, plan_id, action, changes, actor_id)
  values (p_household_id, p_plan_id, 'items_reordered', jsonb_build_object('item_ids', p_item_ids), v_actor_id);
end;
$$;

revoke all on function public.assert_priority_plan_source(uuid, uuid, uuid, uuid) from public;
revoke all on function public.create_priority_plan(uuid, text, numeric, text) from public;
revoke all on function public.update_priority_plan(uuid, uuid, text, numeric, text) from public;
revoke all on function public.set_priority_plan_status(uuid, uuid, text) from public;
revoke all on function public.add_priority_plan_item(uuid, uuid, uuid, uuid) from public;
revoke all on function public.remove_priority_plan_item(uuid, uuid, uuid) from public;
revoke all on function public.reorder_priority_plan_items(uuid, uuid, uuid[]) from public;
grant execute on function public.create_priority_plan(uuid, text, numeric, text) to authenticated;
grant execute on function public.update_priority_plan(uuid, uuid, text, numeric, text) to authenticated;
grant execute on function public.set_priority_plan_status(uuid, uuid, text) to authenticated;
grant execute on function public.add_priority_plan_item(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.remove_priority_plan_item(uuid, uuid, uuid) to authenticated;
grant execute on function public.reorder_priority_plan_items(uuid, uuid, uuid[]) to authenticated;

commit;
