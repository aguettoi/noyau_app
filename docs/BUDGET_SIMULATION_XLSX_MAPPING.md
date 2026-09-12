# Mapping SIMULATION.xlsx

| Historique | Modèle Budget Intelligence |
|---|---|
| SALAIRE | revenu récurrent de membre |
| IBRAHIM / NORA | `personal_member` avec membre dynamique du foyer |
| SALAIRE DEUX | `shared_auto` |
| % membre | clé contributive calculée sur capacité disponible |
| CASH / compte | préférence souple de source de financement |
| SCENARIOS | `BudgetScenario` et règles |
| TDB | reporting prévu / réel / écart |
| PRIOS | objectifs et priorités |

Les noms de personnes ne sont jamais une donnée de domaine : seuls les
identifiants de `household_members` sont persistés.
# Mapping du fichier historique vers le moteur programmable

| Feuille historique | Modèle programmable |
| --- | --- |
| SCENARIO | `BudgetScenario` puis `BudgetScenarioVersion` |
| KEY | identifiant logique/version de règle, sans enum métier figé |
| ENVELOPPES | `Envelope` référencée par `BudgetAllocationStep` |
| MONTANT PREVU | méthode `fixed`, `percentage` ou `residual` de l’étape |
| SALAIRE (membre) | `BudgetSource` de type revenu récurrent membre + clé `single_member` |
| SALAIRE DEUX | source `commonCapacity` + clé automatique ou personnalisée |
| CASH | préférence de paiement analytique, jamais une source économique |
| Durée en mois | dates de validité indicatives du template |
| Pourcentages par membre | `ContributionKeyStrategy.customPercentage` |

Les phases historiques (départ, après acquisition, après remboursement, etc.)
deviennent des templates versionnés. Elles restent des noms utilisateur et ne
deviennent jamais des valeurs codées en dur dans le domaine.
