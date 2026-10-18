begin;
create table public.recurring_financial_audit_events (
  id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households(id) on delete cascade,
  entity_type text not null check (entity_type in ('intention','match')), entity_id uuid not null,
  action text not null check (action in ('created','updated')), before_state jsonb, after_state jsonb not null,
  acted_by uuid not null references auth.users(id), acted_at timestamptz not null default now()
);
create index recurring_financial_audit_household_entity_idx on public.recurring_financial_audit_events(household_id,entity_type,entity_id,acted_at desc);
alter table public.recurring_financial_audit_events enable row level security;
create policy recurring_financial_audit_events_read on public.recurring_financial_audit_events for select to authenticated using (public.is_household_member(household_id));
revoke all on public.recurring_financial_audit_events from public,anon,authenticated;
grant select on public.recurring_financial_audit_events to authenticated;
create or replace function public.audit_recurring_financial_change()
returns trigger language plpgsql security definer set search_path=public,auth as $$
declare v_entity text;
begin
  v_entity:=case tg_table_name when 'recurring_financial_intentions' then 'intention' else 'match' end;
  insert into public.recurring_financial_audit_events(household_id,entity_type,entity_id,action,before_state,after_state,acted_by)
  values(new.household_id,v_entity,new.id,case when tg_op='INSERT' then 'created' else 'updated' end,case when tg_op='UPDATE' then to_jsonb(old) else null end,to_jsonb(new),auth.uid());
  return new;
end $$;
create trigger recurring_financial_intentions_audit after insert or update on public.recurring_financial_intentions for each row execute function public.audit_recurring_financial_change();
create trigger expected_financial_occurrence_matches_audit after insert or update on public.expected_financial_occurrence_matches for each row execute function public.audit_recurring_financial_change();
revoke all on function public.audit_recurring_financial_change() from public,anon,authenticated;
commit;
