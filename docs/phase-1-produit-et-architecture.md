# Phase 1 — Noyau

## Vision validée

Noyau remplace le tableur comme système de pilotage partagé du foyer. Il ne doit pas reproduire les feuilles : il doit conserver leur logique fiable tout en réduisant la saisie, les doubles écritures et les ajustements manuels.

Les deux membres du foyer voient la même situation en temps réel, sur mobile et ordinateur. Chaque solde est explicable à partir d’écritures immuables et toute correction reste traçable.

## Constat sur l’existant

Le Google Sheet concentre six domaines cohérents :

1. Budget par enveloppes et journal d’écritures ; les alimentations, dépenses, transferts et ajustements sont actuellement saisis à la main.
2. Répartition mensuelle des revenus ; les charges fixes sont imputées directement, puis le solde finance les charges variables selon une clé calculée par revenu disponible.
3. Trésorerie ; le système compare les soldes théoriques des comptes et espèces avec les soldes réels.
4. Objectifs et projets ; shopping list, priorités, voiture et épargne utilisent les surplus et la capacité mensuelle d’épargne.
5. Dettes et simulations ; voiture, emprunts familiaux et prêt immobilier avec échéancier, remboursement anticipé, économie d’IR et contribution employeur.
6. Vie du foyer ; tâches ménagères partagées, entretien, courses et futurs modules personnels.

### Règles métier à préserver

- Une écriture peut être une alimentation, dépense, correction ou transfert ; un transfert génère toujours deux lignes liées et équilibrées.
- Les enveloppes représentent un budget disponible, pas un compte bancaire. Les comptes représentent le lieu où l’argent est détenu.
- Les charges fixes sont affectées à un membre. La clé des charges variables est calculée après déduction de ses charges fixes : `reste membre / somme des restes`.
- Un scénario est une projection isolée : il ne modifie jamais l’historique réel.
- Un rapprochement bancaire ne réécrit pas l’historique ; il crée un relevé et, si nécessaire, un ajustement explicitement justifié.
- Toute modification significative doit laisser une trace : auteur, date, ancien état, nouvel état, motif.

## Décisions d’architecture

### Choix : Flutter + Supabase

Flutter reste le choix retenu : une base moderne pour Android, iOS, Windows, macOS et Web, avec une excellente cohérence d’interface et de performance. Supabase est préféré à Firebase car PostgreSQL porte naturellement les relations financières, les contraintes, les requêtes analytiques, les transactions atomiques, le contrôle fin des accès et les sauvegardes. Son temps réel couvrira les deux membres du foyer.

Avantages : cohérence forte des écritures, données exportables, SQL adapté aux projections et faible verrouillage fournisseur. Inconvénient : davantage de conception SQL qu’un modèle NoSQL ; c’est précisément le compromis souhaitable pour un système financier durable.

### Application Flutter

- Présentation : Material 3, thèmes clair/sombre, disposition adaptative téléphone / tablette / bureau.
- État : Riverpod, avec providers par cas d’usage et synchronisation temps réel.
- Domaine : entités pures et règles de calcul testées sans Flutter.
- Données : repositories, cache local chiffrable et file d’opérations hors-ligne.
- Navigation : `go_router`, recherche globale et raccourcis clavier sur ordinateur.

Organisation cible :

```text
lib/
  core/          design system, erreurs, sync, format monétaire
  features/
    household/   membres et rôles
    finance/     comptes, enveloppes, écritures, rapprochement
    planning/    tâches, routines, courses
    goals/       priorités, projets, objectifs
    projections/ scénarios de revenus et dette
    insights/    tableau de bord et alertes
```

## Modèle de données initial

| Groupe | Entités principales | Rôle |
|---|---|---|
| Foyer | `households`, `household_members`, `profiles` | isolement des données et rôles owner/member |
| Référentiels | `categories`, `envelopes`, `accounts` | catégories, budgets et lieux de détention |
| Réel | `transactions`, `transaction_splits`, `transfers`, `reconciliations` | registre comptable, ventilation et rapprochement |
| Budget | `budget_periods`, `budget_allocations`, `income_rules` | alimentation mensuelle, charges fixes et clé variable |
| Objectifs | `goals`, `goal_contributions`, `wish_items`, `projects` | voiture, épargne, shopping et priorités |
| Engagements | `debts`, `debt_terms`, `debt_events`, `loan_scenarios` | prêts familiaux, immobilier et simulations |
| Maison | `tasks`, `task_assignments`, `routines`, `maintenance_items` | planification partagée |
| Gouvernance | `audit_events`, `attachments`, `notifications` | historique, justificatifs et rappels |

