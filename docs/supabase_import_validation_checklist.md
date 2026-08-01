# Checklist de validation Supabase — import des comptes

Cette procédure s'exécute uniquement sur un environnement Supabase non productif,
isolé de la base principale. Ne pas exposer de clés, jetons ou chaînes de connexion
dans les comptes rendus.

## 1. Préparation

- [ ] Identifier le projet Supabase de test ou de préproduction et confirmer qu'il
  n'est pas la production.
- [ ] Vérifier que les testeurs disposent de deux utilisateurs authentifiés : un
  membre du foyer de test et un utilisateur non membre.
- [ ] Prévoir un foyer de test vide, exclusivement dédié à cette recette.
- [ ] Relever les identifiants de test uniquement dans un espace sécurisé ; ne pas
  les enregistrer dans le dépôt.

## 2. Migrations à appliquer, dans cet ordre

- [ ] `202607290001_foundations.sql`
- [ ] `202607300001_lot0_foundation.sql`
- [ ] `202607300002_financial_ledger.sql`
- [ ] `202607300003_workbook_import_journal.sql`
- [ ] `202607300004_envelope_reporting.sql`
- [ ] `202608010001_accounts_import_execution.sql`

Ne pas appliquer de migration supplémentaire sans revue. Vérifier que chaque
migration est enregistrée comme appliquée avant de poursuivre.

## 3. Vérifications SQL de structure

- [ ] La table `accounts` possède `household_id`, `name`, `kind`,
  `opening_balance`, `archived_at`, `created_at` et `updated_at`.
- [ ] La contrainte unique `(household_id, name)` est présente sur `accounts`.
- [ ] La table `accounts_import_executions` existe avec les colonnes
  `household_id`, `id`, `status`, `result`, `created_by`, `created_at` et
  `completed_at`.
- [ ] La clé primaire `(household_id, id)` existe sur
  `accounts_import_executions`.
- [ ] L'index `accounts_import_executions_household_created_idx` existe.
- [ ] La fonction `execute_accounts_import(uuid, uuid, jsonb)` existe et retourne
  `jsonb`.
- [ ] La fonction est `SECURITY DEFINER` et définit `search_path = public`.
- [ ] Le rôle `authenticated` a le droit `EXECUTE` sur la fonction.
- [ ] Les rôles `public` et `anon` ne disposent pas de ce droit.
- [ ] Les tables `financial_transactions` et `financial_transaction_lines` restent
  inchangées : l'import ne crée pas d'écriture du Grand Livre.
- [ ] La vue `account_theoretical_balances` conserve la formule
  `opening_balance + mouvements du Grand Livre`.

## 4. Jeux de données de recette

Créer uniquement dans le foyer de test :

- [ ] Un compte existant `Compte existant` avec `opening_balance = 100.00`.
- [ ] Un utilisateur membre de ce foyer.
- [ ] Un utilisateur authentifié non membre de ce foyer.
- [ ] Deux UUID d'exécution distincts : un pour le succès et un pour l'échec.
- [ ] Un lot valide contenant `Compte nouveau` et, si besoin, une mise à jour de
  `Compte existant`.
- [ ] Un lot invalide dont la seconde opération contient un `kind` non autorisé,
  afin de provoquer un rollback après une première opération valide.

## 5. Tests fonctionnels de la RPC

- [ ] Appeler la RPC avec un UUID inédit et un lot valide.
- [ ] Vérifier la création de chaque compte attendu et la valeur exacte de
  `opening_balance` en dirhams à partir des centimes fournis.
- [ ] Vérifier la création d'une seule ligne `accounts_import_executions` avec le
  statut `completed`.
- [ ] Vérifier que la réponse contient `already_processed: false`.
- [ ] Exécuter un lot avec un compte existant et la politique « ignorer » : ne pas
  envoyer d'opération de remplacement et vérifier que son solde reste inchangé.
- [ ] Exécuter une opération `replace_opening_balance` positive et vérifier le
  nouveau solde.
- [ ] Exécuter une opération `replace_opening_balance` à `0` et vérifier que le
  solde devient exactement `0.00`.
- [ ] Vérifier qu'un solde CSV absent ne génère aucune opération de remplacement.
- [ ] Exécuter le même lot avec un nouvel UUID : le conflit de nom doit échouer
  explicitement, sans contournement silencieux.

## 6. Idempotence et concurrence

- [ ] Réappeler le lot valide avec le même UUID d'exécution.
- [ ] Vérifier l'absence de compte supplémentaire, de second changement de solde
  et de seconde ligne d'exécution.
- [ ] Vérifier que la réponse contient `already_processed: true`.
- [ ] Lancer deux appels concurrents avec le même UUID et le même lot.
- [ ] Vérifier qu'un seul lot produit des changements et que l'autre réponse est
  reconnue comme déjà traitée.

## 7. Rollback et reprise

- [ ] Exécuter le lot invalide avec un UUID inédit.
- [ ] Vérifier qu'aucun compte de la première opération n'a été créé.
- [ ] Vérifier qu'aucune mise à jour de `opening_balance` n'a subsisté.
- [ ] Vérifier qu'aucune exécution réussie n'est conservée avec cet UUID.
- [ ] Corriger le lot, le réessayer avec le même UUID et vérifier qu'il peut être
  exécuté normalement.

## 8. Tests RLS et isolation par foyer

- [ ] Avec le membre du foyer, vérifier qu'un import ciblant son foyer réussit.
- [ ] Avec le non-membre, appeler la RPC pour ce même foyer et vérifier le refus.
- [ ] Vérifier qu'aucune donnée du foyer n'a changé après ce refus.
- [ ] Tester sans session authentifiée et vérifier le refus.
- [ ] Vérifier qu'un membre d'un autre foyer ne peut ni lire ni utiliser les
  exécutions du foyer de test.

## 9. Nettoyage et décision de mise en production

- [ ] Supprimer uniquement le foyer de test et les données créées pour la recette,
  conformément à la politique de l'environnement non productif.
- [ ] Conserver les objets de schéma appliqués ; ne pas supprimer la fonction ni la
  table d'exécutions.
- [ ] Consigner les résultats sans données sensibles.
- [ ] Obtenir la validation métier, sécurité et base de données avant toute
  application sur la production.
