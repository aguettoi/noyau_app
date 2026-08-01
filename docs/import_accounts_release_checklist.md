# Checklist de déploiement — import des comptes

## Prérequis

- [ ] La recette non productive décrite dans
  `supabase_import_validation_checklist.md` est entièrement validée.
- [ ] Une sauvegarde vérifiée de la base cible est disponible.
- [ ] Les migrations antérieures sont appliquées dans l'ordre prévu.
- [ ] La migration `202608010001_accounts_import_execution.sql` a été relue et
  approuvée.
- [ ] Les rôles, droits `EXECUTE`, RLS et `SECURITY DEFINER` ont été contrôlés.
- [ ] L'application utilise exclusivement les variables de lancement prévues ;
  aucune clé secrète n'est intégrée au code.
- [ ] Un créneau de déploiement et un responsable de validation sont identifiés.

## Étapes de déploiement

- [ ] Informer les utilisateurs du créneau, si nécessaire.
- [ ] Vérifier une dernière fois que le projet Supabase ciblé est bien celui
  autorisé pour le déploiement.
- [ ] Appliquer uniquement la migration validée via le Dashboard ou la procédure
  d'exploitation approuvée.
- [ ] Vérifier l'enregistrement de la migration et l'absence d'erreur SQL.
- [ ] Contrôler la table `accounts_import_executions`, la signature de la RPC et
  les droits accordés à `authenticated`.
- [ ] Effectuer un appel de contrôle avec un foyer de recette autorisé, sans
  données réelles non nécessaires.
- [ ] Conserver le bouton d'import désactivé tant que la validation fonctionnelle
  de l'application n'est pas explicitement planifiée.

## Stratégie de rollback

- [ ] Si la migration échoue, arrêter le déploiement avant tout raccordement UI.
- [ ] Si la fonction ou les droits sont incorrects, désactiver son exécution pour
  `authenticated` avant correction.
- [ ] Ne pas supprimer de données réelles pour compenser une erreur d'import.
- [ ] Restaurer depuis la sauvegarde uniquement selon la procédure approuvée par
  l'administrateur de la base.
- [ ] Préparer une migration corrective versionnée ; ne jamais modifier une
  migration déjà appliquée à distance.
- [ ] Documenter l'incident, les UUID d'exécution concernés et la décision prise.

## Vérifications après déploiement

- [ ] La RPC accepte un nouveau UUID d'exécution valide.
- [ ] Une seconde requête avec le même UUID retourne `already_processed: true`.
- [ ] Un UUID différent conserve les contraintes de nom des comptes.
- [ ] Les remplacements de `opening_balance`, y compris à zéro, sont exacts.
- [ ] Un échec au milieu d'un lot ne laisse aucun changement partiel.
- [ ] Un non-membre et un utilisateur anonyme sont refusés.
- [ ] Les vues de solde continuent de calculer
  `opening_balance + mouvements du Grand Livre`.
- [ ] Aucun mouvement du Grand Livre n'est créé par l'import de comptes.

## Métriques et signaux à surveiller

- [ ] Nombre d'appels RPC réussis, déjà traités et échoués.
- [ ] Taux de réexécution avec le même UUID.
- [ ] Erreurs de contrainte unique sur `accounts`.
- [ ] Erreurs d'autorisation ou de RLS.
- [ ] Durée des appels d'import et taux de timeout.
- [ ] Nombre de rollbacks SQL et causes associées.
- [ ] Écarts signalés sur les soldes théoriques après import.
- [ ] Volume et ancienneté des lignes `accounts_import_executions` selon la
  politique de conservation des données.

## Critère de clôture

- [ ] Les contrôles fonctionnels, sécurité et données sont validés.
- [ ] Les incidents éventuels sont résolus ou acceptés formellement.
- [ ] La décision de raccorder le bouton d'import est documentée et approuvée.
