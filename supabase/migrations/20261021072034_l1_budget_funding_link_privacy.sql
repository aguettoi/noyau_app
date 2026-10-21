-- A permissive membership policy OR-ed with the privacy policy, exposing
-- private account references from otherwise shared budget funding links.
drop policy if exists "members read budget funding links"
  on public.budget_funding_links;
drop policy if exists "l1 private budget funding links"
  on public.budget_funding_links;

create policy "l1 visible budget funding links"
  on public.budget_funding_links for select to authenticated
  using (
    public.is_household_member(household_id)
    and (
      source_account_id is null
      or private.can_discover_account(source_account_id, (select auth.uid()))
    )
    and private.can_read_financial_line(source_account_id, (select auth.uid()))
  );
