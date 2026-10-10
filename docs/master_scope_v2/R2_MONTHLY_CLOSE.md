# R2 — clôture mensuelle et fiabilité

Statut : partiellement finalisé le 10/10/2026.

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

La surface Fin de mois est accessible depuis Pilotage. Elle utilise le Design System partagé, une liste responsive, des états loading/error, un score explicable, une checklist guidée, un centre À faire et un contrôle final. La réouverture OWNER est désormais exposée avec motif, retour utilisateur et historique. Les catégories du centre ouvrent les surfaces canoniques Comptes, Transactions et Compensations. Les cibles mensuelles compte × enveloppe sont consultables et modifiables avant clôture via le RPC audité.

## Limites

- Les KPI par profil restent attribués au foyer tant que les données ne prouvent pas le membre responsable.
- Le snapshot ne fournit que des compteurs : le centre À faire ouvre le bon module, mais pas encore l'objet précis.
- Il n'existe pas encore de position canonique compte × enveloppe. Les ledgers donnent un solde par compte et un solde par enveloppe, sans matrice de propriété croisée complète. Le solveur pur ne doit donc pas être alimenté avec une position inventée et aucune confirmation financière R2C n'est exposée.
- La certification iOS réelle reste P1 faute d'environnement Apple.
