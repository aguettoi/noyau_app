-- R2.1: a reopened period is stable under retries and repeated UI actions.
begin;

create or replace function public.reopen_monthly_period(
  p_period_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_period public.monthly_close_periods%rowtype;
begin
  select * into v_period
  from public.monthly_close_periods
  where id = p_period_id
  for update;

  if auth.uid() is null
     or v_period.id is null
     or not exists (
       select 1
       from public.household_members
       where household_id = v_period.household_id
         and user_id = auth.uid()
         and role = 'owner'
     ) then
    raise exception 'Owner access denied';
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'Reopen reason required';
  end if;

  -- A network retry or a repeated click after the first successful transition
  -- must not append a second business event.
  if v_period.status = 'reopened' then
    return v_period.id;
  end if;
  if v_period.status <> 'closed' then
    raise exception 'Only a closed month can be reopened';
  end if;

  update public.monthly_close_periods
  set status = 'reopened'
  where id = v_period.id;

  insert into public.monthly_close_events(
    household_id, period_id, event_kind, reason, idempotency_key, created_by
  ) values (
    v_period.household_id, v_period.id, 'reopened', trim(p_reason),
    p_idempotency_key, auth.uid()
  )
  on conflict(household_id, idempotency_key) do nothing;

  return v_period.id;
end $$;

revoke all on function public.reopen_monthly_period(uuid,text,uuid)
from public, anon;
grant execute on function public.reopen_monthly_period(uuid,text,uuid)
to authenticated;

commit;
