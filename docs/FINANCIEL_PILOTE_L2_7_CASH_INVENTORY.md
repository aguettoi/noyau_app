# L2.7 — Inventaire facultatif des espèces par coupures

## Périmètre

`ACC-12` et `HIS-03` sont deux références historiques livrées par une seule extension canonique du constat de solde espèces.

## Avant

- Le montant physique pouvait être saisi directement.
- Aucun détail billets/pièces ni preuve persistée du comptage n'était disponible.

## Après

- La saisie directe reste disponible et suffisante.
- Le mode facultatif par coupures additionne exactement `valeur en centimes × quantité`.
- Le catalogue est orienté devise; MAD couvre 4 billets et 7 pièces.
- Le serveur valide devise, valeur, nature, quantité et égalité avec le montant observé.
- Mode, détail, auteur, date, motif, solde théorique et écart sont conservés sur l'observation canonique append-only.
- Une clé idempotente empêche un retry de créer un doublon.
- Les droits L1 de découverte et de lecture du solde du compte sont réutilisés.

## Invariant financier

Un inventaire est une observation. Il ne crée aucun `FinancialEvent`, transaction, posting, mouvement d'enveloppe, transfert ou compensation. L'auteur du comptage est une preuve d'action, pas l'attribution de responsabilité d'un écart.

## Preuves

- Domaine et calcul : `test/finance/cash_inventory_test.dart`.
- UI et absence de mutation : `test/finance/accounts_reconciliation_ui_test.dart`.
- Contrat migration : `test/finance/l2_7_cash_inventory_migration_contract_test.dart`.
- SQL/RLS : `supabase/tests/l2_7_cash_denomination_inventory.sql`.
- Runtime Sandbox : transaction rollbackée couvrant saisie directe, coupures, idempotence, historique append-only, coupure inconnue, cross-household et invariants financiers.

## Statut

- `ACC-12` : A.
- `HIS-03` : A.
