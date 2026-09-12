# Budget Intelligence

## Séparation des responsabilités

```text
Scénario et règles (plan) → simulation pure → allocation run approuvé
                                              ↓ seulement après validation
                                        FinancialEvent d’allocation
                                              ↓
                                    Grand Livre et journal des enveloppes
```

Le réel reste immuable. Un `BudgetAllocationRun` n’est qu’une proposition tant qu’il n’est pas appliqué par une RPC FinancialEvent idempotente.

## Concepts

- `BudgetPeriod` : mois du foyer, draft/active/closed. La convention unique est
  `starts_on` / `ends_on`, héritée de la fondation historique ; `year` et `month`
  sont des propriétés dérivées côté Flutter, jamais des colonnes SQL concurrentes.
- `BudgetScenario` : configuration priorisée et éventuellement conditionnelle.
- `BudgetScenarioRule` : règle par enveloppe (fixed, percentage, residual, target ou none), report et provenance souple.
- `BudgetAllocationRun` et lignes : simulation auditable, sans mouvement de ledger.
- `BudgetGoal` : objectif priorisé financé, au besoin, par une enveloppe.

## Rollover et soldes négatifs

Les politiques sont `report_total`, `report_deficit_only`, `reset` et `cap_rollover`. Une dépense cash ou une dette peut faire passer une enveloppe sous zéro : le moteur produit alors un avertissement, sans remise à zéro. Les allocations et remboursements sont positifs; un transfert ne devra pas rendre l’enveloppe source négative.

## Reporting

`budget_envelope_reporting` est calculée depuis `envelope_movements`. Les horizons Monthly, YTD et LTD, ainsi que plan/réel/écart et la projection de fin de mois, seront dérivés de ce journal et des règles, sans cumuls métiers mutables.

## Contributions et provenance

Les contributions (proportionnelle aux revenus, pourcentage fixe, Ibrahim, Nora ou personnalisée) sont une répartition économique. Les préférences de compte restent traçables et souples via `budget_funding_links`, jamais une réservation bancaire stricte.

## SIMULATION.xlsx

| Feuille historique | Cible |
| --- | --- |
| SCENARIOS | BudgetScenario / BudgetScenarioRule |
| TDB | reporting plan/réel |
| PRIOS | BudgetGoal |
| tests de salaires | futur What-if |
| sources salaire/cash | contribution et préférence de financement |

## Suite

L’application atomique utilisera `allocate_budget_event` après confirmation. Les déclencheurs conditionnels, l’import final Excel et le What-if restent explicitement hors de cette fondation.
