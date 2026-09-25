-- A PRIOS active plan is the one read-only household projection reference.
-- It remains planning metadata: this migration never writes financial ledgers.
begin;

create unique index priority_plans_one_active_per_household_idx
  on public.priority_plans(household_id)
  where status = 'active';

create or replace function public.activate_priority_plan(
  p_household_id uuid,
  p_plan_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_target public.priority_plans%rowtype;
  v_previous public.priority_plans%rowtype;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;

  -- Serialises competing activation intents for the same household before the
  -- partial unique index acts as the final integrity guard.
  perform pg_advisory_xact_lock(hashtextextended(p_household_id::text, 0));

  select * into v_target
  from public.priority_plans
  where id = p_plan_id and household_id = p_household_id
  for update;
  if not found then
    raise exception 'Plan introuvable.';
  end if;
  if v_target.status = 'archived' then
    raise exception 'Un plan archivé ne peut pas être activé.';
  end if;
  if v_target.status = 'active' then
    return;
  end if;

  for v_previous in
    select * from public.priority_plans
    where household_id = p_household_id
      and status = 'active'
      and id <> p_plan_id
    for update
  loop
    update public.priority_plans
    set status = 'planned', updated_by = v_actor_id, updated_at = now()
    where id = v_previous.id and household_id = p_household_id;
    insert into public.priority_plan_history(
      household_id, plan_id, action, changes, actor_id
    ) values (
      p_household_id,
      v_previous.id,
      'updated',
      jsonb_build_object(
        'from_status', 'active',
        'to_status', 'planned',
        'reason', 'replaced_as_projection_reference',
        'replacement_plan_id', p_plan_id
      ),
      v_actor_id
    );
  end loop;

  update public.priority_plans
  set status = 'active', updated_by = v_actor_id, updated_at = now()
  where id = p_plan_id and household_id = p_household_id;
  insert into public.priority_plan_history(
    household_id, plan_id, action, changes, actor_id
  ) values (
    p_household_id,
    p_plan_id,
    'activated',
    jsonb_build_object(
      'from_status', v_target.status,
      'to_status', 'active'
    ),
    v_actor_id
  );
end;
$$;

create or replace function public.set_priority_plan_status(
  p_household_id uuid,
  p_plan_id uuid,
  p_status text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_plan public.priority_plans%rowtype;
  v_action text;
begin
  if p_status = 'active' then
    perform public.activate_priority_plan(p_household_id, p_plan_id);
    return;
  end if;
  if v_actor_id is null or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;
  if p_status not in ('paused', 'archived') then
    raise exception 'Le statut demandé est invalide.';
  end if;
  select * into v_plan
  from public.priority_plans
  where id = p_plan_id and household_id = p_household_id
  for update;
  if not found then
    raise exception 'Plan introuvable.';
  end if;
  if v_plan.status = p_status then
    return;
  end if;
  if v_plan.status = 'archived' then
    raise exception 'Un plan archivé ne peut pas être réactivé.';
  end if;
  v_action := case p_status when 'paused' then 'paused' else 'archived' end;
  update public.priority_plans
  set status = p_status, updated_by = v_actor_id, updated_at = now()
  where id = p_plan_id and household_id = p_household_id;
  insert into public.priority_plan_history(
    household_id, plan_id, action, changes, actor_id
  ) values (
    p_household_id,
    p_plan_id,
    v_action,
    jsonb_build_object('from_status', v_plan.status, 'to_status', p_status),
    v_actor_id
  );
end;
$$;

revoke all on function public.activate_priority_plan(uuid, uuid) from public;
grant execute on function public.activate_priority_plan(uuid, uuid) to authenticated;

commit;
