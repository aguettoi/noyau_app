begin;

create table public.home_profiles (
  asset_id uuid primary key,
  household_id uuid not null,
  property_type text not null default 'primary_residence',
  financing_id uuid,
  down_payment numeric(14,2) check (down_payment is null or down_payment >= 0),
  acquisition_fees numeric(14,2) check (acquisition_fees is null or acquisition_fees >= 0),
  status text not null default 'active' check (status in ('planned','active','sold','archived')),
  note text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete cascade,
  foreign key (financing_id,household_id) references public.financing_profiles(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict
);

create table public.home_benefits (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  asset_id uuid not null,
  benefit_type text not null check (benefit_type in ('acquisition_aid','tax_saving','employer_contribution','other')),
  recognition text not null check (recognition in ('projected','cash_received','liability_reduction')),
  amount numeric(14,2) not null check (amount >= 0),
  period_start date,
  period_end date,
  effective_date date,
  rate numeric(9,6) check (rate is null or rate >= 0),
  eligible_base numeric(14,2) check (eligible_base is null or eligible_base >= 0),
  ceiling_amount numeric(14,2) check (ceiling_amount is null or ceiling_amount >= 0),
  financial_event_id uuid,
  note text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (financial_event_id),
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete restrict,
  foreign key (financial_event_id,household_id) references public.financial_events(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict,
  check ((recognition='projected' and financial_event_id is null) or (recognition<>'projected' and financial_event_id is not null))
);

create table public.asset_expense_links (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  asset_id uuid not null,
  financial_event_id uuid not null,
  analytic_category text not null,
  note text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (financial_event_id,asset_id),
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete restrict,
  foreign key (financial_event_id,household_id) references public.financial_events(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict
);

create table public.vehicle_profiles (
  asset_id uuid primary key,
  household_id uuid not null,
  make text,
  model text,
  model_year integer check (model_year is null or model_year between 1886 and 2200),
  financing_id uuid,
  status text not null default 'active' check (status in ('planned','active','sold','archived')),
  note text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete cascade,
  foreign key (financing_id,household_id) references public.financing_profiles(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict
);

create table public.vehicle_mileage_readings (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  asset_id uuid not null,
  reading_date date not null,
  odometer_km integer not null check (odometer_km >= 0),
  note text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (asset_id,reading_date,odometer_km),
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete restrict,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict
);

create table public.vehicle_cost_plans (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  asset_id uuid not null,
  category text not null check (category in ('financing','insurance','tax','maintenance','oil_change','repair','fuel','toll','parking','other')),
  label text not null,
  expected_amount numeric(14,2) not null check (expected_amount >= 0),
  due_date date not null,
  recurrence_months integer check (recurrence_months is null or recurrence_months > 0),
  status text not null default 'planned' check (status in ('planned','completed','cancelled')),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  foreign key (asset_id,household_id) references public.wealth_assets(id,household_id) on delete cascade,
  foreign key (household_id,created_by) references public.household_members(household_id,user_id) on delete restrict
);

create index home_profiles_household_idx on public.home_profiles(household_id,status);
create index home_benefits_asset_idx on public.home_benefits(asset_id,recognition,effective_date);
create index asset_expense_links_asset_idx on public.asset_expense_links(asset_id,created_at desc);
create index vehicle_profiles_household_idx on public.vehicle_profiles(household_id,status);
create index vehicle_mileage_latest_idx on public.vehicle_mileage_readings(asset_id,reading_date desc,created_at desc);
create index vehicle_cost_plans_due_idx on public.vehicle_cost_plans(asset_id,due_date,status);

alter table public.home_profiles enable row level security;
alter table public.home_benefits enable row level security;
alter table public.asset_expense_links enable row level security;
alter table public.vehicle_profiles enable row level security;
alter table public.vehicle_mileage_readings enable row level security;
alter table public.vehicle_cost_plans enable row level security;

create policy home_profiles_member_all on public.home_profiles for all to authenticated
 using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy home_benefits_member_read on public.home_benefits for select to authenticated
 using (public.is_household_member(household_id));
create policy home_benefits_member_insert on public.home_benefits for insert to authenticated
 with check (public.is_household_member(household_id) and created_by=(select auth.uid()));
create policy asset_expense_links_member_read on public.asset_expense_links for select to authenticated
 using (public.is_household_member(household_id));
create policy asset_expense_links_member_insert on public.asset_expense_links for insert to authenticated
 with check (public.is_household_member(household_id) and created_by=(select auth.uid()));
create policy vehicle_profiles_member_all on public.vehicle_profiles for all to authenticated
 using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy vehicle_mileage_member_read on public.vehicle_mileage_readings for select to authenticated
 using (public.is_household_member(household_id));
create policy vehicle_mileage_member_insert on public.vehicle_mileage_readings for insert to authenticated
 with check (public.is_household_member(household_id) and created_by=(select auth.uid()));
create policy vehicle_cost_plans_member_all on public.vehicle_cost_plans for all to authenticated
 using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));

create or replace function public.f5b_append_only() returns trigger
language plpgsql set search_path=public as $$ begin raise exception 'F5B history is append-only'; end $$;
create trigger home_benefits_append_only before update or delete on public.home_benefits for each row execute function public.f5b_append_only();
create trigger asset_expense_links_append_only before update or delete on public.asset_expense_links for each row execute function public.f5b_append_only();
create trigger vehicle_mileage_append_only before update or delete on public.vehicle_mileage_readings for each row execute function public.f5b_append_only();

create view public.asset_expense_overview with (security_invoker=true) as
select l.*,e.description,e.occurred_at,
       coalesce(abs(t.amount),0)::numeric(14,2) event_amount
from public.asset_expense_links l
join public.financial_events e on e.id=l.financial_event_id and e.household_id=l.household_id
left join lateral (
  select sum(amount) amount from public.financial_transactions
  where event_id=e.id and household_id=e.household_id
) t on true;

grant select,insert,update on public.home_profiles,public.vehicle_profiles,public.vehicle_cost_plans to authenticated;
grant select,insert on public.home_benefits,public.asset_expense_links,public.vehicle_mileage_readings to authenticated;
grant select on public.asset_expense_overview to authenticated;
revoke all on function public.f5b_append_only() from public,anon,authenticated;

commit;
