begin;

create table public.recurring_financial_intentions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  economic_type text not null check (economic_type in ('income','expense','account_transfer')),
  label text not null check (length(trim(label)) between 1 and 160),
  expected_amount numeric(14,2) not null check (expected_amount > 0),
  currency_code text not null default 'MAD' check (length(currency_code)=3),
  frequency text not null check (frequency in ('weekly','monthly','yearly')),
  starts_on date not null,
  ends_on date,
  next_occurrence_on date not null,
  anchor_day integer not null check (anchor_day between 1 and 31),
  concerned_member_id uuid,
  source_account_id uuid references public.accounts(id) on delete restrict,
  destination_account_id uuid references public.accounts(id) on delete restrict,
  envelope_id uuid references public.envelopes(id) on delete restrict,
  certainty text not null default 'certain' check (certainty in ('certain','estimated')),
  status text not null default 'active' check (status in ('active','suspended','stopped')),
  source_kind text not null default 'manual' check (source_kind in ('manual','budget','financing','vehicle_cost','obligation','task','monthly_close')),
  source_id uuid,
  source_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(source_metadata)='object'),
  idempotency_key uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  stopped_at timestamptz,
  unique (household_id,idempotency_key),
  check (ends_on is null or ends_on >= starts_on),
  check (next_occurrence_on >= starts_on),
  check (economic_type <> 'account_transfer' or source_account_id is distinct from destination_account_id),
  foreign key (household_id,concerned_member_id) references public.household_members(household_id,user_id)
);

create table public.expected_financial_occurrences (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  intention_id uuid not null references public.recurring_financial_intentions(id) on delete restrict,
  expected_on date not null,
  economic_type text not null check (economic_type in ('income','expense','account_transfer')),
  label text not null,
  expected_amount numeric(14,2) not null check (expected_amount > 0),
  currency_code text not null check (length(currency_code)=3),
  concerned_member_id uuid,
  source_account_id uuid references public.accounts(id) on delete restrict,
  destination_account_id uuid references public.accounts(id) on delete restrict,
  envelope_id uuid references public.envelopes(id) on delete restrict,
  certainty text not null check (certainty in ('certain','estimated')),
  ignored_at timestamptz,
  ignored_by uuid references auth.users(id),
  ignore_reason text,
  created_at timestamptz not null default now(),
  unique (intention_id,expected_on),
  foreign key (household_id,concerned_member_id) references public.household_members(household_id,user_id),
  check ((ignored_at is null and ignored_by is null) or (ignored_at is not null and ignored_by is not null and length(trim(ignore_reason))>0))
);

create table public.expected_financial_occurrence_matches (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  occurrence_id uuid not null references public.expected_financial_occurrences(id) on delete restrict,
  financial_event_id uuid not null references public.financial_events(id) on delete restrict,
  matched_amount numeric(14,2) not null check (matched_amount > 0),
  decision text not null check (decision in ('proposed','confirmed','rejected')),
  score numeric(5,4) check (score is null or score between 0 and 1),
  reasons jsonb not null default '[]'::jsonb check (jsonb_typeof(reasons)='array'),
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  idempotency_key uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (occurrence_id,financial_event_id),
  unique (household_id,idempotency_key),
  check ((decision='proposed' and decided_at is null and decided_by is null) or (decision<>'proposed' and decided_at is not null and decided_by is not null))
);

create table public.recurring_financial_matching_preferences (
  household_id uuid primary key references public.households(id) on delete cascade,
  date_tolerance_days integer not null default 3 check (date_tolerance_days between 0 and 31),
  amount_tolerance numeric(14,2) not null default 10 check (amount_tolerance >= 0),
  amount_tolerance_percent numeric(6,3) not null default 1 check (amount_tolerance_percent between 0 and 100),
  description_similarity numeric(5,4) not null default 0.55 check (description_similarity between 0 and 1),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now()
);

