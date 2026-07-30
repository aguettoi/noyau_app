# Programme de développement intégral

## Noyau commun

- Montants en centimes côté Flutter et `numeric(14,2)` côté PostgreSQL.
- Grand livre avec lignes équilibrées, compte, enveloppe, membre, période, motif et audit.
- Périodes mensuelles versionnées ; aucun calcul ne modifie une période clôturée.
- Salaires prévus, salaires réels et primes séparés par membre.
- Règles de répartition et scénarios versionnés et rejouables.

## Finance quotidienne

- Comptes bancaires, espèces, soldes théoriques, saisie réelle et rapprochement.
- Enveloppes importées du référentiel validé, alimentations, dépenses, transferts et récupérations.
- Alertes de dépassement, d'échéance, de rapprochement et de financement.

## Décision et projections

- Shopping list, prios, objectifs voiture et épargne.
- Simulateur d'achat et mode décision.
- Dette familiale et simulateurs d'amortissement mensuels.
- Déduction IR marocaine versionnée par année fiscale et avantage employeur plafonné à 4 % HT.

## Foyer

- Tâches, routines, courses, maintenance, contrats, fêtes et calendrier partagé.
- Répartition selon disponibilités, rappels et historique d'exécution.

## Données et collaboration

- Authentification, rôles, RLS, temps réel, cache hors connexion, résolution de conflit et audit.
- Liaison Sheet/Excel en lecture, proposition de mapping, prévisualisation et import uniquement après validation.
- Graphiques, patrimoine net, PDF/CSV/Excel et synthèse mensuelle.

## Séquence de raccordement

1. Noyau financier et import validé.
2. Budget mensuel, objectifs et simulateurs.
3. Foyer, alertes et calendrier.
4. Synchronisation, export et recette complète sur les données importées.
