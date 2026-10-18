begin;
create or replace function private.keep_latest_reminder_phase()
returns trigger language plpgsql security definer set search_path=public,private as $$
begin
  if new.source_kind='r3_1_occurrence' then
    update public.financial_reminders set status='cancelled',resolved_at=coalesce(resolved_at,now())
    where household_id=new.household_id and source_kind=new.source_kind and source_id=new.source_id
      and id<>new.id and status='active' and due_at<=new.due_at;
  end if;
  return new;
end $$;
create trigger financial_reminders_latest_phase after insert on public.financial_reminders
for each row execute function private.keep_latest_reminder_phase();
revoke all on function private.keep_latest_reminder_phase() from public,anon,authenticated;
commit;
