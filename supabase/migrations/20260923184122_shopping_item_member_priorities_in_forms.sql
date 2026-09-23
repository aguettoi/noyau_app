-- Shopping List: saisir les priorités de tous les membres depuis le même
-- formulaire, sans confondre l'acteur qui saisit avec le membre concerné.
begin;

create or replace function public.apply_shopping_item_member_priorities(
  p_household_id uuid,
  p_item_id uuid,
  p_member_priorities jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_item public.shopping_items%rowtype;
  v_entry jsonb;
  v_member_user_id uuid;
  v_priority integer;
  v_previous_priority integer;
begin
  if v_actor_id is null
     or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;
  if jsonb_typeof(coalesce(p_member_priorities, '[]'::jsonb)) <> 'array' then
    raise exception 'Les priorités membres doivent être une liste.';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_member_priorities, '[]'::jsonb)) entry
    group by entry ->> 'member_user_id'
    having count(*) > 1
  ) then
    raise exception 'Un membre ne peut apparaître qu''une fois dans les priorités.';
  end if;

  select * into v_item
  from public.shopping_items
  where id = p_item_id and household_id = p_household_id
  for update;
  if not found then raise exception 'Article introuvable.'; end if;
  if v_item.status in ('purchased', 'archived') then
    raise exception 'Cet article ne peut plus être priorisé.';
  end if;

  for v_entry in
    select value from jsonb_array_elements(coalesce(p_member_priorities, '[]'::jsonb))
  loop
    if jsonb_typeof(v_entry) <> 'object'
       or nullif(trim(v_entry ->> 'member_user_id'), '') is null then
      raise exception 'Une priorité membre est invalide.';
    end if;
    begin
      v_member_user_id := (v_entry ->> 'member_user_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Le membre sélectionné est invalide.';
    end;

    if not exists (
      select 1 from public.household_members
      where household_id = p_household_id and user_id = v_member_user_id
    ) then
      raise exception 'Le membre sélectionné n''appartient pas au foyer.';
    end if;

    if v_entry -> 'priority' is null or v_entry -> 'priority' = 'null'::jsonb then
      v_priority := null;
    else
      begin
        v_priority := (v_entry ->> 'priority')::integer;
      exception when invalid_text_representation then
        raise exception 'La priorité doit être comprise entre 0 et 3.';
      end;
      if v_priority not between 0 and 3 then
        raise exception 'La priorité doit être comprise entre 0 et 3.';
      end if;
    end if;

    select priority into v_previous_priority
    from public.shopping_item_member_priorities
    where shopping_item_id = p_item_id and member_user_id = v_member_user_id;

    if v_priority is null then
      if found then
        delete from public.shopping_item_member_priorities
        where shopping_item_id = p_item_id and member_user_id = v_member_user_id;
        insert into public.shopping_item_history(
          household_id, shopping_item_id, action, changes, actor_id
        ) values (
          p_household_id, p_item_id, 'member_priority_cleared',
          jsonb_build_object('member_user_id', v_member_user_id, 'before_priority', v_previous_priority),
          v_actor_id
        );
      end if;
    elsif not found or v_previous_priority is distinct from v_priority then
      insert into public.shopping_item_member_priorities(
        shopping_item_id, household_id, member_user_id, priority, created_by, updated_by
      ) values (
        p_item_id, p_household_id, v_member_user_id, v_priority, v_actor_id, v_actor_id
      ) on conflict (shopping_item_id, member_user_id) do update set
        priority = excluded.priority,
        updated_by = v_actor_id,
        updated_at = now();
      insert into public.shopping_item_history(
        household_id, shopping_item_id, action, changes, actor_id
      ) values (
        p_household_id, p_item_id, 'member_priority_set',
        jsonb_build_object(
          'member_user_id', v_member_user_id,
          'before_priority', v_previous_priority,
          'priority', v_priority
        ),
        v_actor_id
      );
    end if;
  end loop;
end;
$$;

create or replace function public.create_shopping_item_with_member_priorities(
  p_household_id uuid,
  p_label text,
  p_estimated_amount numeric default null,
  p_notes text default null,
  p_desired_date date default null,
  p_envelope_id uuid default null,
  p_budget_goal_id uuid default null,
  p_final_priority integer default null,
  p_member_priorities jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_item_id uuid;
begin
  v_item_id := public.create_shopping_item(
    p_household_id, p_label, p_estimated_amount, p_notes, p_desired_date,
    p_envelope_id, p_budget_goal_id, p_final_priority
  );
  perform public.apply_shopping_item_member_priorities(
    p_household_id, v_item_id, p_member_priorities
  );
  return v_item_id;
end;
$$;

create or replace function public.update_shopping_item_with_member_priorities(
  p_household_id uuid,
  p_item_id uuid,
  p_label text,
  p_estimated_amount numeric default null,
  p_notes text default null,
  p_desired_date date default null,
  p_envelope_id uuid default null,
  p_budget_goal_id uuid default null,
  p_final_priority integer default null,
  p_member_priorities jsonb default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.update_shopping_item(
    p_household_id, p_item_id, p_label, p_estimated_amount, p_notes,
    p_desired_date, p_envelope_id, p_budget_goal_id, p_final_priority
  );
  perform public.apply_shopping_item_member_priorities(
    p_household_id, p_item_id, p_member_priorities
  );
end;
$$;

revoke all on function public.apply_shopping_item_member_priorities(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.create_shopping_item_with_member_priorities(uuid, text, numeric, text, date, uuid, uuid, integer, jsonb) from public, anon;
revoke all on function public.update_shopping_item_with_member_priorities(uuid, uuid, text, numeric, text, date, uuid, uuid, integer, jsonb) from public, anon;
grant execute on function public.create_shopping_item_with_member_priorities(uuid, text, numeric, text, date, uuid, uuid, integer, jsonb) to authenticated;
grant execute on function public.update_shopping_item_with_member_priorities(uuid, uuid, text, numeric, text, date, uuid, uuid, integer, jsonb) to authenticated;

commit;
