-- R2 hardening: double-close resistance and audited target configuration.
begin;
create table public.monthly_envelope_account_target_events (
 id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households(id) on delete cascade,
 month_start date not null, envelope_id uuid not null, account_id uuid not null,
 target_amount numeric(14,2) not null check(target_amount>=0), idempotency_key uuid not null,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(household_id,idempotency_key), foreign key(envelope_id,household_id) references public.envelopes(id,household_id),
 foreign key(account_id,household_id) references public.accounts(id,household_id));
alter table public.monthly_envelope_account_target_events enable row level security;
revoke all on public.monthly_envelope_account_target_events from public,anon;
grant select on public.monthly_envelope_account_target_events to authenticated;
create policy monthly_target_events_read on public.monthly_envelope_account_target_events for select to authenticated using(public.is_household_member(household_id));

create or replace function public.set_monthly_envelope_account_target(p_household_id uuid,p_month_start date,p_envelope_id uuid,p_account_id uuid,p_target_amount numeric,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 if p_month_start<>date_trunc('month',p_month_start)::date or p_target_amount<0 then raise exception 'Invalid target'; end if;
 if exists(select 1 from public.monthly_close_periods where household_id=p_household_id and month_start=p_month_start and status='closed') then raise exception 'Closed month targets are immutable'; end if;
 insert into public.monthly_envelope_account_target_events(household_id,month_start,envelope_id,account_id,target_amount,idempotency_key,created_by)
 values(p_household_id,p_month_start,p_envelope_id,p_account_id,p_target_amount,p_idempotency_key,auth.uid()) on conflict(household_id,idempotency_key) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.monthly_envelope_account_target_events where household_id=p_household_id and idempotency_key=p_idempotency_key; return v_id; end if;
 insert into public.monthly_envelope_account_targets(household_id,month_start,envelope_id,account_id,target_amount,created_by)
 values(p_household_id,p_month_start,p_envelope_id,p_account_id,p_target_amount,auth.uid()) on conflict(household_id,month_start,envelope_id,account_id) do update set target_amount=excluded.target_amount,created_by=excluded.created_by,created_at=now();
 return v_id;
end $$;

create or replace function public.close_monthly_period(p_household_id uuid,p_month_start date,p_override_warnings boolean,p_reason text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_period public.monthly_close_periods%rowtype; v_snapshot jsonb; v_role text;
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 select * into v_period from public.monthly_close_periods where household_id=p_household_id and month_start=p_month_start for update;
 if v_period.status='closed' then return v_period.id; end if;
 select role into v_role from public.household_members where household_id=p_household_id and user_id=auth.uid();
 v_snapshot:=public.monthly_close_snapshot(p_household_id,p_month_start);
 if (v_snapshot->>'hard_blockers')::int>0 then raise exception 'Monthly close has hard blockers'; end if;
 if (v_snapshot->>'warnings')::int>0 and not p_override_warnings then raise exception 'Monthly close has warnings'; end if;
 if p_override_warnings and (v_role<>'owner' or nullif(trim(p_reason),'') is null) then raise exception 'Owner reason required for warning override'; end if;
 if v_period.id is null then insert into public.monthly_close_periods(household_id,month_start,status,created_by) values(p_household_id,p_month_start,'closed',auth.uid()) returning * into v_period;
 else update public.monthly_close_periods set status='closed' where id=v_period.id; end if;
 insert into public.monthly_close_events(household_id,period_id,event_kind,reason,snapshot,idempotency_key,created_by)
 values(p_household_id,v_period.id,case when p_override_warnings then 'warning_override' else 'closed' end,nullif(trim(p_reason),''),v_snapshot,p_idempotency_key,auth.uid()) on conflict(household_id,idempotency_key) do nothing;
 return v_period.id;
end $$;
revoke all on function public.set_monthly_envelope_account_target(uuid,date,uuid,uuid,numeric,uuid) from public,anon;
grant execute on function public.set_monthly_envelope_account_target(uuid,date,uuid,uuid,numeric,uuid) to authenticated;
commit;
