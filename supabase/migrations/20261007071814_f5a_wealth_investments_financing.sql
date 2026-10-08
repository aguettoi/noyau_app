begin;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='budget_goals_id_household_unique') then
    alter table public.budget_goals add constraint budget_goals_id_household_unique unique(id,household_id);
  end if;
end $$;

create table public.wealth_assets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  asset_type text not null check (asset_type in ('real_estate','vehicle','other')),
  label text not null check (char_length(trim(label)) between 1 and 160),
  ownership_type text not null default 'household'
    check (ownership_type in ('household','individual','shared')),
  acquisition_date date,
  acquisition_value numeric(14,2) check (acquisition_value is null or acquisition_value >= 0),
  status text not null default 'active' check (status in ('active','sold','archived')),
  goal_id uuid,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_by uuid not null,
  updated_at timestamptz not null default now(),
  unique (id, household_id),
  foreign key (household_id, created_by)
    references public.household_members(household_id,user_id) on delete restrict,
  foreign key (household_id, updated_by)
    references public.household_members(household_id,user_id) on delete restrict,
  foreign key (goal_id,household_id) references public.budget_goals(id,household_id) on delete restrict
);

create table public.wealth_asset_owners (
  household_id uuid not null,
  asset_id uuid not null,
  user_id uuid not null,
  ownership_share numeric(7,4) check (ownership_share is null or (ownership_share > 0 and ownership_share <= 1)),
  created_at timestamptz not null default now(),
  primary key (asset_id,user_id),
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete cascade,
  foreign key (household_id,user_id) references public.household_members(household_id,user_id) on delete restrict
);

create table public.wealth_asset_valuations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  asset_id uuid not null,
  estimated_value numeric(14,2) not null check (estimated_value >= 0),
  valued_on date not null,
  note text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (asset_id,valued_on,created_at),
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict
);

create table public.investment_products (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 160),
  product_type text not null default 'other'
    check (product_type in ('savings','fund','security','term_deposit','other')),
  backing_account_id uuid,
  owner_user_id uuid,
  goal_id uuid,
  currency_code text not null default 'MAD' check (currency_code ~ '^[A-Z]{3}$'),
  status text not null default 'active' check (status in ('active','closed','archived')),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id,household_id),
  foreign key (backing_account_id,household_id) references public.accounts(id,household_id) on delete restrict,
  foreign key (household_id,owner_user_id) references public.household_members(household_id,user_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict,
  foreign key (goal_id,household_id) references public.budget_goals(id,household_id) on delete restrict
);

create table public.investment_valuations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  investment_id uuid not null,
  estimated_value numeric(14,2) not null check (estimated_value >= 0),
  valued_on date not null,
  note text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  foreign key (investment_id,household_id) references public.investment_products(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict
);

create table public.investment_operations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  investment_id uuid not null,
  operation_type text not null check (operation_type in ('contribution','withdrawal','distribution','tax_withholding')),
  gross_amount numeric(14,2) not null check (gross_amount > 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0 and tax_amount <= gross_amount),
  occurred_on date not null,
  financial_event_id uuid not null,
  idempotency_key uuid not null,
  note text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (household_id,idempotency_key),
  unique (financial_event_id),
  foreign key (investment_id,household_id) references public.investment_products(id,household_id) on delete restrict,
  foreign key (financial_event_id,household_id) references public.financial_events(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict
);

create table public.financing_profiles (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 160),
  structure_type text not null check (structure_type in ('interest_loan','murabaha','fixed_cost','other')),
  obligation_id uuid not null,
  asset_id uuid,
  principal_initial numeric(14,2) not null check (principal_initial > 0),
  start_date date not null,
  duration_months integer not null check (duration_months > 0),
  periodicity_months integer not null default 1 check (periodicity_months > 0),
  annual_rate numeric(9,6) check (annual_rate is null or annual_rate >= 0),
  fixed_total_cost numeric(14,2) check (fixed_total_cost is null or fixed_total_cost >= 0),
  scheduled_payment numeric(14,2) check (scheduled_payment is null or scheduled_payment > 0),
  next_due_date date,
  status text not null default 'active' check (status in ('draft','active','completed','cancelled')),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (obligation_id),
  unique (id,household_id),
  foreign key (obligation_id,household_id) references public.obligations(id,household_id) on delete restrict,
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict,
  check ((structure_type='interest_loan' and annual_rate is not null) or structure_type<>'interest_loan')
);

