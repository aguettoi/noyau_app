# Dépendances fonctionnelles

## Graphe directeur

FinancialEvent alimente le Grand Ledger, l’envelope ledger, les obligations et l’historique. Budget Intelligence, obligations, calendrier et FinancialAvailability alimentent ensuite la clôture et le centre À faire. La clôture fiable alimente la projection, puis les rapports.

| Fonction restante | Dépend de | Moteurs à réutiliser | Interdiction |
|---|---|---|---|
| Clôture mensuelle | rapprochements, inventaires, justificatifs, compensations, budget | F2, F3, F4, F6 | Réécrire FinancialEvent ou GL |
| Centre À faire | alertes et navigation source | F6 AppAlert, Dashboard | Second moteur de tâches |
| Régularisation globale | clôture fiable, recommandations, multi-comptes | F3, transferts canoniques | Exécution sans confirmation |
| KPI qualité | actor, occurred_at, created_at, dossiers, pièces | F2C, F3 | Attribution membre sans preuve |
| Récurrents | règles budget, calendrier, historique | F4, F6, F2 | Création automatique d'une dépense |
| Projection J+30/J+90 | budget, récurrents, obligations, financements | FinancialAvailability, Scenarios | Mélange réel/projeté |
| Reporting périodique | clôture et historique fiables | F7 Exports, Dashboard, F5 | Nouveau calcul de solde |
| Emprunt enrichi | financing profile, obligations | F5, Scenarios | Moteur spécifique banque |
| Onboarding | Auth, foyer, comptes, enveloppes, budget | F1 et assistants existants | Foyer technique automatique |
| Offline | RPC idempotentes, conflits, chiffrement | robustesse F7 | Cache local source comptable |
| Confidentialité fine | RLS, Search, Export, Alertes | F1, F7 | Sécurité uniquement UI |

## Chaîne critique

1. R2 définit le mois fiable et clôturé.
2. R3 projette à partir de données fiabilisées.
3. R4 restitue les mêmes sources sans moteur parallèle.
4. R5 prépare l’usage réel et la distribution.
5. R7 ne démarre qu’après décisions offline/confidentialité.
6. R8, P1 et A1/A2 précèdent obligatoirement le cutover final.

## Moteurs backend sans UI et fonctions peu découvrables

- Les moteurs canoniques principaux sont exposés.
- Patrimoine, compensations, programme Budget, runs, scénarios, moyens de paiement, organisation et recherche/export sont moins visibles mais accessibles via Fondation, Dashboard ou paramètres.
- La clôture, le cashflow daté et l’offline n’ont ni modèle complet ni UI : ils doivent être conçus ensemble.
- Les extensions de reporting doivent rester des vues et encodeurs sur les sources existantes.

## Contraintes transversales

- Household-scoped et 1/2/N membres.
- RLS/RPC serveur pour toute sécurité.
- Idempotence pour toute mutation.
- Simulation égale zéro écriture avant confirmation.
- Design System commun et responsive Windows/Web/Android; architecture iOS conservée.
