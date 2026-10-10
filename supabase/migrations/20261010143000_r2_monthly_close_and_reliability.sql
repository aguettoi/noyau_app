-- R2: guided monthly close and configurable envelope/account targets.
begin;

create table public.monthly_close_periods (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  month_start date not null check (month_start = date_trunc('month', month_start)::date),
  status text not null default 'open' check (status in ('open','closed','reopened')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (household_id, month_start),
  unique (id, household_id)
);

create table public.monthly_close_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  period_id uuid not null,
  event_kind text not null check (event_kind in ('opened','closed','reopened','warning_override')),
  reason text,
  snapshot jsonb not null default '{}'::jsonb,
  idempotency_key uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (household_id, idempotency_key),
  foreign key (period_id, household_id) references public.monthly_close_periods(id, household_id)
);

create table public.monthly_envelope_account_targets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  month_start date not null check (month_start = date_trunc('month', month_start)::date),
  envelope_id uuid not null,
  account_id uuid not null,
  target_amount numeric(14,2) not null check (target_amount >= 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (household_id, month_start, envelope_id, account_id),
  foreign key (envelope_id, household_id) references public.envelopes(id, household_id),
  foreign key (account_id, household_id) references public.accounts(id, household_id)
);

create index monthly_close_periods_household_month_idx on public.monthly_close_periods(household_id, month_start desc);
create index monthly_close_events_period_idx on public.monthly_close_events(period_id, created_at);
create index monthly_targets_month_idx on public.monthly_envelope_account_targets(household_id, month_start);

alter table public.monthly_close_periods enable row level security;
alter table public.monthly_close_events enable row level security;
alter table public.monthly_envelope_account_targets enable row level security;
revoke all on public.monthly_close_periods, public.monthly_close_events, public.monthly_envelope_account_targets from public, anon;
grant select on public.monthly_close_periods, public.monthly_close_events, public.monthly_envelope_account_targets to authenticated;
create policy monthly_close_periods_read on public.monthly_close_periods for select to authenticated using (public.is_household_member(household_id));
create policy monthly_close_events_read on public.monthly_close_events for select to authenticated using (public.is_household_member(household_id));
create policy monthly_targets_read on public.monthly_envelope_account_targets for select to authenticated using (public.is_household_member(household_id));

create or replace function public.monthly_close_snapshot(p_household_id uuid, p_month_start date)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_end date:=p_month_start+interval '1 month'; v_open_reconciliations int; v_missing_cash int; v_missing_receipts int; v_compensations int;
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 if p_month_start<>date_trunc('month',p_month_start)::date then raise exception 'Invalid month'; end if;
 select count(*) into v_open_reconciliations from public.account_reconciliation_cases where household_id=p_household_id and status in ('open','partially_resolved','explained_pending');
 select count(*) into v_missing_cash from public.accounts a where a.household_id=p_household_id and a.kind='cash' and a.archived_at is null and not exists(select 1 from public.account_balance_observations o where o.account_id=a.id and o.observed_at>=p_month_start and o.observed_at<v_end);
 select count(*) into v_missing_receipts from public.financial_events e where e.household_id=p_household_id and e.event_type in ('cash_expense','debt_expense') and e.occurred_at>=p_month_start and e.occurred_at<v_end and not exists(select 1 from public.financial_event_attachments a where a.financial_event_id=e.id and a.deleted_at is null);
 select count(*) into v_compensations from public.member_compensation_balances c where c.household_id=p_household_id and c.remaining_amount>0;
 return jsonb_build_object('open_reconciliations',v_open_reconciliations,'missing_cash_inventories',v_missing_cash,'missing_receipts',v_missing_receipts,'open_compensations',v_compensations,'hard_blockers',v_open_reconciliations+v_missing_cash,'warnings',v_missing_receipts+v_compensations);
end $$;

create or replace function public.close_monthly_period(p_household_id uuid,p_month_start date,p_override_warnings boolean,p_reason text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_period uuid; v_snapshot jsonb; v_role text;
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 select role into v_role from public.household_members where household_id=p_household_id and user_id=auth.uid();
 v_snapshot:=public.monthly_close_snapshot(p_household_id,p_month_start);
 if (v_snapshot->>'hard_blockers')::int>0 then raise exception 'Monthly close has hard blockers'; end if;
 if (v_snapshot->>'warnings')::int>0 and not p_override_warnings then raise exception 'Monthly close has warnings'; end if;
 if p_override_warnings and ((v_role<>'owner') or nullif(trim(p_reason),'') is null) then raise exception 'Owner reason required for warning override'; end if;
 insert into public.monthly_close_periods(household_id,month_start,status,created_by) values(p_household_id,p_month_start,'closed',auth.uid())
 on conflict(household_id,month_start) do update set status='closed' returning id into v_period;
 insert into public.monthly_close_events(household_id,period_id,event_kind,reason,snapshot,idempotency_key,created_by)
 values(p_household_id,v_period,case when p_override_warnings then 'warning_override' else 'closed' end,nullif(trim(p_reason),''),v_snapshot,p_idempotency_key,auth.uid()) on conflict(household_id,idempotency_key) do nothing;
 return v_period;
end $$;

create or replace function public.reopen_monthly_period(p_period_id uuid,p_reason text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_period public.monthly_close_periods%rowtype;
begin
 select * into v_period from public.monthly_close_periods where id=p_period_id for update;
 if auth.uid() is null or v_period.id is null or not exists(select 1 from public.household_members where household_id=v_period.household_id and user_id=auth.uid() and role='owner') then raise exception 'Owner access denied'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Reopen reason required'; end if;
 update public.monthly_close_periods set status='reopened' where id=v_period.id;
 insert into public.monthly_close_events(household_id,period_id,event_kind,reason,idempotency_key,created_by) values(v_period.household_id,v_period.id,'reopened',trim(p_reason),p_idempotency_key,auth.uid()) on conflict(household_id,idempotency_key) do nothing;
 return v_period.id;
end $$;

revoke all on function public.monthly_close_snapshot(uuid,date),public.close_monthly_period(uuid,date,boolean,text,uuid),public.reopen_monthly_period(uuid,text,uuid) from public,anon;
grant execute on function public.monthly_close_snapshot(uuid,date),public.close_monthly_period(uuid,date,boolean,text,uuid),public.reopen_monthly_period(uuid,text,uuid) to authenticated;
commit;
