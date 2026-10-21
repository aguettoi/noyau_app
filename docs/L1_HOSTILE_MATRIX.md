# L1.2 — matrice hostile de confidentialité

Date de preuve : 21 octobre 2026. Cette matrice complète les tests SQL transactionnels et les tests Flutter. Elle ne remplace pas la recette multi-client qui nécessite plusieurs sessions authentifiées simultanées.

## Résultat automatique

| Acteur / état | Lecture directe | RPC | Agrégat / projection | Recherche | Export existant | Alerte / deep link | Capacité |
|---|---|---|---|---|---|---|---|
| Titulaire / visible | autorisée | autorisée | complète | visible | visible | visible | intention autorisée |
| Titulaire / solde masqué | autorisée au titulaire | autorisée au titulaire | complète pour le titulaire | visible | visible au titulaire | visible au titulaire | intention autorisée |
| Titulaire / privé | autorisée au titulaire | autorisée au titulaire | complète pour le titulaire | visible | visible au titulaire | visible au titulaire | intention autorisée |
| Membre autorisé / visible | autorisée | autorisée | complète | visible | visible | visible | décision bornée |
| Membre non autorisé / solde masqué | montant refusé | retour expurgé | total visible explicitement incomplet | aucun montant | montant absent | aucun payload privé | décision bornée uniquement |
| Membre non autorisé / privé | compte et montant absents | retour expurgé/refusé | total visible explicitement incomplet | absent | identifiant et montant absents sur le chemin certifié | deep link sans autorisation | décision bornée uniquement |
| Administrateur non titulaire / privé | mêmes refus qu'un membre non autorisé | mêmes refus | même contrat incomplet | absent | absent | aucun contournement | décision bornée uniquement |
| Autre foyer | refusé | refusé | absent | absent | absent | absent | refusé |

## Preuves automatiques

- Les tests SQL L1 couvrent les lectures et mutations hostiles, y compris cross-household.
- `l1_sensitive_member_records` couvre privé par défaut, partage explicite et révocation.
- `l1_2_bounded_capability` couvre une intention métier fixe, l'absence de seuil arbitraire, l'idempotence et l'impossibilité de lire le montant privé de l'intention.
- `l1_2_realtime_invalidation` couvre la publication expurgée, l'isolation household et l'absence de colonnes financières. Le test Flutter interdit les abonnements directs aux tables financières.
- Le Dashboard et FinancialAvailability excluent les soldes illisibles et signalent explicitement l'incomplétude.

## Intégration à exécuter

1. Deux sessions authentifiées simultanées : révocation pendant abonnement ouvert et rafraîchissement du membre révoqué.
2. Navigation arrière, deep link et redémarrage après révocation sur Windows et Web.
3. Export household complet avec identités titulaire/non-titulaire après activation réelle des trois modes.
4. Les RPC de cutover `execute_cutover_opening_import`, `get_cutover_opening_run` et `reconcile_cutover_opening_run` restent B jusqu'à restriction de leur plan/retour.

## Conclusion

Automatique : **PASS partiel, aucune fuite critique ouverte sur les canaux testés**. Intégration multi-client, export complet, cutover et cache après révocation restent à certifier. Le verrou d'activation demeure fermé.
