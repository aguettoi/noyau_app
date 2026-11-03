# FINANCIEL PILOTE — D1.2 traceability

Baseline: `009bcf30b3dbca9efc5717536a48444f8a3511d3`.

This matrix is the presentation contract for D1.2. It does not change any
business status or backend contract. “Advanced” means progressive disclosure,
never removal.

| Capability family | Historical surface | D1.2 destination | Level | Desktop/Web | Mobile | D1.2-A state | Existing evidence |
|---|---|---|---|---|---|---|---|
| Dashboard/KPI/alerts | Dashboard | Home | Simple cockpit + analytics advanced | Rail/Home | Home | D1.2-B redesigned: month situation, canonical action centre, today, goals and secondary overview; all prior KPI panels remain under Analytics | dashboard home, visual, V2 and KPI tests |
| Accounts/cash/reconciliation/privacy | Accounts | Money > Accounts | Simple + Advanced | Money hub | Money hub | Routed | accounts/privacy tests |
| Transactions/transfers | Transactions | Money > Transactions / universal + | Simple + Advanced | Money hub/+ | Money/+ | Routed | transaction tests |
| Debts/receivables/settlements | Transactions subpages | Money > Debts and receivables / + | Advanced | Money hub/+ | Money/+ | Routed | debt/receivable tests |
| Envelopes/movements/recommendations | Envelope dashboard | Money > Envelopes | Simple + Advanced | Money hub | Money hub | Routed | envelope tests |
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

## Result

- Historical capability families recorded: 20.
- Families with a D1.2 destination: 20.
- Families without a destination: 0.
- All original IndexedStack destinations remain addressable during migration.
