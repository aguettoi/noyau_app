-- L1: server-owned account privacy state. Existing accounts remain visible.
-- A request changes the effective mode only after every active holder consents.
create table public.account_privacy_settings (
  account_id uuid primary key references public.accounts(id) on delete cascade,
  household_id uuid not null references public.households(id) on delete cascade,
  visibility text not null check (visibility in ('visible', 'balance_hidden', 'private')),
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  unique (account_id, household_id),
  foreign key (account_id, household_id)
    references public.accounts(id, household_id) on delete cascade
);

create table public.account_privacy_requests (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  household_id uuid not null,
  requested_visibility text not null
    check (requested_visibility in ('visible', 'balance_hidden', 'private')),
  status text not null default 'pending'
    check (status in ('pending', 'applied', 'rejected', 'cancelled')),
  requested_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  foreign key (account_id, household_id)
    references public.accounts(id, household_id) on delete cascade
);
create unique index account_privacy_one_pending_request
  on public.account_privacy_requests(account_id) where status = 'pending';

create table public.account_privacy_consents (
  request_id uuid not null references public.account_privacy_requests(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  decision text not null check (decision in ('approve', 'reject')),
  decided_at timestamptz not null default now(),
  primary key (request_id, user_id)
);

create table public.account_privacy_audit (
  id bigint generated always as identity primary key,
  account_id uuid not null,
  household_id uuid not null,
  request_id uuid,
  actor_id uuid not null,
  action text not null,
  from_visibility text,
  to_visibility text,
  occurred_at timestamptz not null default now()
);

alter table public.account_privacy_settings enable row level security;
alter table public.account_privacy_requests enable row level security;
alter table public.account_privacy_consents enable row level security;
alter table public.account_privacy_audit enable row level security;

-- Direct writes are deliberately unavailable: only the audited RPCs may mutate.
revoke all on public.account_privacy_settings,
  public.account_privacy_requests, public.account_privacy_consents,
  public.account_privacy_audit from anon, authenticated;
revoke all on public.account_holders from anon;
revoke insert, update, delete on public.account_holders from authenticated;
drop policy if exists "members manage account holders" on public.account_holders;

create schema if not exists private;

create function private.account_is_holder(p_account_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1 from public.account_holders h
    join public.household_members m
      on m.household_id = h.household_id and m.user_id = h.user_id
    where h.account_id = p_account_id and h.user_id = p_user_id
      and m.inactive_at is null
  );
$$;

create function private.account_visibility(p_account_id uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select coalesce((select s.visibility from public.account_privacy_settings s
                   where s.account_id = p_account_id), 'visible');
$$;

create function private.can_discover_account(p_account_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1 from public.accounts a
    join public.household_members m on m.household_id = a.household_id
    where a.id = p_account_id and m.user_id = p_user_id
      and m.inactive_at is null and not a.is_system
      and (private.account_visibility(a.id) <> 'private'
           or private.account_is_holder(a.id, p_user_id))
  );
$$;

create function private.can_read_account_balance(p_account_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1 from public.accounts a
    join public.household_members m on m.household_id = a.household_id
    where a.id = p_account_id and m.user_id = p_user_id
      and m.inactive_at is null and not a.is_system
      and (private.account_visibility(a.id) = 'visible'
           or private.account_is_holder(a.id, p_user_id))
  );
$$;

revoke all on function private.account_is_holder(uuid,uuid),
  private.account_visibility(uuid), private.can_discover_account(uuid,uuid),
  private.can_read_account_balance(uuid,uuid) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.can_discover_account(uuid,uuid),
  private.can_read_account_balance(uuid,uuid) to authenticated;

-- RLS is row-granular. A hidden account's raw row contains opening_balance,
-- so a non-holder must use the sanitized metadata projection below instead.
create policy "l1 account raw balance boundary" on public.accounts
  as restrictive for select to authenticated
  using (private.can_read_account_balance(id, (select auth.uid())));

drop policy if exists "members read account holders" on public.account_holders;
create policy "l1 discoverable holders" on public.account_holders
  for select to authenticated
  using (private.can_discover_account(account_id, (select auth.uid())));

create function public.list_account_privacy_summaries(p_household_id uuid)
returns table (
  account_id uuid, household_id uuid, name text, kind text,
  currency_code text, ownership_type text, archived_at timestamptz,
  visibility text, can_read_balance boolean, holder_user_ids uuid[]
) language sql stable security definer set search_path = ''
as $$
  select a.id, a.household_id, a.name, a.kind, a.currency_code,
         a.ownership_type, a.archived_at,
         private.account_visibility(a.id),
         private.can_read_account_balance(a.id, auth.uid()),
         array(select h.user_id from public.account_holders h
               where h.account_id = a.id order by h.user_id)
  from public.accounts a
  where a.household_id = p_household_id
    and private.can_discover_account(a.id, auth.uid())
  order by a.created_at, a.id;
$$;
revoke all on function public.list_account_privacy_summaries(uuid) from public, anon;
grant execute on function public.list_account_privacy_summaries(uuid) to authenticated;

create function public.request_account_privacy_change(
  p_account_id uuid, p_visibility text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_account public.accounts%rowtype;
  v_request_id uuid;
  v_actor uuid := auth.uid();
begin
  if v_actor is null or p_visibility not in ('visible','balance_hidden','private') then
    raise exception 'Account privacy change denied';
  end if;
  select * into v_account from public.accounts where id=p_account_id for update;
  if not found or v_account.ownership_type = 'household'
     or not private.account_is_holder(p_account_id,v_actor) then
    raise exception 'Account privacy change denied';
  end if;
  if private.account_visibility(p_account_id) = p_visibility then
    raise exception 'Account already has the requested privacy mode';
  end if;
  insert into public.account_privacy_requests(
    account_id,household_id,requested_visibility,requested_by
  ) values (p_account_id,v_account.household_id,p_visibility,v_actor)
  returning id into v_request_id;
  insert into public.account_privacy_audit(
    account_id,household_id,request_id,actor_id,action,from_visibility,to_visibility
  ) values (p_account_id,v_account.household_id,v_request_id,v_actor,'requested',
            private.account_visibility(p_account_id),p_visibility);
  -- The requester consents explicitly by making the request.
  perform public.decide_account_privacy_change(v_request_id, 'approve');
  return v_request_id;
end;
$$;

create function public.decide_account_privacy_change(
  p_request_id uuid, p_decision text
) returns text language plpgsql security definer set search_path = ''
as $$
declare
  v_request public.account_privacy_requests%rowtype;
  v_actor uuid := auth.uid();
  v_from text;
begin
  if v_actor is null or p_decision not in ('approve','reject') then
    raise exception 'Account privacy decision denied';
  end if;
  select * into v_request from public.account_privacy_requests
    where id=p_request_id for update;
  if not found or v_request.status <> 'pending'
     or not private.account_is_holder(v_request.account_id,v_actor) then
    raise exception 'Account privacy decision denied';
  end if;
  insert into public.account_privacy_consents(request_id,user_id,decision)
    values (p_request_id,v_actor,p_decision)
    on conflict (request_id,user_id) do nothing;
  if not found then
    raise exception 'Account privacy decision already recorded';
  end if;
  insert into public.account_privacy_audit(
    account_id,household_id,request_id,actor_id,action,from_visibility,to_visibility
  ) values (v_request.account_id,v_request.household_id,p_request_id,v_actor,
            p_decision,private.account_visibility(v_request.account_id),
            v_request.requested_visibility);
  if p_decision = 'reject' then
    update public.account_privacy_requests set status='rejected',resolved_at=now()
      where id=p_request_id;
    return 'rejected';
  end if;
  if not exists (
    select 1 from public.account_holders h
    join public.household_members m on m.household_id=h.household_id
      and m.user_id=h.user_id and m.inactive_at is null
    where h.account_id=v_request.account_id
      and not exists (select 1 from public.account_privacy_consents c
        where c.request_id=p_request_id and c.user_id=h.user_id
          and c.decision='approve')
  ) then
    v_from := private.account_visibility(v_request.account_id);
    insert into public.account_privacy_settings(
      account_id,household_id,visibility,changed_by
    ) values (v_request.account_id,v_request.household_id,
              v_request.requested_visibility,v_actor)
    on conflict (account_id) do update set
      visibility=excluded.visibility,changed_by=excluded.changed_by,
      changed_at=now();
    update public.account_privacy_requests set status='applied',resolved_at=now()
      where id=p_request_id;
    insert into public.account_privacy_audit(
      account_id,household_id,request_id,actor_id,action,from_visibility,to_visibility
    ) values (v_request.account_id,v_request.household_id,p_request_id,v_actor,
              'applied',v_from,v_request.requested_visibility);
    return 'applied';
  end if;
  return 'pending';
end;
$$;
revoke all on function public.request_account_privacy_change(uuid,text),
  public.decide_account_privacy_change(uuid,text) from public, anon;
grant execute on function public.request_account_privacy_change(uuid,text),
  public.decide_account_privacy_change(uuid,text) to authenticated;
