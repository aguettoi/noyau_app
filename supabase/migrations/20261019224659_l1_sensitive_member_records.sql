-- Generic private-by-default personal records. No Cycle data is introduced.
create table public.sensitive_member_records (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  owner_user_id uuid not null,
  category text not null check (length(trim(category)) between 1 and 80),
  payload jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  foreign key (household_id,owner_user_id)
    references public.household_members(household_id,user_id) on delete restrict
);
create index sensitive_member_records_owner_idx
  on public.sensitive_member_records(household_id,owner_user_id,created_at desc);

create table public.sensitive_member_record_shares (
  record_id uuid not null references public.sensitive_member_records(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id),
  granted_by uuid not null references auth.users(id),
  granted_at timestamptz not null default now(),
  primary key(record_id,recipient_user_id)
);

create table public.sensitive_member_record_audit (
  id bigint generated always as identity primary key,
  record_id uuid not null,
  household_id uuid not null,
  owner_user_id uuid not null,
  actor_id uuid not null,
  action text not null,
  recipient_user_id uuid,
  occurred_at timestamptz not null default now()
);

alter table public.sensitive_member_records enable row level security;
alter table public.sensitive_member_record_shares enable row level security;
alter table public.sensitive_member_record_audit enable row level security;
revoke all on public.sensitive_member_records,
  public.sensitive_member_record_shares,
  public.sensitive_member_record_audit from anon,authenticated;
grant select,insert,update on public.sensitive_member_records to authenticated;
grant select on public.sensitive_member_record_shares,
  public.sensitive_member_record_audit to authenticated;

create policy "l1 personal records authorized readers"
  on public.sensitive_member_records for select to authenticated
  using (
    archived_at is null and exists (
      select 1 from public.household_members m
      where m.household_id=sensitive_member_records.household_id
        and m.user_id=(select auth.uid()) and m.inactive_at is null
    ) and (
      owner_user_id=(select auth.uid()) or exists (
        select 1 from public.sensitive_member_record_shares s
        where s.record_id=sensitive_member_records.id
          and s.recipient_user_id=(select auth.uid())
      )
    )
  );

create policy "l1 owner creates personal records"
  on public.sensitive_member_records for insert to authenticated
  with check (
    owner_user_id=(select auth.uid()) and created_by=(select auth.uid())
    and exists (select 1 from public.household_members m
      where m.household_id=household_id and m.user_id=(select auth.uid())
        and m.inactive_at is null)
  );

create policy "l1 owner updates personal records"
  on public.sensitive_member_records for update to authenticated
  using (owner_user_id=(select auth.uid()))
  with check (owner_user_id=(select auth.uid()) and created_by=(select auth.uid()));

create policy "l1 personal share participants read grant"
  on public.sensitive_member_record_shares for select to authenticated
  using (recipient_user_id=(select auth.uid()));

create policy "l1 personal owner reads audit"
  on public.sensitive_member_record_audit for select to authenticated
  using (owner_user_id=(select auth.uid()));

create function private.audit_sensitive_member_record()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op='UPDATE' and
     (new.household_id is distinct from old.household_id or
      new.owner_user_id is distinct from old.owner_user_id or
      new.created_by is distinct from old.created_by or
      new.created_at is distinct from old.created_at) then
    raise exception 'Personal record ownership is immutable';
  end if;
  if tg_op='UPDATE' then new.updated_at := now(); end if;
  insert into public.sensitive_member_record_audit(
    record_id,household_id,owner_user_id,actor_id,action
  ) values (new.id,new.household_id,new.owner_user_id,auth.uid(),
            case when tg_op='INSERT' then 'created'
                 when new.archived_at is not null and old.archived_at is null
                   then 'archived' else 'updated' end);
  return new;
end;
$$;
create trigger sensitive_member_record_audit_trigger
  before insert or update on public.sensitive_member_records
  for each row execute function private.audit_sensitive_member_record();
revoke all on function private.audit_sensitive_member_record() from public,anon,authenticated;

create function public.set_sensitive_member_record_share(
  p_record_id uuid,p_recipient_user_id uuid,p_share boolean
) returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_record public.sensitive_member_records%rowtype;
  v_actor uuid := auth.uid();
begin
  select * into v_record from public.sensitive_member_records
    where id=p_record_id for update;
  if v_actor is null or not found or v_record.owner_user_id<>v_actor
     or v_record.archived_at is not null
     or p_recipient_user_id=v_actor
     or not exists (select 1 from public.household_members m
       where m.household_id=v_record.household_id
         and m.user_id=p_recipient_user_id and m.inactive_at is null) then
    raise exception 'Personal record sharing denied';
  end if;
  if p_share then
    insert into public.sensitive_member_record_shares(
      record_id,recipient_user_id,granted_by
    ) values (p_record_id,p_recipient_user_id,v_actor)
    on conflict(record_id,recipient_user_id) do nothing;
  else
    delete from public.sensitive_member_record_shares
      where record_id=p_record_id and recipient_user_id=p_recipient_user_id;
  end if;
  insert into public.sensitive_member_record_audit(
    record_id,household_id,owner_user_id,actor_id,action,recipient_user_id
  ) values (p_record_id,v_record.household_id,v_actor,v_actor,
            case when p_share then 'shared' else 'revoked' end,
            p_recipient_user_id);
end;
$$;
revoke all on function public.set_sensitive_member_record_share(uuid,uuid,boolean)
  from public,anon;
grant execute on function public.set_sensitive_member_record_share(uuid,uuid,boolean)
  to authenticated;
