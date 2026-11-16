-- PostgREST upsert requires UPDATE even when the first operation inserts.
-- RLS still restricts every affected row to its owner.
grant update on public.member_cycle_calendar_shares to authenticated;
