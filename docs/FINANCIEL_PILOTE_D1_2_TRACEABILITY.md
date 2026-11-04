# FINANCIEL PILOTE — D1.2 traceability

Baseline: `009bcf30b3dbca9efc5717536a48444f8a3511d3`.

This matrix is the presentation contract for D1.2. It does not change any
business status or backend contract. “Advanced” means progressive disclosure,
never removal.

| Capability family | Historical surface | D1.2 destination | Level | Desktop/Web | Mobile | D1.2-A state | Existing evidence |
|---|---|---|---|---|---|---|---|
| Dashboard/KPI/alerts | Dashboard | Home | Simple cockpit + analytics advanced | Rail/Home | Home | D1.2-B redesigned: month situation, canonical action centre, today, goals and secondary overview; all prior KPI panels remain under Analytics | dashboard home, visual, V2 and KPI tests |
| Accounts/cash/reconciliation/privacy | Accounts | Money > Accounts | Simple + Advanced | Money hub | Money hub | D1.2-C redesigned: simple cards and advanced reconciliation/inventory with privacy preserved | accounts/privacy and D1.2-C visual tests |
| Transactions/transfers | Transactions | Money > Transactions / universal + | Simple + Advanced | Money hub/+ | Money/+ | D1.2-C redesigned: quick filters, progressive entry and advanced workflows preserved | transaction and D1.2-C visual tests |
| Debts/receivables/settlements | Transactions subpages | Money > Debts and receivables / + | Advanced | Money hub/+ | Money/+ | Routed | debt/receivable tests |
| Envelopes/movements/recommendations | Envelope dashboard | Money > Envelopes + ENV-TPL | Simple + Advanced | Money hub | Money hub | D1.2-C redesigned: readable balances plus reusable localized template catalog | envelope, ENV-TPL and D1.2-C visual tests |
| Budget/contributions/scenarios/program/runs | Budget pages | Money > Budget | Simple + Advanced | Money hub | Money hub | Routed | budget tests |
| Monthly close/compensations/inventories | Monthly close/compensations | Money > Advanced | Advanced | Existing routes | Existing routes | Preserved | close/compensation tests |
| Cashflow/projections/recurring | Projection/recurring | Money and Household | Advanced | hubs | hubs | Routed | projection/recurring tests |
| Savings goals | Goals | Projects > Goals | Simple + Advanced | Projects hub | More/Projects | Routed | goal tests |
| PRIOS | Priorities | Projects > PRIOS | Simple + Advanced | Projects hub | More/Projects | Routed | priority tests |
| Wealth/home/vehicles/investments/financing | Wealth | Projects > Wealth | Simple + Advanced | Projects hub | More/Projects | Routed | wealth tests |
| Shopping list | Shopping | Household > Daily life | Simple | Household hub | Household hub | Preserved direct index + hub | shopping tests |
| Tasks/calendar/alerts | Organization | Household > Tasks and calendar | Simple + Advanced | Household hub | Household hub | Routed | organization tests |
| Home/contracts/warranties/maintenance | Daily life | Household > Daily life | Simple + Advanced | Household hub | Household hub | Routed | daily-life tests |
| Menstrual cycle/private sharing | Daily life/Cycle | More > Personal space > Cycle | Sensitive advanced | Existing Daily life route | Existing Daily life route | Preserved; dedicated composition deferred | cycle/RLS tests |
| Household/members/invitations/roles | Settings/dialogs | More > Members/Settings | Simple + Advanced | More hub | More hub | Routed | household tests |
| Import/history/cutover | Imports | More > Imports | Advanced | More hub | More hub | Routed | import/cutover tests |
| Search/export/portability | Portability | More > Reports and portability | Advanced | More hub | More hub | Routed | portability tests |
| Assistant L5 | Assistant | More + Ctrl+K | Simple | Global | Global | Routed | assistant tests |
| Onboarding/help/language/accessibility | Experience surfaces | More | Simple | Global/More | Global/More | Routed | L4 tests |
| Offline resilience | Shell/drafts | Global status banner | Simple | Persistent | Persistent | Foundation delivered | L4 tests |

## D1.2-D — Budget, control and close

The D1.2-D checkpoint preserves every historical destination and adds guided,
progressively disclosed entry points. It does not introduce a second budget,
alert, calendar, reconciliation or accounting engine.

