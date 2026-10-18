# R3.0 — Audit de couverture « Prévision & automatisation »

## Verdict

**R3.0 AUDIT : PRÊT.** Le dépôt contient déjà les primitives de budget récurrent, d'échéances, de calendrier, de rappels in-app et de projections spécialisées. Il ne contient pas encore un contrat financier récurrent unifié, un rapprochement attendu/réel, ni une projection de trésorerie datée consolidée. R3 doit donc composer et étendre les moteurs existants, pas en créer des copies.

Audit réalisé en lecture seule du code Flutter, des migrations et du schéma Sandbox. Aucun calcul financier, aucune donnée, aucun snapshot et aucune migration n'ont été modifiés.

## Séparation fonctionnelle obligatoire

| Nature | Définition R3 | Effet financier |
|---|---|---|
| Prévision | Occurrence future calculée depuis une règle, une échéance ou un scénario | Aucun |
| Rappel | Message adressé à un utilisateur au sujet d'une échéance ou action | Aucun |
| Proposition | Action préparée et expliquée, encore modifiable/refusable | Aucun avant confirmation |
| Automatisation autorisée | Action explicitement activée, bornée, idempotente et auditée | Mutation uniquement par une primitive canonique et selon la politique confirmée |

Une projection ne doit jamais devenir implicitement un `FinancialEvent`. Les primitives canoniques restent FinancialEvent, Grand Ledger, Envelope Ledger, obligations, Budget Intelligence et FinancialAvailability.

## Matrice exhaustive de couverture

