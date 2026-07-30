-- Noyau: données partagées et sécurité par foyer.
create extension if not exists pgcrypto;

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create or replace function public.is_household_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.household_members
    where household_id = target_household and user_id = auth.uid()
  );
$$;

create or replace function public.create_household(household_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare new_household_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.households(name) values (trim(household_name)) returning id into new_household_id;
  insert into public.household_members(household_id, user_id, role)
  values (new_household_id, auth.uid(), 'owner');
  return new_household_id;
end;
$$;

create table public.envelopes (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  color text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  unique (household_id, name)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  envelope_id uuid references public.envelopes(id),
  occurred_at date not null default current_date,
  amount numeric(14, 2) not null check (amount <> 0),
  kind text not null check (kind in ('expense', 'income', 'allocation', 'transfer', 'adjustment')),
  description text,
  created_by uuid not null references auth.users(id),
  voided_at timestamptz,
  created_at timestamptz not null default now()
);

create index transactions_household_occurred_idx on public.transactions(household_id, occurred_at desc);
create index transactions_envelope_occurred_idx on public.transactions(envelope_id, occurred_at desc);

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.envelopes enable row level security;
alter table public.transactions enable row level security;

create policy "members read household" on public.households for select using (public.is_household_member(id));
create policy "members read own membership" on public.household_members for select using (public.is_household_member(household_id));
create policy "members manage envelopes" on public.envelopes for all using (
  public.is_household_member(household_id)
) with check (
  public.is_household_member(household_id)
);
create policy "members manage transactions" on public.transactions for all using (
  public.is_household_member(household_id)
) with check (
  public.is_household_member(household_id)
);
