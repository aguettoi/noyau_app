# Recette manuelle — Budget Intelligence UI

## Préconditions

- utiliser un foyer Sandbox disposant de trois enveloppes ordinaires actives :
  `Courses`, `Transport` et `Épargne` ;
- utiliser un compte ordinaire disposant des fonds nécessaires ;
- créer ou choisir une période dont `starts_on` et `ends_on` couvrent le mois
  de recette ;
- relever les soldes de comptes et d’enveloppes avant la recette.

## Scénario `TEST BUDGET UI`

1. Créer le scénario `TEST BUDGET UI`, le laisser actif.
2. Ajouter `Courses` en règle **Montant fixe** de `2 000 MAD`.
3. Ajouter `Transport` en règle **Pourcentage** de `10 %`.
4. Ajouter `Épargne` en règle **Reste à répartir**.
5. Saisir `10 000 MAD` de ressources et lancer la simulation.

Résultat attendu : Courses `2 000 MAD`, Transport `1 000 MAD`, Épargne
`7 000 MAD`, total `10 000 MAD`, reste `0 MAD`.

## Persistance, validation et application

1. Enregistrer la simulation et vérifier que les soldes réels restent inchangés.
2. Ouvrir le run depuis **Historique** : période, scénario, montants, lignes,
   avertissements et statut `Simulé` doivent être lisibles, sans UUID.
3. Valider le run puis vérifier que les soldes restent inchangés et que le statut
   devient `Validé`.
4. Appliquer le run une seule fois avec un compte de financement ordinaire.
5. Vérifier que le statut devient `Appliqué`, que les enveloppes, le Grand Livre
   et les soldes de comptes sont rafraîchis sans redémarrage.
6. Tenter une seconde application : elle doit être refusée.

## Reporting

1. Contrôler le mode **Mois** contre les mouvements de la période.
2. Contrôler **YTD** du 1er janvier à `ends_on` de la période sélectionnée.
3. Contrôler **LTD** depuis le début des données jusqu’à `ends_on`.
4. Vérifier que le plan affiché utilise le run `applied`, ou le dernier
   `approved` uniquement lorsqu’aucun run appliqué n’existe pour la période.
5. Vérifier qu’une enveloppe négative reste négative et affiche son dépassement.