| Besoin | Classification | Existant | Source canonique | UI existante | Backend existant | Tests existants | Manque réel | Action R3 recommandée |
|---|---|---|---|---|---|---|---|---|
| Revenus récurrents par membre | EXISTANT PARTIEL | Revenus nets/autres récurrents configurés par scénario | Budget Intelligence | Scénarios / préparation budget | `budget_scenario_member_incomes` | `budget_contribution_calculator_test.dart` | Pas d'occurrence datée attendue ni de rapprochement avec l'encaissement réel | Produire des occurrences attendues depuis le scénario, sans écriture |
| Charges fixes mensuelles | EXISTANT PARTIEL | Règles fixes ordonnées, membres et enveloppes | Budget Intelligence | Programme budgétaire | `budget_rules`, runs/snapshots | `budget_simulator_test.dart` | Le budget mensuel n'est pas un échéancier transactionnel | Adapter les règles en occurrences prévisionnelles explicables |
| Charges communes et contributions | EXISTANT COMPLET pour le budget | Répartition 1/2/N, clés et financements multi-comptes | Budget Intelligence | Contributions / runs | scénarios, contributions, funding | tests Budget/R2.5/R2.6 | Pas d'attendu bancaire daté | Réutiliser les sorties du run, ne pas recalculer les clés |
| Abonnements et dépenses périodiques | MOTEUR CACHÉ / PARTIEL | Tâches récurrentes et coûts auto périodiques existent | F6 + F5 | Organisation; Patrimoine | `household_tasks`, `vehicle_cost_plans` | tests F5/F6 | Aucun contrat générique montant/date/compte/enveloppe et aucun attendu/réel | Ajouter une intention récurrente minimale reliée aux objets sources |
| Charges annuelles | EXISTANT PARTIEL | Récurrence annuelle des tâches; coûts auto datés | F6/F5 | Organisation; Véhicules | recurrence yearly / recurrence_months | `organization_models_test.dart` | Pas de matérialisation prévisionnelle financière consolidée | Projeter les occurrences; ne pas créer de dépense |
| Virements récurrents | ABSENT | Transfert réel canonique disponible, sans planification récurrente | Transfert canonique | Grand Livre / Fin de mois | `create_account_transfer_event` | tests ledger/R2.10 | Règle future, confirmation et suivi attendu/réel absents | Créer une intention; confirmation via le RPC existant uniquement |
| Allocations budgétaires récurrentes | EXISTANT PARTIEL | Scénarios, périodes, runs et reprise du mois précédent | Budget Intelligence | Budget | RPC de préparation/application | tests Budget/F4 | Pas d'automatisation planifiée; application exige un run approuvé | Conserver l'approbation; proposer la préparation sans appliquer seule |
| Échéances d'obligations | EXISTANT PARTIEL | Date d'échéance, solde restant, alertes | Obligations | Dettes; calendrier | `obligations.due_at`, balances | tests obligations/F6 | Une date par obligation; échéancier global incomplet | Composer avec l'échéancier F5 quand lié à un financement |
| Échéanciers logement/auto | EXISTANT COMPLET comme projection spécialisée | Profil, mensualité, prochaine échéance et calendrier calculé | F5 financement | Patrimoine | `financing_profiles`, `financing_overview` | tests F5A/F5B | Pas injecté dans un cashflow transversal | Fournir ses lignes datées au compositeur R3 |
| Coûts auto futurs | EXISTANT PARTIEL | Plans datés avec périodicité | F5B | Véhicules; calendrier | `vehicle_cost_plans` | `home_auto_models_test.dart` | Récurrence non unifiée avec les autres attendus | Adapter vers le même format prévisionnel |
| Objectifs et PRIOS | EXISTANT COMPLET comme projection spécialisée | Capacité, cascade, reliquat, date cible | FinancialAvailability | Objectifs; Priorités | lectures canoniques | `financial_availability_test.dart` | Ce n'est pas un solde de compte daté | Consommer ses résultats sans en faire des transactions |
| Dépenses planifiées Shopping | EXISTANT PARTIEL | Date souhaitée et plan de financement | Shopping + F4 | Achats | shopping items/plans | tests Shopping/F4 | Pas consolidé dans la trésorerie | Ajouter comme hypothèse identifiable et désactivable |
| Épargne et surplus | EXISTANT PARTIEL | Remainder, revenus exceptionnels, sweep de clôture confirmé | Budget/R2 | Budget; Fin de mois | budget rules, RPC sweep | tests Budget/R2.7 | Pas de règle prospective générique de sweep | Proposer, jamais exécuter sans politique/confirmation explicite |
| Situation compte × enveloppe | EXISTANT COMPLET pour actuel/cible | Matrice actuelle, cibles structurelles, netting | R2 | Fin de mois | positions, targets, drafts | tests R2.2–R2.15 | Ne fournit pas seule un cashflow futur | Utiliser actuel comme point de départ et cible comme contrainte, jamais comme preuve historique |
| Projection foyer datée | ABSENT comme produit consolidé | Soldes et sous-projections séparés | GL + compositeur à créer | Aucune vue unique | lectures canoniques | tests unitaires par moteur | Série de flux datés et solde quotidien/mensuel absents | Construire un compositeur read-only |
| Projection par compte | EXISTANT PARTIEL | Soldes GL, échéances et comptes de financement connus par endroits | GL | Comptes / modules sources | vues de soldes | tests comptes/F5 | Attribution de nombreux flux futurs au compte encore absente | Afficher seulement les flux attribuables; marquer le reste « compte à confirmer » |
| Projection par membre | EXISTANT PARTIEL | Revenus, contributions, ownership, assignee séparés | Membres + Budget | Budget | tables household-scoped | tests 1/2/N | Consolidation et confidentialité à définir | Calcul N membres, avec vue foyer et vue membre selon politique |
| Projection par enveloppe | EXISTANT PARTIEL | Budgets, soldes, objectifs et cibles disponibles | Envelope Ledger + Budget | Budget/Enveloppes | reporting budget | tests Budget/R2 | Les échéances ne portent pas toutes une enveloppe | Ne projeter que les affectations prouvées, signaler les non affectées |
| Horizons fin de mois / mois suivant / 3 / 6 / 12 mois | ABSENT comme interface | Les moteurs spécialisés peuvent calculer plusieurs mois | Compositeur à créer | Aucune | Aucun agrégat unique | Aucun test transversal | Sélecteur d'horizon et granularité manquent | Un moteur unique paramétré par horizon |
| Réel / projeté / scénario | EXISTANT COMPLET comme invariant | Types et écrans séparent les états | Budget, FinancialAvailability, F5 | Plusieurs | tables séparées | tests F4/F5 | Libellé transversal à uniformiser | Préserver et rendre l'origine visible sur chaque ligne |
| Rapprochement attendu / réalisé | ABSENT | Historique FinancialEvent consultable | FinancialEvent | Historique/recherche | `financial_event_history` | tests F2C/F7 | Matching, tolérances et état manquent | Détection read-only puis confirmation humaine |
| Détection assistée de récurrence | ABSENT | Historique exploitable mais aucun détecteur | Historique FinancialEvent | Aucune | aucune fonction dédiée | aucun test | Algorithme, score, explication et validation absents | Détecteur conservateur, sans création automatique |
| Calendrier multi-source | EXISTANT COMPLET | Tâches, budget, obligations, objectifs, shopping, home/auto | F6 | Organisation | projections des sources | tests F6/F6.1 | Manquent les futures occurrences financières R3 | Étendre `CalendarEntry`, pas créer un second calendrier |
| Alertes in-app | EXISTANT PARTIEL | Alertes financières, compensations, tâches en retard, lu/non-lu | F6 + Dashboard | Organisation/Dashboard | `user_alert_states` | tests Dashboard/F6 | Pas de scheduler, snooze, relance ni attendu/réalisé | Étendre F6 avec états temporels |
| Préférences de notifications | EXISTANT PARTIEL | Activation in-app par catégorie et utilisateur | F6 | Organisation | `notification_preferences` RLS | tests F6 | Heure, jours, canal natif et fuseau non paramétrés | Ajouter préférences R3; natif reste P1 |
| Rappel quotidien 20h | ABSENT | Aucun scheduler ni règle d'heure | — | — | — | — | Déclenchement, fuseau et jours actifs absents | Orchestration côté serveur ou scheduler contrôlé, après arbitrage |
| « Fait / Pas encore / snooze 15 min » | EXISTANT PARTIEL | Complétion de tâche et lecture d'alerte existent | F6 | Organisation | occurrences + `user_alert_states` | tests F6 | Snooze et sémantique « pas encore » absents | Étendre l'état d'alerte; ne pas détourner `read_at` |
| Pré-clôture mensuelle | EXISTANT PARTIEL | Checklist, santé et centre À faire sont calculés | R2 | Fin de mois | vues/RPC R2 | tests R2 | Déclenchement programmé absent | Règle légère générant rappel/proposition, aucune clôture automatique |
| Seuils compte/enveloppe/budget | EXISTANT PARTIEL | Alertes négatives et seuil budget dans le Dashboard | Dashboard | Pilotage | calcul client sur sources canoniques | tests Dashboard | Paramétrage par foyer/utilisateur et moteur commun absents | Extraire une règle configurable sans dupliquer les calculs |
| Centre de règles légères | ABSENT comme centre | Règles distribuées dans Budget, F6, Dashboard, R2 et F5 | Sources existantes | Aucune surface unique | plusieurs tables spécialisées | tests par module | Catalogue, activation, portée, acteur et audit absents | Créer un orchestrateur minimal de références, pas un moteur « Zapier » |
| Exécution financière automatique | ABSENT volontairement | RPC canoniques confirmables et idempotentes | FinancialEvent | Surfaces métier | RPC canoniques | tests idempotence | Politique d'autorisation non arbitrée | V1 par défaut : rappel/proposition; aucune exécution implicite |

