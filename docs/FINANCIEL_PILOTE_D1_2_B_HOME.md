# D1.2-B — Accueil / Dashboard

## Contract delivered

The Home surface is a household cockpit with five levels, in this order:

1. the official prepared budget situation for the selected month;
2. actionable items from the canonical organization alert centre;
3. today's entries from the canonical organization calendar;
4. at most three active savings goals;
5. a compact monthly flow overview and entry to advanced analytics.

The previous detailed Dashboard panels and L3A operational KPIs are preserved
behind **View analytics**. The Home surface does not create a second alert,
calendar, goal or budget engine.

## Data and privacy decisions

- “Available” means `DashboardBudgetSummary.remaining` (official planned budget
  minus recognized budget consumption). It never means bank balance, envelope
  availability, liquidity or net worth.
- If no prepared budget exists, Home displays a setup state; it does not invent
  zero.
- Account totals and hidden balances are not consumed by the main situation
  card. Private accounts therefore cannot be reconstructed by subtraction.
- Today is composed only from `organizationCalendarProvider`. The shared
  calendar contract has no menstrual-cycle source, so sensitive cycle data is
  absent by default.
- Alerts are read from `organizationAlertsProvider`, deduplicated for
  presentation and routed to canonical workflows.
- A failure of an optional organization/member source yields a visible partial
  state while the canonical financial snapshot remains usable.

## Responsive and accessibility contract

- Mobile: one column in the required priority order.
- Tablet/desktop: two balanced rows before the compact overview.
- RTL uses directional padding/alignment and Material directionality.
- Cards expose distinct, minimum-size actions instead of ambiguous nested
  gestures. Reading order follows the visual order.
- Dark mode uses the shared Material 3 tokens.

## Universal add

From Home, the canonical D1.2-A sheet exposes expense, income, transfer, debt,
receivable, task, grocery item, event, goal and PRIO. Every action opens an
existing canonical page; the sheet performs no financial mutation.

## Visual evidence

Deterministic golden files live under `test/dashboard/goldens/`:

- `d12b_dashboard_desktop.png`
- `d12b_dashboard_mobile.png`
- `d12b_dashboard_tablet.png`
- `d12b_dashboard_dark.png`
- `d12b_dashboard_rtl.png`
- `d12b_dashboard_empty.png`
- `d12b_dashboard_no_actions.png`
- `d12b_dashboard_add_sheet.png`

They validate layout only; business/privacy behavior remains covered by the
provider and widget tests.

## Non-goals

No Supabase migration, financial mutation, import, cutover, purge or D1.2-C
work is included.
