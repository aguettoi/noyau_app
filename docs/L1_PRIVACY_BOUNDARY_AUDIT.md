# L1 — état de la frontière de confidentialité (audit de sécurité)

Statut : **incomplet**. Ce document ne certifie aucun mode de compte privé ou de solde masqué. Aucun sélecteur de confidentialité ne doit être exposé avant que les contrats serveur et leur matrice hostile soient complets.

## Contrat retenu

- Trois états demandés : compte et solde visibles ; compte visible, solde masqué ; compte privé.
- Pour un compte détenu par plusieurs membres, le passage vers un état plus restrictif exige l'accord de **tous** les titulaires. Cet arbitrage a été donné le 19 octobre 2026.
- L'appartenance au foyer n'autorise pas par elle-même la lecture d'une donnée privée. Les données sensibles personnelles sont privées par défaut ; tout partage futur doit être explicite, scopé et révocable.
- Les calculs de capacité autorisés peuvent exploiter un montant côté serveur mais ne doivent pas retourner de solde, plancher, delta ou oracle de seuil exploitable par un autre membre.
- Les totaux incomplets ne doivent jamais être présentés comme des totaux du foyer. Les vues, exports, recherche, Realtime, rappels, erreurs, journaux et futurs contrats IA suivent la même audience.

## Surfaces vérifiées sur le Sandbox

Le 19 octobre 2026, la base contenait 101 tables `public`, 163 fonctions `SECURITY DEFINER` publiques (121 exécutables par `authenticated`) et 3 privées. Les lectures des tables `accounts`, `financial_events`, `financial_transactions`, `financial_transaction_lines`, `account_balance_observations`, `envelope_movements` et `budget_scenario_member_incomes` sont aujourd'hui autorisées par appartenance au foyer. Les vues `account_ledger_balances`, `account_theoretical_balances`, `envelope_balances` et `obligation_balances` sont `security_invoker`, mais héritent de ces politiques foyer trop larges pour un compte privé.

L'application lit directement `accounts` (y compris `opening_balance`) et `account_ledger_balances` dans ses providers. Dashboard, FinancialAvailability et trésorerie composent ensuite des montants dans Flutter. L'archive foyer lit des tables entières et le ZIP contient des montants et noms de comptes. Realtime écoute des changements de tables financières : ignorer le payload dans le callback ne signifie pas que le payload n'a pas été envoyé. Les RPC `SECURITY DEFINER` doivent être contrôlées individuellement ; une politique RLS seule n'y suffit pas.

Preuve SQL authentifiée, transaction rollbackée, sur un foyer **technique** à deux membres : le membre non titulaire peut actuellement lire les lignes de **deux** comptes individuels de l'autre membre, leurs champs bruts `opening_balance` et **deux** soldes dans `account_ledger_balances`. C'est un comportement historique de partage foyer, mais il démontre que les futurs modes « solde masqué » et « privé » ne peuvent pas être certifiés sans nouvelle frontière serveur.

Ainsi, ajouter un champ de visibilité puis remplacer le nombre par `****` dans Flutter serait une **faille**, pas une implémentation de PRV-01..07. Il faut d'abord un contrat de lecture serveur expurgé, révoquer/filtrer les lectures brutes, couvrir les références indirectes et les agrégats, puis tester les lectures alternatives et les changements de droits avec identités 1/2/N.

## Frontières legacy établies

`LocalAccountsRepository` et `AccountsController` n'avaient aucun appelant V1 : seul leur ancien test les utilisait. Ils semaient cinq comptes nommés dans `SharedPreferences`, indépendamment de Supabase. Leurs fichiers ont été retirés et remplacés par un test qui interdit la résurgence de cette source locale. Aucune préférence historique n'a été effacée : le produit ne la lit plus.

La matérialisation CSV legacy est désactivée dans l'UI. Le Sandbox refuse à `authenticated` et `anon` l'exécution de `execute_accounts_import`, `import_household_envelopes` et `create_financial_transaction_with_envelopes`. La lecture/prévisualisation CSV reste disponible. Ceci préserve LEG-02 sans migration supplémentaire.

## Ce qu'il reste à démontrer avant L1 PRÊT

1. Modèle d'audience et consentement des cotitulaires, historique audité et révocation atomique.
2. Vues/RPC de lecture minimales pour comptes visibles mais soldes masqués ; aucune exposition de la ligne brute ni du mouvement révélateur pour un compte privé.
3. Agrégats, FinancialAvailability, scénarios, recherche, exports, historique, alertes, Realtime et caches qui n'exposent ni montant ni inférence ; résultat utilisable mais minimal.
4. Primitives de données personnelles sensibles privées par défaut, partage volontaire et révocation serveur ; aucune donnée Cycle fonctionnelle dans L1.
5. Matrice authentifiée de toutes les sorties pertinentes, notamment les `SECURITY DEFINER`, 1/2/N, deux foyers, revocation/reconnexion et payload Realtime.
6. Recette humaine des trois modes, accès du propriétaire, cotitulaires unanimes et absence de fuite chez les autres membres.

