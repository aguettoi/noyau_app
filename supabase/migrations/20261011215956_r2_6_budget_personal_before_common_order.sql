-- R2.6 — keep personal charges before common allocations in the six
-- spreadsheet-certified pilot scenarios. Amounts, contribution keys and
-- historical budget run snapshots are intentionally left untouched.
begin;

create temporary table r2_6_reordered_steps on commit drop as
select
  st.id,
  (row_number() over (
    partition by st.scenario_version_id
    order by
      case
        when st.contribution_key = 'single_member'
          and st.group_name not like 'Charges communes — Habits%'
        then 0
        else 1
      end,
      st.step_order,
      st.id
  ) - 1) * 10 as new_step_order
from public.budget_scenarios s
join public.households h on h.id = s.household_id
join public.budget_scenario_steps st
  on st.scenario_version_id = s.current_version_id
 and st.household_id = s.household_id
where h.name = 'FINANCIEL PILOTE — FOYER RÉEL'
  and s.name in (
    'DEPART',
    'APRES ACQUISITION VOITURE',
    'APRES REMBOURSEMENT 40K',
    'APRES AOUT 27',
    'APRES REMBOURSEMENT VOITURE',
    'APRES FIN PRIO'
  );

-- Avoid the immediate unique constraint on (scenario_version_id, step_order)
-- while preserving every row and only changing its position.
update public.budget_scenario_steps st
set step_order = st.step_order + 10000
from r2_6_reordered_steps reordered
where reordered.id = st.id;

update public.budget_scenario_steps st
set step_order = reordered.new_step_order
from r2_6_reordered_steps reordered
where reordered.id = st.id;

do $$
begin
  if exists (
    with ordered as (
      select
        s.id,
        st.step_order,
        st.contribution_key,
        st.group_name,
        min(st.step_order) filter (
          where st.contribution_key <> 'single_member'
             or st.group_name like 'Charges communes — Habits%'
        ) over (partition by s.id) as first_common_order
      from public.budget_scenarios s
      join public.households h on h.id = s.household_id
      join public.budget_scenario_steps st
        on st.scenario_version_id = s.current_version_id
       and st.household_id = s.household_id
      where h.name = 'FINANCIEL PILOTE — FOYER RÉEL'
        and s.name in (
          'DEPART',
          'APRES ACQUISITION VOITURE',
          'APRES REMBOURSEMENT 40K',
          'APRES AOUT 27',
          'APRES REMBOURSEMENT VOITURE',
          'APRES FIN PRIO'
        )
    )
    select 1
    from ordered
    where contribution_key = 'single_member'
      and group_name not like 'Charges communes — Habits%'
      and step_order > first_common_order
  ) then
    raise exception 'R2.6 invariant failed: a personal charge remains after common allocations';
  end if;
end;
$$;

commit;