| Capability | Destination after D1.2-D | Canonical source/action | State |
|---|---|---|---|
| Monthly preparation | Money > Budget > Prepare my month | Existing scenario, contributions and monthly preparation providers | Guided and reachable |
| Programmable budget | Money > Budget > Program | Existing programmable engine and simulation | Simple/advanced modes reachable |
| Scenarios and simulations | Money > Budget > Scenarios | Existing scenario and simulation contracts | Clearly marked simulation |
| Envelope recommendations | Money > Envelopes > Recommendations | Existing recommendation provider | Rule/recommendation/error distinguished |
| Account reconciliation | Money > Accounts > Check my balance | Canonical observation and reconciliation providers | Real/theoretical/difference visible when authorized |
| Cash inventory | Money > Accounts > Cash inventory | Canonical cash observation, optional denominations | Direct amount or denominations |
| Member regularization | Canonical transaction/reconciliation flow | FinancialEvent canonical actions | Explicit confirmation, 1/2/N |
| Monthly close | Money > Advanced > Finalize my month | Existing monthly-close workflow | Six-step guide and blockers |
| Compensations | Money > Advanced > Internal compensations | Existing compensation actions | Debtor/creditor/amount/reason/state explicit |

Historical capability families without a destination after D1.2-D: **0**.
Removed or inaccessible historical functions: **0**.

## D1.2-D architecture before / after

Measurements compare baseline `0c693e8cc77073d6eeac6d9e98ade793c6c7db23`
with the D1.2-D worktree.

| Surface | Before | After | Change and assessment |
|---|---:|---:|---|
| `programmable_budget_program_page.dart` | 3,650 lines / 23 declared types | 3,687 lines / 23 declared types | Simple-mode entry and progressive disclosure added; orchestration and most presentation responsibilities remain in the monolith. |
| `budget_monthly_preparation_page.dart` | 2,236 lines / 14 declared types | 2,249 lines / 14 declared types | Guided entry added; canonical providers and simulator preserved. Significant monolith debt remains. |
| `monthly_close_page.dart` | 2,885 lines / 13 declared types | 2,906 lines / 13 declared types | Six-step close guide added; canonical blockers/actions preserved. Significant monolith debt remains. |

Extracted reusable component: `BudgetWorkflowGuide`, responsible only for
step/state/navigation presentation. It contains no financial calculation,
Supabase access or mutation.

Architecture verdict: user guidance improved, but the three large files were
not materially decomposed. Human Developer Readiness is therefore **not
certified**. Final audit debt remains open for Transactions, Accounts,
Envelopes, Programmable Budget, Monthly Preparation and Monthly Close.

## Result

- Historical capability families recorded: 20.
- Families with a D1.2 destination: 20.
- Families without a destination: 0.
- All original IndexedStack destinations remain addressable during migration.

## D1.2-D certification evidence

The 18 D1.2-D visual proofs under `test/d12/runtime_goldens/` are rasterized
from the real production pages with deterministic provider fixtures. They cover
monthly preparation (desktop/mobile), programmable budget (simple/advanced),
scenario/simulation, recommendations, reconciliation, both cash-count modes,
member regularization, monthly close (desktop/mobile/blocker/final confirmation),
compensation, dark mode, RTL and an empty household state.

The contact-sheet and individual-image review found no overflow, clipping,
overlap or private-value disclosure. The initial compensation capture exposed
only a loading state; its fixture was corrected and the proof regenerated with
an active deterministic compensation. The RTL proof loads the Windows
Arabic-capable Tahoma font in the test harness, so Arabic glyphs,
directionality and numeric readability are visually reviewable without
changing the application font or production code.

Final automated certification: 1,174 tests passed and 3 environment-dependent
tests were conditionally skipped. Product analysis, formatting, Windows release
and Web release passed. No financial mutation, import, cutover, purge or
Supabase migration was performed.

## D1.2-E — Household, daily life and personal organization

The Household destination now opens on a focused **Today** projection backed
by the existing `organizationCalendarProvider`. Tasks, calendar and reminders
remain the canonical L3B surfaces; no second task, calendar, alert or recurrence
engine was introduced. Ordinary task creation keeps title, responsible member
and due date in the primary flow while room, duration, workload, priority and
recurrence remain available through progressive disclosure.

Domestic groceries remain distinct from financial Shopping. Marking an item as
purchased only updates the domestic list. The explicit **Record the expense**
action opens the canonical Transactions expense workflow with safe prefill and
does not create a `FinancialEvent`, GL posting or envelope movement by itself.

Daily life keeps home, vehicle, contract, warranty and maintenance records on
their existing providers and calendar projection. Personal space is visually
separated from collective Household data. Menstrual-cycle events remain owner
only by default; the existing server-side sharing contract exposes only dates
and phases to explicitly selected members, while symptoms, notes and flow stay
private. Revocation continues through the canonical L3B action/provider.