## Primitives canoniques à réutiliser

- **Réel financier** : FinancialEvent, Grand Ledger et Envelope Ledger.
- **Budget et scénario** : Budget Intelligence, périodes, règles, contributions et runs approuvés.
- **Capacité et objectifs** : FinancialAvailability, PRIOS, Shopping et Objectives.
- **Échéances spécialisées** : obligations, financements F5 et coûts home/auto.
- **Organisation** : `CalendarEntry`, `AppAlert`, tâches/occurrences, préférences et navigation F6.
- **Cycle mensuel** : checklist, santé, centre À faire, matrice compte × enveloppe et clôture R2.
- **Exécution confirmée** : uniquement les RPC canoniques existantes; aucune écriture directe depuis une projection.

## Moteurs cachés, doublons et legacy

### Moteurs cachés ou sous-exposés

- `budget_scenarios.trigger_type/trigger_definition` existe mais n'est pas un orchestrateur générique.
- `household_tasks` constitue déjà un moteur simple de récurrence non financière.
- `vehicle_cost_plans.recurrence_months` et les profils de financement fournissent des occurrences spécialisées.
- `user_alert_states.dismissed_at` est prévu dans le schéma, tandis que l'application exploite principalement `read_at`.
- Les alertes Dashboard couvrent déjà seuils, échéances, rapprochements, objectifs et PRIOS.

