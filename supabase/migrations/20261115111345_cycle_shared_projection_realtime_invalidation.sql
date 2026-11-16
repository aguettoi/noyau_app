-- Realtime transports only a household-scoped invalidation topic. Raw Cycle
-- observations and private journal values never enter the publication.
create trigger l3b_safe_realtime_member_cycle_events
after insert or update or delete on public.member_cycle_events
for each row execute function private.emit_household_realtime_invalidation();

create trigger l3b_safe_realtime_member_cycle_calendar_shares
after insert or update or delete on public.member_cycle_calendar_shares
for each row execute function private.emit_household_realtime_invalidation();