| Historical capability | D1.2-E destination | Canonical contract |
|---|---|---|
| Household tasks and responsibility | Household > Tasks | `householdTasksProvider` / existing actions |
| Today and upcoming items | Household > Today | `organizationCalendarProvider` + `CalendarEntry` filtering |
| Calendar | Household > Calendar | Existing organization calendar |
| Recurrences and reminders | Household > Tasks / Reminders | Existing recurring-finance and alert contracts |
| Domestic groceries | Household > Daily life > Groceries | L3B grocery provider/actions |
| Grocery to expense | Explicit Transactions transition | Canonical `TransactionsPage` expense flow |
| Home, vehicles, maintenance, contracts | Household > Daily life > Home & vehicles | L3B home-record provider/calendar projection |
| Personal menstrual cycle | Household > Daily life > My space | L3B private cycle providers/RLS |

Historical Household/Daily Life/Cycle capabilities without a destination: **0**.
Functional loss: **0**. Direct Supabase access added to Presentation: **0**.
Financial mutations introduced by D1.2-E: **0**.

## D1.2-F — Projects, goals, simulations and wealth

The Projects universe now has a dedicated decision hub with explicit routes to
Goals, PRIOS, Simulations, Financing and Wealth. The hub delegates to existing
canonical providers and domain calculators; it contains no financial formula,
Supabase access or mutation.

| Historical capability | D1.2-F destination | Canonical contract |
|---|---|---|
| Savings and non-financial goals | Projects > Goals | Existing savings-goal providers and envelope-backed progress |
| Priority plans and linked projects | Projects > PRIOS | Existing priority-plan and financial-availability projections |
| Financing simulation | Projects > Simulations | `simulateFinancingOffer` through the existing comparison UI |
| Financing comparison | Projects > Financing | Existing two-offer comparison, capacity and assumption contracts |
| Murabaha/fixed cost/interest structures | Financing comparison | Existing `FinancingStructure`; terminology remains structure-specific |
| Amortization schedules | Wealth > Financing / History & dues | Existing `buildFinancingSchedule` |
| Assets and liabilities | Projects > Wealth | Existing `wealthDataProvider` and privacy-filtered snapshot |
| Valuations and investments | Wealth > Assets / Investments | Existing wealth records and valuation dates |

Simulation surfaces explicitly state that no debt, obligation, GL entry or
`FinancialEvent` is created. Mobile financing comparison now uses the full
viewport while desktop retains side-by-side offer cards. Wealth tabs remain
scrollable on compact widths. Private values continue to be omitted by the
authorized server/provider contracts; Presentation does not substitute zero or
reconstruct a household total.

Historical Projects/Goals/PRIOS/Simulation/Financing/Wealth capabilities
without a destination: **0**. Functional loss: **0**. Direct Supabase access
added to Presentation: **0**. Financial mutations introduced: **0**.

## HOTFIX-D1.2-NAV — Universe, business page and legacy index separation

Root cause: the shell still constructed an eight-destination historical
`NavigationRail` with the modern eleven-page `IndexedStack` index. Household,
Projects and More use page indices 8, 9 and 10, outside that historical rail.

| Business page / legacy index | Active universe | Historical rail selection |
|---|---|---|
| Dashboard / 0 | Home | 0 |
| Accounts / 1 | Money | 1 |
| Money hub / 2 | Money | 2 |
| Envelopes / 3 | Money | 3 |
| Goals / 4 | Projects | 4 |
| Shopping / 5 | Money | 5 |
| PRIOS / 6 | Projects | 6 |
| Imports / 7 | More | 7 |
| Household hub / 8 | Household | none (`null`) |
| Projects hub / 9 | Projects | none (`null`) |
| More hub / 10 | More | none (`null`) |

The five-universe D1.2 navigation receives only an `FpUniverse`. The legacy
rail receives an index only when that destination exists in the legacy rail.
Breakpoint changes preserve the active universe and never reuse a business
page index as an adaptive-navigation index.

The authenticated Wealth surface also exposed a separate loading defect during
the runtime campaign. Its gateway queried the canonical
`expected_financial_occurrence_overview` view with the non-existent `status`
column, while the view contract exposes `occurrence_status`. The client query
now selects and filters `occurrence_status`; a PostgREST request-contract test
locks this mapping. No schema, RLS policy, financial engine or migration was
changed.