create index recurring_financial_intentions_household_status_next_idx on public.recurring_financial_intentions(household_id,status,next_occurrence_on);
create index expected_financial_occurrences_household_date_idx on public.expected_financial_occurrences(household_id,expected_on);
create index expected_financial_occurrence_matches_occurrence_idx on public.expected_financial_occurrence_matches(occurrence_id,decision);

alter table public.recurring_financial_intentions enable row level security;
alter table public.expected_financial_occurrences enable row level security;
alter table public.expected_financial_occurrence_matches enable row level security;
alter table public.recurring_financial_matching_preferences enable row level security;

create policy recurring_financial_intentions_read on public.recurring_financial_intentions for select to authenticated using (public.is_household_member(household_id));
create policy expected_financial_occurrences_read on public.expected_financial_occurrences for select to authenticated using (public.is_household_member(household_id));
create policy expected_financial_occurrence_matches_read on public.expected_financial_occurrence_matches for select to authenticated using (public.is_household_member(household_id));
create policy recurring_financial_matching_preferences_read on public.recurring_financial_matching_preferences for select to authenticated using (public.is_household_member(household_id));

revoke all on public.recurring_financial_intentions,public.expected_financial_occurrences,public.expected_financial_occurrence_matches,public.recurring_financial_matching_preferences from public,anon,authenticated;
grant select on public.recurring_financial_intentions,public.expected_financial_occurrences,public.expected_financial_occurrence_matches,public.recurring_financial_matching_preferences to authenticated;

create or replace function public.r3_next_occurrence(p_date date,p_frequency text,p_anchor_day integer)
returns date language sql immutable set search_path=public as $$
  select case p_frequency
    when 'weekly' then p_date+7
    when 'monthly' then make_date(extract(year from (p_date+interval '1 month'))::int,extract(month from (p_date+interval '1 month'))::int,least(p_anchor_day,extract(day from (date_trunc('month',p_date+interval '2 month')-interval '1 day'))::int))
    when 'yearly' then make_date(extract(year from p_date)::int+1,extract(month from p_date)::int,least(p_anchor_day,extract(day from (date_trunc('month',p_date+interval '1 year 1 month')-interval '1 day'))::int))
  end
$$;