### Doublons à éviter

- Ne pas créer un deuxième calendrier, un deuxième système d'alertes, un deuxième moteur Budget ou un second moteur de capacité.
- Ne pas recalculer les échéanciers F5 ni les contributions membres R2/Budget dans R3.
- Ne pas transformer une tâche récurrente en transaction récurrente : ce sont deux contrats différents reliables entre eux.

### Legacy

Aucun ancien moteur financier récurrent complet n'est exposé. Les primitives historiques de mutation financière ne doivent pas être réactivées. Les tables et RPC actuelles montrent au contraire une séparation canonique entre projections, tâches et mutations confirmées.

## Cas métier couverts par le futur compositeur

- salaires et autres revenus de référence, avec statut attendu/réalisé;
- charges personnelles, communes, mensuelles, annuelles et abonnements;
- échéances logement/auto, obligations et coûts périodiques;
- enveloppes, objectifs, PRIOS, Shopping et dépenses planifiées;
- scénarios budgétaires, contributions 1/2/N et surplus/primes;
- rapprochement, pré-clôture et clôture sans automatisation financière implicite;
- projection foyer, compte, membre et enveloppe, avec origine et niveau de certitude visibles.

## Multi-utilisateur et sécurité

Les sources R3 existantes sont household-scoped et les tables F6 utilisent RLS. Le futur modèle devra conserver `actor`, membre, titulaire, débiteur/créancier et assignee comme concepts distincts. Une règle de foyer ne doit pas devenir une préférence privée, et une préférence privée ne doit pas être exposée aux autres membres. Les tests minimaux devront couvrir 1/2/N membres, OWNER/MEMBER, non-membre, cross-household, changement de foyer, idempotence et absence totale d'écriture financière lors d'une simulation.

## Arbitrages métier nécessaires avant implémentation

1. Politique V1 d'exécution : confirmer que toute règle financière produit seulement un rappel ou une proposition, sauf autorisation explicite bornée.
2. Tolérances du rapprochement attendu/réalisé : fenêtre de dates, écart de montant, libellé/marchand et traitement des paiements fractionnés.
3. Visibilité multi-utilisateur : règles de foyer communes versus rappels/préférences privés par membre.
4. Projection incertaine : inclusion ou exclusion par défaut des revenus exceptionnels, Shopping et objectifs non sécurisés.
5. Flux sans compte ou enveloppe prouvés : affichage « à confirmer » versus exclusion des sous-totaux détaillés.
6. Rappel quotidien : heure locale, jours actifs, fuseau du foyer/utilisateur et comportement du snooze.

## Découpage R3 minimal recommandé

1. **R3.1 — Intentions récurrentes et attendu/réalisé** : contrat minimal, adaptateurs Budget/F5/F6, détection conservatrice, validation humaine et aucune écriture automatique.
2. **R3.2 — Projection de trésorerie consolidée** : compositeur read-only par horizon, foyer/compte/membre/enveloppe, scénarios et explications; réutilisation de FinancialAvailability.
3. **R3.3 — Rappels et règles légères** : extension de F6 pour échéances, snooze, pré-clôture, préférences et propositions; notifications natives conservées pour P1.

Trois lots sont justifiés : les occurrences attendues sont la donnée d'entrée de la projection, et les rappels/règles consomment ensuite les deux sans devenir un moteur financier parallèle.
