# R2 — clôture mensuelle et fiabilité

Statut : implémenté le 10/10/2026, validation automatisée en cours.

## Sources canoniques réutilisées

- Grand Ledger et comptes pour les positions théoriques.
- Dossiers de rapprochement pour les écarts ouverts.
- Observations de caisse pour les inventaires.
- FinancialEvent et justificatifs privés pour la complétude documentaire.
- Compensations F3 pour les montants encore à verser ou confirmer.
- Journal des enveloppes et flux de transfert canoniques pour toute exécution confirmée.

## Architecture

`monthly_close_periods` conserve l'état mensuel. `monthly_close_events` constitue l'audit append-only des clôtures, dérogations et réouvertures. `monthly_envelope_account_targets` porte la cible mensuelle configurable compte × enveloppe sans recopier un solde.

La fonction `monthly_close_snapshot` calcule les conditions depuis les sources métier. Une clôture refuse tout blocker. Un OWNER peut déroger aux warnings avec un motif obligatoire. Une réouverture est réservée à un OWNER et exige un motif.

Le solveur Dart de régularisation est pur et produit seulement des propositions de transferts minimisées par compensation des surplus et déficits. Il ne crée aucun FinancialEvent.

## UI/UX

La surface Fin de mois est accessible depuis Pilotage. Elle utilise le Design System partagé, une liste responsive, des états loading/error, un score explicable, une checklist guidée, un centre À faire et un contrôle final.

## Limites

- Les KPI par profil restent attribués au foyer tant que les données ne prouvent pas le membre responsable.
- L'exécution des transferts proposés reste volontaire et passe par le flux canonique existant.
- La certification iOS réelle reste P1 faute d'environnement Apple.
