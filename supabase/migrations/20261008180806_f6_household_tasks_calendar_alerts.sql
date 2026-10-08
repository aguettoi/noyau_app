create table public.household_tasks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 160),
  description text,
  assignee_user_id uuid,
  due_date date,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'todo' check (status in ('todo','in_progress','completed','cancelled')),
  recurrence text not null default 'none' check (recurrence in ('none','daily','weekly','monthly','yearly')),
  source_module text,
  source_type text,
  source_id uuid,
  idempotency_key uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (household_id,idempotency_key),
  foreign key (household_id,assignee_user_id)
    references public.household_members(household_id,user_id)
);

create table public.household_task_occurrences (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  task_id uuid not null references public.household_tasks(id) on delete cascade,
  scheduled_date date,
  outcome text not null check (outcome in ('completed','cancelled')),
  note text,
  acted_by uuid not null references auth.users(id),
  acted_at timestamptz not null default now(),
  idempotency_key uuid not null,
  unique (task_id,idempotency_key)
);

create table public.user_alert_states (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  alert_key text not null,
  read_at timestamptz,
  dismissed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (household_id,user_id,alert_key),
  foreign key (household_id,user_id)
    references public.household_members(household_id,user_id)
);

create table public.notification_preferences (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('tasks','budget','finance','goals','home_auto')),
  in_app_enabled boolean not null default true,
  native_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (household_id,user_id,category),
  foreign key (household_id,user_id)
    references public.household_members(household_id,user_id)
);

alter table public.household_tasks enable row level security;
alter table public.household_task_occurrences enable row level security;
alter table public.user_alert_states enable row level security;
alter table public.notification_preferences enable row level security;

create policy household_tasks_read on public.household_tasks for select to authenticated
  using (public.is_household_member(household_id));
create policy household_tasks_create on public.household_tasks for insert to authenticated
  with check (public.is_household_member(household_id) and created_by=(select auth.uid()));
create policy household_task_occurrences_read on public.household_task_occurrences for select to authenticated
  using (public.is_household_member(household_id));
create policy user_alert_states_own on public.user_alert_states for all to authenticated
  using (user_id=(select auth.uid()) and public.is_household_member(household_id))
  with check (user_id=(select auth.uid()) and public.is_household_member(household_id));
create policy notification_preferences_own on public.notification_preferences for all to authenticated
  using (user_id=(select auth.uid()) and public.is_household_member(household_id))
  with check (user_id=(select auth.uid()) and public.is_household_member(household_id));

revoke all on public.household_tasks,public.household_task_occurrences,public.user_alert_states,public.notification_preferences from public,anon;
grant select,insert on public.household_tasks to authenticated;
grant select on public.household_task_occurrences to authenticated;
grant select,insert,update on public.user_alert_states,public.notification_preferences to authenticated;

create or replace function public.complete_household_task(
  p_task_id uuid,p_outcome text,p_note text,p_idempotency_key uuid
) returns public.household_tasks
language plpgsql security definer set search_path=public as $$
declare v_task public.household_tasks; v_next date;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_task from public.household_tasks where id=p_task_id for update;
  if v_task.id is null or not public.is_household_member(v_task.household_id) then
    raise exception 'Task access denied';
  end if;
  if p_outcome not in ('completed','cancelled') then raise exception 'Invalid outcome'; end if;
  insert into public.household_task_occurrences(
    household_id,task_id,scheduled_date,outcome,note,acted_by,idempotency_key
  ) values(v_task.household_id,v_task.id,v_task.due_date,p_outcome,nullif(trim(p_note),''),auth.uid(),p_idempotency_key)
  on conflict(task_id,idempotency_key) do nothing;
  if not found then return v_task; end if;
  if p_outcome='completed' and v_task.recurrence<>'none' then
    v_next:=case v_task.recurrence
      when 'daily' then coalesce(v_task.due_date,current_date)+1
      when 'weekly' then coalesce(v_task.due_date,current_date)+7
      when 'monthly' then (coalesce(v_task.due_date,current_date)+interval '1 month')::date
      when 'yearly' then (coalesce(v_task.due_date,current_date)+interval '1 year')::date
    end;
    update public.household_tasks set due_date=v_next,status='todo',completed_at=null,updated_at=now()
      where id=v_task.id returning * into v_task;
  else
    update public.household_tasks set status=case when p_outcome='completed' then 'completed' else 'cancelled' end,
      completed_at=case when p_outcome='completed' then now() else null end,updated_at=now()
      where id=v_task.id returning * into v_task;
  end if;
  return v_task;
end $$;

grant execute on function public.complete_household_task(uuid,text,text,uuid) to authenticated;