Le modèle financier et les données pilotes n'ont pas été modifiés dans cet audit. Ne pas promouvoir PRV-01..07 ni R7-05 en A avant ces preuves.

## Passage 2 — état de reprise

- `LEG-01` et `LEG-02` remplissent désormais indépendamment leurs critères et sont reclassés A dans le contrat V1. Les huit lignes de confidentialité demeurent non-A.
- L'inventaire statique des **121/121** fonctions exposées est conservé dans [L1_SECURITY_DEFINER_INVENTORY.md](L1_SECURITY_DEFINER_INVENTORY.md). Il ne constitue pas encore la classification A–E exigée : les appels indirects et l'audience de chaque retour doivent être vérifiés avant toute révocation ou certification.
- Le test de confirmation Snooze était sensible à la casse du message lors du report après l'heure limite. Le test accepte les deux formulations métier ; le code R3.3 n'a pas été modifié. Suite Flutter : 958 réussis, 3 ignorés.
- Aucun niveau de confidentialité n'est activé et aucune migration L1 n'a été appliquée. Le SQL authentifié de lecture transversale reste une preuve négative bloquante pour PRV-02/03.

## Passage 3 — état intermédiaire, 20 octobre 2026

Le paragraphe « Passage 2 » ci-dessus décrit l'état historique avant implémentation ; il ne décrit plus le Sandbox actuel. Huit migrations L1 additives ont depuis été appliquées. Le modèle de visibilité, le consentement unanime des cotitulaires, les lectures directes expurgées et les dossiers personnels sensibles sont présents. La migration `l1_privacy_activation_gate` retire toutefois l'accès aux RPC de changement de confidentialité : **les modes restrictifs ne sont pas encore activables par les utilisateurs** tant que tous les canaux indirects ne sont pas certifiés.

Tests RED puis GREEN avec identités techniques et rollback : les 39 lignes GL d'un compte caché et leur transaction parente ne sont plus lisibles ; trois résolutions de rapprochement d'un compte devenu privé ne sont plus lisibles ; la RPC `envelope_account_position_snapshot` révélait encore l'identifiant du compte privé et des agrégats malgré la RLS. Cette dernière retourne désormais seulement `{restricted:true,reason:private_account}` lorsqu'un membre ne peut lire tous les comptes de son foyer. Les projections de positions directes héritent des politiques RLS. Le test SQL `l1_derived_read_boundary.sql` couvre ces deux sorties après correction.

Cette correction ponctuelle ne certifie **pas** les autres RPC `SECURITY DEFINER`, les agrégats transverses, FinancialAvailability, recherche, export, Realtime ni les oracles de capacité. En particulier, l'inventaire des 121 fonctions exposées reste syntaxique et non qualifié A–E. L1 demeure PARTIEL, le verrou d'activation doit rester fermé, et aucune ligne PRV-01..07/R7-05 ne doit être promue en A avant la matrice hostile complète.

## Passage 4 — contrôle des privilèges et lectures dérivées

Le changement annoncé par Supabase pour le 30 octobre 2026 impose de ne plus dépendre des privilèges implicites des nouveaux objets `public`. La migration additive `20261020191731_l1_explicit_api_privileges.sql` révoque les privilèges par défaut de `postgres` sur les futures tables, séquences et fonctions, y compris l'exécution future des fonctions par `PUBLIC`. Elle attribue ensuite aux objets L1 déjà créés leurs seules permissions client nécessaires ; `anon` n'en reçoit aucune. Les RPC de changement de visibilité restent révoquées tant que le verrou d'activation est fermé. Une création fictive de table et fonction dans une transaction rollbackée a démontré que ni `anon`, ni `authenticated`, ni `service_role` n'obtiennent un accès implicite. Cela ne constitue pas une reconstruction complète des migrations : aucun environnement PostgreSQL isolé/reproductible n'était disponible, et le Sandbox actif n'a pas été réinitialisé.

Deux lectures `SECURITY DEFINER` ont été reproduites en fuite avec un troisième membre technique non titulaire : le brouillon de position initiale retournait 123,45 MAD d'un compte privé, puis la clôture mensuelle comptait ce compte et exposait un rapprochement dans les tâches. Les migrations additives `20261020192142_l1_invoker_account_read_projections.sql` et `20261020192356_l1_invoker_monthly_close_reads.sql` ont converti respectivement quatre lectures de positions et quatre lectures de clôture en `SECURITY INVOKER`, avec `EXECUTE` limité à `authenticated`. Les tests SQL rollbackés sont verts : le non-titulaire ne voit plus la donnée ou le compte, et le titulaire conserve ses lectures. Un test de la recherche globale confirme également que le compte privé n'apparaît pas chez ce non-titulaire mais reste trouvable par le titulaire. La migration de clôture n'a pas modifié les soldes ni les opérations financières.

