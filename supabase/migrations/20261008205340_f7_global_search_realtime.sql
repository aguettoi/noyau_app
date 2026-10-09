-- F7 global search is a household-scoped read model. It never writes or
-- duplicates domain data. Security invoker preserves every table's RLS.
create or replace function public.search_household_global(
  p_household_id uuid,
  p_query text,
  p_limit integer default 50,
  p_offset integer default 0
) returns table(
  result_type text,
  source_id uuid,
  title text,
  subtitle text,
  occurred_on date,
  amount numeric
) language plpgsql security invoker set search_path=public as $$
declare v_query text := '%' || lower(btrim(coalesce(p_query,''))) || '%';
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if length(btrim(coalesce(p_query,''))) < 2 then return; end if;

  return query
  select * from (
    select 'financial_event', f.id, f.description,
      f.event_type || coalesce(' — ' || f.notes,''), f.occurred_at::date,
      null::numeric
    from public.financial_events f
    where f.household_id=p_household_id
      and lower(f.description || ' ' || coalesce(f.notes,'') || ' ' || f.event_type) like v_query
    union all
    select 'account',a.id,a.name,a.kind,null::date,null::numeric
    from public.accounts a where a.household_id=p_household_id and a.archived_at is null
      and lower(a.name || ' ' || a.kind) like v_query
    union all
    select 'envelope',e.id,e.name,coalesce(e.notes,''),null::date,null::numeric
    from public.envelopes e where e.household_id=p_household_id and e.archived_at is null
      and lower(e.name || ' ' || coalesce(e.notes,'')) like v_query
    union all
    select case when o.obligation_kind='debt' then 'obligation' else 'receivable' end,
      o.id,o.description,coalesce(o.counterparty_name,''),o.due_at::date,o.initial_amount
    from public.obligations o where o.household_id=p_household_id
      and lower(o.description || ' ' || coalesce(o.counterparty_name,'')) like v_query
    union all
    select 'compensation',c.id,c.reason,
      c.status || ' — ' || c.remaining_amount::text || ' MAD',c.created_at::date,c.remaining_amount
    from public.member_compensation_balances c where c.household_id=p_household_id
      and lower(c.reason || ' ' || c.status) like v_query
    union all
    select 'goal',g.id,g.name,coalesce(g.notes,''),g.target_date,g.target_amount
    from public.budget_goals g where g.household_id=p_household_id
      and lower(g.name || ' ' || coalesce(g.notes,'')) like v_query
    union all
    select 'shopping',s.id,s.label,coalesce(s.notes,''),s.desired_date,s.estimated_amount
    from public.shopping_items s where s.household_id=p_household_id and s.archived_at is null
      and lower(s.label || ' ' || coalesce(s.notes,'')) like v_query
    union all
    select 'priority',p.id,p.name,coalesce(p.notes,''),null::date,p.monthly_capacity
    from public.priority_plans p where p.household_id=p_household_id
      and lower(p.name || ' ' || coalesce(p.notes,'')) like v_query
    union all
    select 'task',t.id,t.title,coalesce(t.description,''),t.due_date,null::numeric
    from public.household_tasks t where t.household_id=p_household_id
      and lower(t.title || ' ' || coalesce(t.description,'')) like v_query
    union all
    select 'asset',w.id,w.label,w.asset_type,w.acquisition_date,w.acquisition_value
    from public.wealth_assets w where w.household_id=p_household_id
      and lower(w.label || ' ' || w.asset_type) like v_query
  ) results
  order by occurred_on desc nulls last,title
  limit least(greatest(p_limit,1),100) offset greatest(p_offset,0);
end $$;

revoke all on function public.search_household_global(uuid,text,integer,integer)
  from public,anon;
grant execute on function public.search_household_global(uuid,text,integer,integer)
  to authenticated;

-- Realtime only carries invalidation signals. Canonical providers reload from
-- their existing read models after an event.
do $$
declare t text;
begin
  foreach t in array array[
    'accounts','envelopes','financial_events','obligations',
    'member_compensations','budget_goals','shopping_items','priority_plans',
    'household_tasks','wealth_assets'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename=t
    ) then
      execute format('alter publication supabase_realtime add table public.%I',t);
    end if;
  end loop;
end $$;
