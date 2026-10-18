begin;

alter table public.recurring_financial_audit_events
  drop constraint recurring_financial_audit_events_entity_type_check;
alter table public.recurring_financial_audit_events
  add constraint recurring_financial_audit_events_entity_type_check
  check (entity_type in ('intention','occurrence','match'));

create or replace function public.audit_recurring_financial_change()
returns trigger language plpgsql security definer set search_path=public,auth as $$
declare v_entity text;
begin
  v_entity:=case tg_table_name
    when 'recurring_financial_intentions' then 'intention'
    when 'expected_financial_occurrences' then 'occurrence'
    else 'match'
  end;
  insert into public.recurring_financial_audit_events(
    household_id,entity_type,entity_id,action,before_state,after_state,acted_by
  ) values(
    new.household_id,v_entity,new.id,
    case when tg_op='INSERT' then 'created' else 'updated' end,
    case when tg_op='UPDATE' then to_jsonb(old) else null end,
    to_jsonb(new),auth.uid()
  );
  return new;
end $$;

create trigger expected_financial_occurrences_audit
after update on public.expected_financial_occurrences
for each row execute function public.audit_recurring_financial_change();

create or replace function public.ignore_expected_financial_occurrence(
  p_occurrence_id uuid,
  p_reason text,
  p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_occ public.expected_financial_occurrences;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null then raise exception 'Idempotency key required'; end if;
  if length(trim(coalesce(p_reason,'')))=0 then raise exception 'Ignore reason required'; end if;

  select * into v_occ
  from public.expected_financial_occurrences
  where id=p_occurrence_id
  for update;
  if v_occ.id is null or not public.is_household_member(v_occ.household_id) then
    raise exception 'Occurrence access denied';
  end if;

  update public.expected_financial_occurrences
  set ignored_at=coalesce(ignored_at,now()),
      ignored_by=coalesce(ignored_by,auth.uid()),
      ignore_reason=coalesce(ignore_reason,trim(p_reason))
  where id=p_occurrence_id;
  return p_occurrence_id;
end $$;

revoke all on function public.ignore_expected_financial_occurrence(uuid,text,uuid)
from public,anon;
grant execute on function public.ignore_expected_financial_occurrence(uuid,text,uuid)
to authenticated;

commit;