Les montants sont stockés en `numeric(14,2)`, jamais en flottant. Les états calculés (solde d’enveloppe, trésorerie, prévisions) sont fournis par des vues SQL ou des fonctions transactionnelles. Les index démarrent par `household_id`, puis la date et les clés de filtre usuelles.

## Sécurité et synchronisation

- RLS sur toutes les tables : chaque ligne appartient à un foyer ; seuls ses membres y accèdent.
- Les mutations financières passent par des fonctions SQL transactionnelles pour garantir les écritures liées.
- Realtime par foyer sur écritures, tâches, objectifs et notifications.
- Cache local et file de commandes pour une saisie hors connexion ; synchronisation optimiste, détection de conflit par version et résolution visible.
- Sauvegardes PostgreSQL, exports CSV/PDF, journal d’audit et annulation logique plutôt que suppression définitive.

## Expérience à construire d’abord

1. Tableau de bord : disponible aujourd’hui, santé du foyer, alertes et prochaines actions.
2. Ajout express : une dépense ou un transfert en moins de dix secondes, avec dernière enveloppe mémorisée.
3. Enveloppes : budget, consommé, restant, prévision de fin de mois et alertes utiles.
4. Journal : recherche, filtres, pièces jointes, modification annulative et source de chaque mouvement.
5. Préparation mensuelle : revenus, charges fixes, clé automatique et validation à deux.

Les scénarios de dette, projections avancées, IA et import sont ensuite des modules distincts : ils ne doivent jamais complexifier le geste quotidien.

## Roadmap proposée

### Lot 0 — fondation validée

Schéma Supabase final, authentification, RLS, design system, audit et stratégie hors-ligne.

### Lot 1 — noyau financier quotidien

Membres, comptes, enveloppes, journal, transferts, rapprochement, tableau de bord et temps réel. Import contrôlé de l’historique Google Sheets.

### Lot 2 — budget mensuel et objectifs

Règles de répartition, préparation du mois, enveloppes récurrentes, shopping list, priorités, objectifs et alertes.

### Lot 3 — foyer organisé

Tâches, routines, courses, maintenance, rappels et calendrier partagé.

### Lot 4 — projection et intelligence

Scénarios de revenus, dette / prêt immobilier, trésorerie 3–12 mois, détection d’anomalies, assistant et exports.

## Validation demandée

Avant le Lot 0, valider :

- le périmètre du Lot 1 ;
- les comptes réels à suivre et les catégories d’enveloppes initiales ;
- si la clé variable doit rester identique pour tous les budgets ou pouvoir être personnalisée ;
- si les montants et soldes réels visibles dans le Google Sheet doivent être importés ou seulement servir de référence de migration.

## Extensions validées

- Vue de reste à vivre par personne, après charges directes, contribution variable et engagements.
- Tout revenu mensuel supérieur au salaire prévu est ventilé en salaire prévu et prime ; la prime garde sa source, son bénéficiaire et son affectation.
- Simulateur d'achat avec impact sur voiture, priorités, trésorerie et date d'atteinte des objectifs.
- Alertes d'enveloppe, de rapprochement, d'échéance et de sous-financement.
- Suivi des récupérations, avances et remboursements attendus entre membres ou proches.
- Mode décision pour comparer voiture, remboursement anticipé, épargne et priorités.
- Préparation du mois suivant, proposant les allocations récurrentes et nécessitant la validation des membres.
- Calendrier des engagements : traites, assurances, vignette, vidange, entretien, contrats et fêtes religieuses.
- Vue de patrimoine nette, graphiques, export mensuel PDF et historique motivé de chaque changement.
- Liaison Google Sheet / Excel uniquement en lecture ; une analyse peut proposer un import, mais aucune écriture n'est importée sans validation explicite.