create or replace function public.save_recurring_financial_intention(
  p_household_id uuid,p_intention_id uuid,p_economic_type text,p_label text,p_expected_amount numeric,
  p_currency_code text,p_frequency text,p_starts_on date,p_ends_on date,p_concerned_member_id uuid,
  p_source_account_id uuid,p_destination_account_id uuid,p_envelope_id uuid,p_certainty text,
  p_source_kind text,p_source_id uuid,p_source_metadata jsonb,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_existing public.recurring_financial_intentions;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if p_economic_type not in ('income','expense','account_transfer') or p_frequency not in ('weekly','monthly','yearly') or p_certainty not in ('certain','estimated') then raise exception 'Invalid recurring intention'; end if;
  if p_expected_amount<=0 or length(trim(p_label))=0 then raise exception 'Label and positive amount are required'; end if;
  if p_concerned_member_id is not null and not exists(select 1 from public.household_members where household_id=p_household_id and user_id=p_concerned_member_id and inactive_at is null) then raise exception 'Invalid member'; end if;
  if p_source_account_id is not null and not exists(select 1 from public.accounts where id=p_source_account_id and household_id=p_household_id and archived_at is null) then raise exception 'Invalid source account'; end if;
  if p_destination_account_id is not null and not exists(select 1 from public.accounts where id=p_destination_account_id and household_id=p_household_id and archived_at is null) then raise exception 'Invalid destination account'; end if;
  if p_envelope_id is not null and not exists(select 1 from public.envelopes where id=p_envelope_id and household_id=p_household_id and archived_at is null) then raise exception 'Invalid envelope'; end if;
  if p_economic_type='account_transfer' and (p_source_account_id is null or p_destination_account_id is null or p_source_account_id=p_destination_account_id) then raise exception 'Transfer accounts are required and distinct'; end if;
  perform pg_advisory_xact_lock(hashtextextended('r3-intention:'||p_household_id::text||':'||p_idempotency_key::text,0));
  select * into v_existing from public.recurring_financial_intentions where household_id=p_household_id and idempotency_key=p_idempotency_key;
  if found then return v_existing.id; end if;
  if p_intention_id is null then
    insert into public.recurring_financial_intentions(household_id,economic_type,label,expected_amount,currency_code,frequency,starts_on,ends_on,next_occurrence_on,anchor_day,concerned_member_id,source_account_id,destination_account_id,envelope_id,certainty,source_kind,source_id,source_metadata,idempotency_key,created_by)
    values(p_household_id,p_economic_type,trim(p_label),p_expected_amount,upper(p_currency_code),p_frequency,p_starts_on,p_ends_on,p_starts_on,extract(day from p_starts_on)::int,p_concerned_member_id,p_source_account_id,p_destination_account_id,p_envelope_id,p_certainty,p_source_kind,p_source_id,coalesce(p_source_metadata,'{}'),p_idempotency_key,auth.uid()) returning id into v_id;
  else
    select * into v_existing from public.recurring_financial_intentions where id=p_intention_id and household_id=p_household_id for update;
    if not found then raise exception 'Intention access denied'; end if;
    update public.recurring_financial_intentions set economic_type=p_economic_type,label=trim(p_label),expected_amount=p_expected_amount,currency_code=upper(p_currency_code),frequency=p_frequency,ends_on=p_ends_on,concerned_member_id=p_concerned_member_id,source_account_id=p_source_account_id,destination_account_id=p_destination_account_id,envelope_id=p_envelope_id,certainty=p_certainty,source_kind=p_source_kind,source_id=p_source_id,source_metadata=coalesce(p_source_metadata,'{}'),updated_at=now() where id=p_intention_id returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function public.set_recurring_financial_intention_status(p_intention_id uuid,p_status text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_rule public.recurring_financial_intentions;
begin
  select * into v_rule from public.recurring_financial_intentions where id=p_intention_id for update;
  if auth.uid() is null or v_rule.id is null or not public.is_household_member(v_rule.household_id) then raise exception 'Intention access denied'; end if;
  if p_status not in ('active','suspended','stopped') then raise exception 'Invalid status'; end if;
  update public.recurring_financial_intentions set status=p_status,stopped_at=case when p_status='stopped' then now() else null end,updated_at=now() where id=p_intention_id;
  return p_intention_id;
end $$;

create or replace function public.materialize_recurring_financial_occurrences(p_intention_id uuid,p_through date)
returns integer language plpgsql security definer set search_path=public,auth as $$
declare v_rule public.recurring_financial_intentions; v_date date; v_count integer:=0;
begin
  select * into v_rule from public.recurring_financial_intentions where id=p_intention_id for update;
  if auth.uid() is null or v_rule.id is null or not public.is_household_member(v_rule.household_id) then raise exception 'Intention access denied'; end if;
  if p_through>current_date+interval '18 months' then raise exception 'Materialization window is limited to 18 months'; end if;
  if v_rule.status<>'active' then return 0; end if;
  v_date:=v_rule.next_occurrence_on;
  while v_date<=p_through and (v_rule.ends_on is null or v_date<=v_rule.ends_on) loop
    insert into public.expected_financial_occurrences(household_id,intention_id,expected_on,economic_type,label,expected_amount,currency_code,concerned_member_id,source_account_id,destination_account_id,envelope_id,certainty)
    values(v_rule.household_id,v_rule.id,v_date,v_rule.economic_type,v_rule.label,v_rule.expected_amount,v_rule.currency_code,v_rule.concerned_member_id,v_rule.source_account_id,v_rule.destination_account_id,v_rule.envelope_id,v_rule.certainty)
    on conflict(intention_id,expected_on) do nothing;
    if found then v_count:=v_count+1; end if;
    v_date:=public.r3_next_occurrence(v_date,v_rule.frequency,v_rule.anchor_day);
  end loop;
  update public.recurring_financial_intentions set next_occurrence_on=v_date,updated_at=now() where id=v_rule.id;
  return v_count;
end $$;

create or replace function public.record_expected_financial_match(
  p_occurrence_id uuid,p_financial_event_id uuid,p_matched_amount numeric,p_decision text,p_score numeric,p_reasons jsonb,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_occ public.expected_financial_occurrences; v_id uuid; v_expected_type text;
begin
  select * into v_occ from public.expected_financial_occurrences where id=p_occurrence_id for update;
  if auth.uid() is null or v_occ.id is null or not public.is_household_member(v_occ.household_id) then raise exception 'Occurrence access denied'; end if;
  if p_decision not in ('proposed','confirmed','rejected') or p_matched_amount<=0 then raise exception 'Invalid match'; end if;
  v_expected_type:=case v_occ.economic_type when 'income' then 'cash_income' when 'expense' then 'cash_expense' else 'account_transfer' end;
  if not exists(select 1 from public.financial_events where id=p_financial_event_id and household_id=v_occ.household_id and event_type=v_expected_type) then raise exception 'Financial event is incompatible'; end if;
  perform pg_advisory_xact_lock(hashtextextended('r3-match:'||v_occ.id::text||':'||p_financial_event_id::text,0));
  insert into public.expected_financial_occurrence_matches(household_id,occurrence_id,financial_event_id,matched_amount,decision,score,reasons,decided_by,decided_at,idempotency_key,created_by)
  values(v_occ.household_id,v_occ.id,p_financial_event_id,p_matched_amount,p_decision,p_score,coalesce(p_reasons,'[]'),case when p_decision='proposed' then null else auth.uid() end,case when p_decision='proposed' then null else now() end,p_idempotency_key,auth.uid())
  on conflict(occurrence_id,financial_event_id) do update set decision=excluded.decision,score=excluded.score,reasons=excluded.reasons,decided_by=excluded.decided_by,decided_at=excluded.decided_at
  returning id into v_id;
  return v_id;
end $$;

create or replace view public.expected_financial_occurrence_overview with (security_invoker=true) as
select o.*,coalesce(sum(m.matched_amount) filter(where m.decision='confirmed'),0)::numeric(14,2) confirmed_amount,
  case when o.ignored_at is not null then 'ignored'
       when coalesce(sum(m.matched_amount) filter(where m.decision='confirmed'),0)>=o.expected_amount then 'realized'
       when coalesce(sum(m.matched_amount) filter(where m.decision='confirmed'),0)>0 then 'partially_realized'
       when o.expected_on<current_date then 'overdue'
       else 'expected' end occurrence_status
from public.expected_financial_occurrences o left join public.expected_financial_occurrence_matches m on m.occurrence_id=o.id
group by o.id;

revoke all on public.expected_financial_occurrence_overview from public,anon;
grant select on public.expected_financial_occurrence_overview to authenticated;
revoke all on function public.r3_next_occurrence(date,text,integer),public.save_recurring_financial_intention(uuid,uuid,text,text,numeric,text,text,date,date,uuid,uuid,uuid,uuid,text,text,uuid,jsonb,uuid),public.set_recurring_financial_intention_status(uuid,text,uuid),public.materialize_recurring_financial_occurrences(uuid,date),public.record_expected_financial_match(uuid,uuid,numeric,text,numeric,jsonb,uuid) from public,anon;
grant execute on function public.r3_next_occurrence(date,text,integer),public.save_recurring_financial_intention(uuid,uuid,text,text,numeric,text,text,date,date,uuid,uuid,uuid,uuid,text,text,uuid,jsonb,uuid),public.set_recurring_financial_intention_status(uuid,text,uuid),public.materialize_recurring_financial_occurrences(uuid,date),public.record_expected_financial_match(uuid,uuid,numeric,text,numeric,jsonb,uuid) to authenticated;

alter publication supabase_realtime add table public.recurring_financial_intentions,public.expected_financial_occurrences,public.expected_financial_occurrence_matches;

comment on table public.expected_financial_occurrences is 'R3.1 non-financial expectations. Rows never represent FinancialEvents, GL postings, or envelope movements.';
commit;
