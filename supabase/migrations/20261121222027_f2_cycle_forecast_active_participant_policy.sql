-- F2 — a former household member must not retain access to consent metadata.

drop policy if exists member_cycle_forecast_shares_participants_read
  on public.member_cycle_forecast_shares;

create policy member_cycle_forecast_shares_active_participants_read
  on public.member_cycle_forecast_shares for select to authenticated
  using (
    public.is_household_member(household_id)
    and (
      owner_user_id = (select auth.uid())
      or recipient_user_id = (select auth.uid())
    )
  );