La suite Flutter complète (959 succès, 3 tests conditionnellement ignorés), `flutter analyze lib test`, le format, les builds Windows/Web et les quatre tests SQL L1 sont verts à ce stade. Les compteurs pilotes C3/C4B sont inchangés. L'advisor sécurité Supabase signale toujours 116 fonctions `SECURITY DEFINER` exécutables par `authenticated` : il s'agit d'un inventaire de risque, non d'une preuve qu'elles sont toutes vulnérables. En revanche, les agrégats de Dashboard/FinancialAvailability peuvent encore présenter un total partiel comme exhaustif et aucune capacité bornée anti-oracle n'est livrée. La recherche n'est testée ici que pour un compte ; Realtime, export, cache, alertes/deep links et les autres fonctions `SECURITY DEFINER` ne sont pas tous certifiés. **L1 reste PARTIEL ; le verrou d'activation doit demeurer fermé ; aucune ligne PRV-01..07/R7-05 n'est promue.**

## Passage 5 — fuite indirecte bloquante reproduite

Sur le foyer technique à trois membres, une transaction rollbackée a rendu privé un compte dont le troisième membre n'est pas titulaire, puis l'a référencé comme `envelopes.recommended_account_id` d'une enveloppe commune. Ce troisième membre ne voyait pas la ligne `accounts`, mais lisait **encore l'UUID du compte privé** dans `envelopes` (`leaked=true`). La recommandation apparaît également dans la lecture Flutter des enveloppes et dans l'export foyer brut. Ce canal révèle au moins l'existence de ce compte, malgré le mode privé. Le test n'a laissé aucune donnée durable.

Ce défaut ne se résout pas par un masquage Flutter : la colonne est déjà envoyée au client et le `SELECT` sur la table était accordé au foyer. La RLS par ligne ne peut pas masquer seulement cette colonne sans supprimer l'enveloppe commune, ce qui casserait le budget. La migration additive `20261021071225_l1_envelope_recommendation_read_boundary.sql` retire donc la lecture brute des colonnes de recommandation et de leur audit, accorde seulement les colonnes communes nécessaires, puis fournit `list_household_envelopes_safe`. Cette RPC exige un membre actif du foyer, masque le compte/moyen privé au non-titulaire et conserve l'enveloppe commune. La définition libre de recommandation reste côté serveur car elle peut contenir des références de compte ou montants. La lecture Flutter des enveloppes et l'export utilisateur appellent cette projection ; les autres lectures client identifiées n'utilisent que des colonnes non sensibles. Le mutateur historique `set_envelope_recommendation` retournait aussi une ligne brute complète malgré le retrait du `SELECT` ; la migration `20261021071622_l1_safe_envelope_recommendation_mutation.sql` révoque son exécution client et expose un wrapper sans retour de données, qui refuse un compte ou moyen privé inaccessible à l'acteur. La preuve RED puis GREEN est dans `l1_envelope_recommendation_read_boundary.sql`, exécutée avec rollback. **Ce point précis est fermé, mais la matrice des autres références de comptes reste ouverte et le verrou d'activation demeure fermé.**

Le contrôle suivant a reproduit une autre fuite : deux `budget_funding_links` du foyer technique pointaient vers le compte testé ; sous une identité membre non titulaire et un réglage temporaire `private`, la lecture RLS retournait les deux références. Deux politiques `SELECT` permissives se combinaient par **OR** : la politique membre neutralisait le filtre privé. La migration additive `20261021072034_l1_budget_funding_link_privacy.sql` les remplace par une politique conjonctive membre + droit de découverte + droit de lecture financière. Le test transactionnel `l1_budget_funding_link_privacy.sql` démontre 0 référence chez le non-titulaire et la conservation de l'historique chez le titulaire, puis rollback. Ce test ne constitue pas une certification de tous les autres liens et agrégats : le verrou reste fermé.

### Contrat futur assistant

L1 ne livre aucun assistant. Un éventuel assistant doit appeler les mêmes services/RPC d'audience que le client humain avec l'identité de l'utilisateur courant. Il ne doit recevoir ni `service_role`, ni lecture brute des tables sensibles, ni export technique complet. Une réponse dérivée doit respecter la portée visible et les limites anti-inférence ; toute action financière requiert confirmation humaine et primitive canonique. Ce contrat est documentaire tant que l'infrastructure IA et sa preuve automatisée n'existent pas.

