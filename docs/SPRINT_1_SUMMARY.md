# Sprint 1 — FINANCIEL PILOTE

## Objectifs atteints

- Authentification Supabase et sélection contrôlée du foyer actif.
- Comptes distants avec lecture, création et rafraîchissement Riverpod.
- Conversion des montants MAD en centimes et validation des formulaires.
- Comptes individuels, partagés et foyer avec titulaires relationnels.
- Stockage des titulaires dans `account_holders` pour tous les types de compte.
- Affichage des titulaires réels : `Banque • Ibrahim & Nora • Actif`.
- Résolution des membres via `household_members` et `profiles`, avec le repli
  `display_name`, puis `email`, puis `Membre du foyer`.
- Import CSV Comptes : template, lecture UTF-8, parsing, validation, aperçu,
  décision, idempotence et exécution distante préparée.
- Synchronisation automatique de `profiles` lors de la création d’un utilisateur.

## Architecture finale

```text
Flutter UI
  ↓
Riverpod
  ↓
Repositories
  ↓
Supabase RPC
  ↓
accounts
  ↓
account_holders
  ↓
profiles
```

`ownership_type` exprime uniquement la cardinalité métier :

- `household` : zéro, un ou plusieurs titulaires ; l’interface associe par
  défaut les membres disponibles du foyer ;
- `individual` : exactement un titulaire ;
- `shared` : au moins deux titulaires.

La relation `account_holders` est la source de vérité des titulaires affichés.

## Migrations

- `202607290001_foundations.sql`
- `202607300001_lot0_foundation.sql`
- `202607300002_financial_ledger.sql`
- `202607300003_workbook_import_journal.sql`
- `202607300004_envelope_reporting.sql`
- `202608010001_accounts_import_execution.sql`
- `202608040001_account_ownership.sql`
- `202608040002_auto_profiles.sql`
- `202608040003_unify_account_holders.sql`

## Décisions d’architecture

### `ownership_type`

Il ne porte pas de nom de personne et ne pilote pas l’affichage. Il exprime
uniquement la règle de cardinalité validée par la RPC et le trigger SQL.

### `account_holders`

Chaque titulaire est une relation vers un membre réel du foyer. Les comptes
foyer, individuels et partagés utilisent donc le même modèle relationnel.

### `profiles`

Les noms affichés viennent de `profiles.display_name`, avec repli sur l’e-mail
puis un libellé neutre qui n’expose jamais les UUID.

### `handle_new_user()`

Le trigger `on_auth_user_created` crée ou complète automatiquement le profil
public correspondant à chaque nouvel utilisateur `auth.users`.

### Import idempotent

L’exécution d’import utilise un identifiant d’exécution et une session distante
pour éviter les doublons lors d’une réexécution du même lot.

## Couverture des tests

252 tests Flutter passent pour cette version. Ils couvrent notamment les
comptes distants, les règles de titularité, les formulaires, la conversion MAD,
les imports CSV, les providers et la navigation.

## Dette technique réelle

- L’écran Comptes ne propose pas encore de fiche détaillée, d’édition ni
  d’archivage/suppression depuis l’interface.
- `AccountsPage` et `ImportsPage` concentrent encore plusieurs responsabilités
  d’interface et d’orchestration ; leur découpage est à envisager après le
  Sprint 2, sans perturber la stabilité actuelle.
- La migration `202608040003_unify_account_holders.sql` doit être appliquée sur
  chaque environnement cible avant l’usage des comptes foyer avec titulaires.

## Prochain Sprint

Le Sprint 2 commence par le Grand Livre, source de vérité de toutes les
transactions, enveloppes, budgets, objectifs et indicateurs.
