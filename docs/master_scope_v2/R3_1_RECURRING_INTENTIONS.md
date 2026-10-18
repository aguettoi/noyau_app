# R3.1 — Intentions financières récurrentes et attendu ↔ réalisé

## Contrat

Une intention décrit une opération future attendue. Elle n'est ni un FinancialEvent, ni une transaction GL, ni un mouvement d'enveloppe. R3.1 ne déclenche aucune écriture financière automatique.

Les types V1 sont revenu, dépense et transfert bancaire. Les fréquences sont hebdomadaire, mensuelle et annuelle. Compte, enveloppe et membre sont facultatifs; aucun référentiel fictif n'est créé. Le niveau `certain` ou `estimated` distingue engagement et hypothèse.

## Occurrences et historique

Les occurrences sont matérialisées à la demande dans une fenêtre glissante, limitée côté serveur à 18 mois. L'UI crée initialement quatre mois. Chaque occurrence copie les attributs utiles de la règle. Une modification ultérieure de la règle affecte seulement les générations futures : les occurrences existantes ne sont pas réécrites.

Le statut est dérivé : `expected`, `partially_realized`, `realized`, `ignored` ou `overdue`. Le montant réalisé est la somme des liens confirmés. Il n'existe pas de `remaining_amount` mutable. Une occurrence peut être explicitement ignorée avec un motif obligatoire; cette décision conserve l'acteur et un audit append-only, sans créer d'écriture financière.

## Attendu ↔ réalisé

La vue `recurring_financial_actual_candidates` est un adaptateur read-only sur FinancialEvent et les transactions canoniques. Elle exclut les transactions reversées et ne copie aucune écriture.

Le matching conservateur examine :

- nature économique;
- proximité de date (3 jours par défaut);
- montant (10 MAD ou 1 % par défaut);
- compte source/destination, enveloppe et membre lorsqu'ils sont connus;
- similarité des mots du libellé (0,55 par défaut).

Le score et les raisons sont conservés. Les paiements partiels et fractionnés sont supportés par plusieurs liens vers une occurrence. Un candidat peut être confirmé ou rejeté; le FinancialEvent référencé reste immuable.

Un transfert bancaire récurrent attendu exige deux comptes actifs et distincts du foyer. Il reste une intention : la planification et la matérialisation des occurrences ne déclenchent jamais le transfert réel.

## Provenance et réutilisation

`source_kind/source_id/source_metadata` permettent de référencer une source Budget, financement F5, coût véhicule, obligation, tâche F6 ou clôture R2 sans dupliquer son moteur. R3.1 expose la création autonome manuelle; les adaptateurs automatiques vers ces sources seront ajoutés seulement quand leur règle de synchronisation est explicitement définie.

## Sécurité et concurrence

- RLS household-scoped sur les quatre tables.
- Références membre/compte/enveloppe validées côté serveur.
- Écritures uniquement via RPC SECURITY DEFINER avec `auth.uid()` et membership.
- Clés d'idempotence, contraintes uniques, verrous de transaction et génération `ON CONFLICT DO NOTHING`.
- Realtime activé pour règles, occurrences et liens de rapprochement.

## Détection assistée

La création silencieuse est interdite. Le détecteur historique complet est reporté : son score de périodicité, ses faux positifs et sa validation nécessitent un lot dédié plutôt que de mélanger détection et contrat canonique. R3.1 fournit les modèles et le matcher nécessaires à cette future proposition.

## Limites réservées aux lots suivants

- **R3.2** : projection consolidée foyer/compte/membre/enveloppe et horizons.
- **R3.3** : scheduler, heure locale, rappels, « Pas encore », snooze et notifications.