## Clôture tentée le 21 octobre 2026 — état toujours partiel

Cinq migrations additives supplémentaires, sans toucher aux quatorze migrations L1 antérieures, ferment quatre chemins reproduits RED puis GREEN sur le foyer technique avec rollback : exécution client de deux fonctions internes, transfert/revenu canonique sur un compte privé non découvert, observation de solde de ce compte et création d'un moyen de paiement qui le référence. Les tests SQL dédiés et les six tests L1 antérieurs sont verts. Le test des fuites de recommandation d'enveloppe et de lien de financement budgétaire reste vert. Le Sandbox compte désormais 134 fonctions `public` exécutables par `authenticated`, dont 115 `SECURITY DEFINER`, et zéro par `anon`.

Le [registre courant des fonctions privilégiées](L1_PRIVILEGED_FUNCTION_CURRENT_REGISTER.md) inventorie 117 fonctions de départ (115 encore exposées et deux internes révoquées). Les 115 exposées restent **non qualifiées individuellement** : des indices statiques de `auth.uid()`, de `search_path` ou de tables ne démontrent ni autorisation correcte ni absence de fuite indirecte. Il serait faux de les promouvoir en catégorie A sans test de comportement. Ce reliquat interdit L1 PRÊT.

Les autres critères de sortie non certifiés sont notamment : agrégats et comparaison par différence (Dashboard, patrimoine, disponibilité financière), capacité bornée anti-oracle, payload Realtime multi-client et révocation sur abonnement déjà ouvert, export partagé, cache après révocation, alertes et deep links, données sensibles sur tous les canaux, matrice hostile finale 1/2/N et reconstruction physique des migrations depuis base vierge. Le client compose encore des montants partiels susceptibles d'être présentés comme totaux ; les abonnements Postgres Changes aux tables financières ne sont pas une projection d'invalidation expurgée. L'absence de fuite prouvée sur une lecture donnée ne prouve donc pas l'ensemble de la frontière.

Le verrou d'activation reste **fermé** : aucune recette utilisateur des modes privés ne doit être lancée avant correction/certification de ces canaux. Aucun FinancialEvent, GL, mouvement d'enveloppe ni donnée C3/C4B pilote n'a été écrit par les tests rollbackés. Sans moteur de base locale isolée disponible, la reconstruction depuis base vierge reste **non exécutée**, et ne saurait être marquée PASS.

## L1.2 — campagne systématique du 21 octobre 2026

La surface privilégiée courante a été extraite du Sandbox et qualifiée signature par signature : **111 fonctions `SECURITY DEFINER` exécutables par `authenticated`, 0 par `anon`, 108 A, 3 B, 0 C, 8 D révoquées au total et 0 non qualifiée**. Les trois B sont les RPC de cutover dont le plan/retour complet doit encore être restreint. Six fonctions internes, anciennes ou supplantées ont perdu leur droit d'exécution client pendant cette passe.

Une capacité privée bornée est livrée : le titulaire crée une intention liée à un objet métier existant et à un montant fixé ; un membre du même foyer obtient seulement `ALLOWED`, `NOT_ALLOWED` ou `REQUIRES_OWNER_ACTION`. Aucun seuil arbitraire, montant maximal, reste ou solde n'est accepté ou retourné. L'intention expire, est idempotente et produit une trace d'évaluation inaccessible directement au client.

Le transport Realtime brut a été remplacé par `household_realtime_invalidations`, projection sans compte, membre, source ni montant. La publication `supabase_realtime` contient uniquement cette table et Flutter ne s'abonne plus directement aux tables financières. Les tests automatiques SQL et Flutter sont verts. La preuve avec deux sessions authentifiées simultanées et révocation sur abonnement déjà ouvert reste à exécuter.

Dashboard et FinancialAvailability excluent les soldes non lisibles et annoncent explicitement que leur total visible est incomplet. Cela ferme la présentation erronée d'un total partiel comme total exhaustif sur ces écrans, sans prétendre certifier tous les agrégats historiques. La matrice hostile détaillée est dans `L1_HOSTILE_MATRIX.md`.

L1 reste **PARTIEL** : export complet, cache/révocation runtime, Realtime multi-client, trois RPC de cutover et reconstruction physique depuis une base vierge restent non certifiés. Le verrou demeure fermé.

## L1 final — audience cutover

Les trois RPC cutover précédemment B sont conservées comme primitives opérateur, mais ne sont plus exécutables par `authenticated`, `anon` ou `PUBLIC`. Elles restent utilisables par un opérateur de migration contrôlé et ne constituent plus une API utilisateur. La réconciliation mathématique finale du registre est 119 signatures suivies = 108 A exécutables + 11 D révoquées, zéro B/C/E et zéro non qualifiée.