create index wealth_assets_household_idx on public.wealth_assets(household_id,status);
create index wealth_asset_valuations_latest_idx on public.wealth_asset_valuations(asset_id,valued_on desc,created_at desc);
create index investment_products_household_idx on public.investment_products(household_id,status);
create index investment_valuations_latest_idx on public.investment_valuations(investment_id,valued_on desc,created_at desc);
create index investment_operations_history_idx on public.investment_operations(investment_id,occurred_on desc,created_at desc);
create index financing_profiles_household_idx on public.financing_profiles(household_id,status);

alter table public.wealth_assets enable row level security;
alter table public.wealth_asset_owners enable row level security;
alter table public.wealth_asset_valuations enable row level security;
alter table public.investment_products enable row level security;
alter table public.investment_valuations enable row level security;
alter table public.investment_operations enable row level security;
alter table public.financing_profiles enable row level security;

create policy wealth_assets_member_all on public.wealth_assets for all to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy wealth_asset_owners_member_all on public.wealth_asset_owners for all to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy wealth_asset_valuations_member_read on public.wealth_asset_valuations for select to authenticated
  using (public.is_household_member(household_id));
create policy wealth_asset_valuations_member_insert on public.wealth_asset_valuations for insert to authenticated
  with check (public.is_household_member(household_id) and created_by=auth.uid());
create policy investment_products_member_all on public.investment_products for all to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy investment_valuations_member_read on public.investment_valuations for select to authenticated
  using (public.is_household_member(household_id));
create policy investment_valuations_member_insert on public.investment_valuations for insert to authenticated
  with check (public.is_household_member(household_id) and created_by=auth.uid());
create policy investment_operations_member_read on public.investment_operations for select to authenticated
  using (public.is_household_member(household_id));
create policy investment_operations_member_insert on public.investment_operations for insert to authenticated
  with check (public.is_household_member(household_id) and created_by=auth.uid());
create policy financing_profiles_member_all on public.financing_profiles for all to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));

create or replace function public.f5a_append_only() returns trigger language plpgsql as $$
begin raise exception 'F5A history is append-only'; end $$;
create trigger wealth_asset_valuations_append_only before update or delete on public.wealth_asset_valuations
  for each row execute function public.f5a_append_only();
create trigger investment_valuations_append_only before update or delete on public.investment_valuations
  for each row execute function public.f5a_append_only();
create trigger investment_operations_append_only before update or delete on public.investment_operations
  for each row execute function public.f5a_append_only();

create view public.wealth_asset_current_values with (security_invoker=true) as
select a.*,v.estimated_value current_estimated_value,v.valued_on valuation_date
from public.wealth_assets a
left join lateral (
 select estimated_value,valued_on from public.wealth_asset_valuations
 where asset_id=a.id order by valued_on desc,created_at desc limit 1
) v on true;

create view public.investment_current_values with (security_invoker=true) as
select p.*,v.estimated_value current_estimated_value,v.valued_on valuation_date,
 coalesce(o.contributed,0)::numeric(14,2) capital_contributed,
 coalesce(o.withdrawn,0)::numeric(14,2) capital_withdrawn,
 coalesce(o.distributed,0)::numeric(14,2) distributions,
 coalesce(o.tax,0)::numeric(14,2) taxes
from public.investment_products p
left join lateral (
 select estimated_value,valued_on from public.investment_valuations
 where investment_id=p.id order by valued_on desc,created_at desc limit 1
) v on true
left join lateral (
 select sum(gross_amount) filter(where operation_type='contribution') contributed,
 sum(gross_amount) filter(where operation_type='withdrawal') withdrawn,
 sum(gross_amount) filter(where operation_type='distribution') distributed,
 sum(tax_amount) tax
 from public.investment_operations where investment_id=p.id
) o on true;

create view public.financing_overview with (security_invoker=true) as
select f.*,b.remaining_amount,b.status obligation_status
from public.financing_profiles f join public.obligation_balances b
 on b.obligation_id=f.obligation_id and b.household_id=f.household_id;

grant select,insert,update on public.wealth_assets,public.wealth_asset_owners,public.investment_products,public.financing_profiles to authenticated;
grant select,insert on public.wealth_asset_valuations,public.investment_valuations,public.investment_operations to authenticated;
grant select on public.wealth_asset_current_values,public.investment_current_values,public.financing_overview to authenticated;
revoke all on function public.f5a_append_only() from public,anon,authenticated;

commit;
