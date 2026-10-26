# FINANCIEL PILOTE — plan d'exécution du Lot 2

Baseline : `02de6d2728522c8561611f994a670e01ae13c676`, 22 octobre 2026.

Ce document planifie uniquement l'ancien « Lot 1 — Décision financière, qualité mensuelle, reporting et restauration canonique », désormais nommé **Lot 2** puisque L1 désigne le socle de confidentialité. Il ne développe aucune fonction, ne crée aucune migration et ne modifie aucune donnée.

## 1. Périmètre strict

À sa baseline, le Lot 2 contenait **28 fonctions historiques** non-A : B=18, C=9 et D=1. Aucun ID extérieur à cette baseline post-L1 n'est ajouté; les livraisons L2 mettent ensuite chaque ligne à jour sans réécrire cet inventaire initial.

### Matrice des fonctions

| ID | Domaine | Fonction | Statut | Manque exact | Backend existant | Frontend/tests existants | Dépendances | Taille | Confidentialité | 1/2/N | GL/comptabilité | Enveloppes | C3/C4B |
|---|---|---|:---:|---|---|---|---|:---:|---|---|---|---|---|
| HID-01 | Budget | Définition de déclencheur de scénario | D | `trigger_type/definition` sans règle utilisable | Colonnes Budget Intelligence | Non exposé; aucun test UI | Budget, R3.3 | S | Ne pas révéler un déclencheur privé par alerte/erreur | Règles par foyer et acteurs N | Projection seulement jusqu'à action confirmée | Peut cibler le budget, sans mouvement automatique | Invariants stricts |
| REC-X3 | Récurrents | Adaptateurs Budget/F5/F6 | B | Sources spécialisées non synchronisées | Domaine R3.1 | Pas d'adaptateur automatique ni action | Budget, F5, F6 | M | Occurrences filtrées côté serveur | Sources et destinataires N | Zéro écriture lors de la matérialisation attendue | Aucun mouvement | Invariants stricts |
| R3-02 | Prévision | Détection assistée des récurrents | C | Historique présent, détecteur absent | `financial_event_history` | Transactions; tests portabilité | Historique | M | Historique visible seulement selon droits | Détection par membre/foyer autorisé | Read-only | Read-only | Invariants stricts |
| CAS-X1 | Trésorerie | Scénario alternatif interactif | B | Variantes datées non sélectionnables | Moteur cash-flow | Écran sans choix complet; tests domaine | Scénarios | M | Résultats non inférentiels | Contributions N | Simulation, zéro écriture | Simulation seulement | Invariants stricts |
| BUD-10 | Budget | Prévu versus réel | B | Présentation des écarts incomplète | Analyse mensuelle, reporting enveloppes | Budget/Dashboard; tests calcul | Ledgers | M | Agrégats visibles seulement | Ventilation N | Lecture des ledgers | Lecture Envelope Ledger | Invariants stricts |
| R2-09 | Cycle mensuel | KPI rapprochement | B | Provider/KPI incomplet | Cas de rapprochement | Dashboard; tests métriques | Rapprochements | S | Masquer comptes et écarts privés | Responsable optionnel/N | Lecture, aucune régularisation implicite | Neutre | Invariants stricts |
| R2-10 | Cycle mensuel | Santé des justificatifs | B | Règles et KPI globaux absents | Pièces FinancialEvent | Qualité; tests F2C | FIN-10 | S | Pièces et métadonnées autorisées seulement | Actor/member N | Lecture | Neutre | Invariants stricts |
| R2-11 | Cycle mensuel | Responsabilité foyer/non attribué | B | Contrat nullable et restitution à finaliser | Actor/holder/assignee | Modèles F2/F3/F6; tests partiels | R2-08/09 | S | Pas de déduction d'identité privée | Foyer, membre ou non attribué; N | Lecture | Neutre | Invariants stricts |
| ALT-X3 | Rappels | Seuils enveloppes/échéances | B | Sources canoniques et UI de règle manquent | Alertes F6/R3.3 | Types limités; tests rappels | Envelope Ledger, F6 | M | Alerte sans montant interdit | Préférences personnelles N | Détection seulement | Lecture | Invariants stricts |
| OBL-05 | Dettes/créances | Échéances | B | Dates présentes, composition globale absente | Obligations et calendrier | Dette/calendrier; tests organisation | Calendrier | M | Échéances filtrées | Parties/membres N | Lecture obligation | Neutre | Invariants stricts |
| PLAN-07 | Objectifs/Shopping/PRIOS | Surplus et bonus | B | FinancialAvailability à étendre | Planification F4 | Préparer mois; tests disponibilité | Budget, scénarios | M | Réponse bornée, sans révéler solde privé | Revenus exceptionnels par membre N | Simulation/read-only | Respect Épargne versus primes | Invariants stricts |
| PLAN-08 | Objectifs/Shopping/PRIOS | Arbitrage décisionnel transversal | B | Briques séparées non orchestrées | F4/F5/Scenarios | Pages patrimoine/PRIOS | F4, F5 | L | Comparaisons anti-inférence | Objectifs/participants N | Aucune écriture avant confirmation | Lecture/simulation | Invariants stricts |
| WLT-05 | Patrimoine | Échéancier et remboursement anticipé | B | Comparaison durée/échéance à compléter | Financing F5 | Financement; tests modèles | Scenarios | L | Financement privé filtré | Titulaires N | Simulation, paiement réel canonique séparé | Neutre | Invariants stricts |
| WLT-06 | Patrimoine | Logement, aide, fiscalité, employeur | B | Paramètres/versionnement et restitution à étendre | F5A/F5B | Panneaux logement; tests modèles | F5A | L | Données d'actif/avantage selon droits | Propriétaires et bénéficiaires N | Projeté ≠ réel | Neutre | Invariants stricts |
| WLT-08 | Patrimoine | Historique de valeur nette | B | Série consolidée limitée | Valorisations, Wealth provider | Patrimoine; tests page | GL, obligations | M | Aucun total permettant une soustraction privée | Propriété N | Lecture GL/obligations | Neutre | Invariants stricts |
| R4-02 | Restitution | Excel structuré quatre feuilles | B | Pack métier non structuré | Encodeur XLSX F7 | Export; tests encodeurs | Ledgers, obligations | M | Export = contrat de lecture courant | Membres/acteurs N | Lecture | Lecture | Invariants stricts |
| R4-03 | Restitution | PDF périodique | B | PDF métier périodique incomplet | Encodeur PDF F7 | Export; tests encodeurs | R2, Dashboard | M | Même visibilité que l'écran | Filtres N | Lecture | Lecture | Invariants stricts |
| R4-04 | Restitution | PowerPoint | C | Générateur absent | Aucun | Aucun | R4-03 | L | Aucun contenu privé non autorisé | Restitution N | Lecture | Lecture | Invariants stricts |
| R4-05 | Restitution | Rapport de clôture | A | Rapport métier mensuel exploitable, états réalisé/importé et qualité de clôture | `business_reporting.dart`; `reporting_provider.dart` | Onglet Rapports & timeline; 7 tests L2.5; SQL/RLS | R2, L1, L2.4 | — | Sources filtrées serveur, sans total privé reconstitué | Neutre 1/2/N | Lecture du snapshot et faits canoniques | Lecture | Livré L2.5 |
| R4-06 | Restitution | Bilan annuel N/N-1 | C | Vue multi-période et exports incomplets | Historique Dashboard/ledgers | Pilotage partiel; tests Dashboard | F2, F5 | L | Anti-inférence entre périodes | Filtres N | Lecture | Lecture | Invariants stricts |
| R4-07 | Restitution | Échéancier global | B | Échéanciers objets non composés | Obligations et financements | Rapports partiels; tests Wealth | F5 | M | Exclure échéances interdites | Parties N | Lecture | Neutre | Invariants stricts |
| R4-08 | Restitution | Simulateur emprunt complet | B | Comparaison d'offres/paramètres à étendre | Moteur financing F5 | Financements; tests modèles | Scenarios | L | Hypothèses privées non exposées | Emprunteurs N | Simulation seulement | Neutre | Invariants stricts |
| R4-09 | Restitution | Reconstruction sauvegarde | C | Export présent, restauration certifiée absente | Export foyer F7 | Import/Export; tests portabilité | F7, sécurité L1 | L | Environnement isolé et droits restaurés | Foyer N | Aucune action sur pilote | Aucune action sur pilote | Comparaison, jamais mutation |
| R4-10 | Restitution | Timeline significative | A | Timeline déterministe distincte de l'historique exhaustif, provenance et marquage personnel | FinancialEvent, clôture, obligations/financements, historique analytique | Onglet Rapports & timeline; `timeline_significance_marks`; tests Flutter + SQL/RLS | Reporting, L1 | — | Significatif ne change jamais l'audience | Marquage personnel 1/2/N | Lecture + métadonnée personnelle | Lecture | Livré L2.5 |
| EXP-X1 | Exports | Export fiscal logement | C | Restitution absente | Modèles F5B | Panneau logement; aucun test export | F5B, R4 | M | Propriétaire/foyer autorisé seulement | Propriétaires N | Lecture des hypothèses versionnées | Neutre | Invariants stricts |
| EXP-X2 | Exports | Historique net exportable | B | Série prouvée non exportée | Wealth provider | Patrimoine; tests page | F5A, Export | M | Pas de net worth reconstituant un privé | Propriétaires N | Lecture | Neutre | Invariants stricts |
| ACC-12 | Comptes/espèces | Inventaire par coupures | A | Livré L2.7 | Observation canonique enrichie | Compte espèces, total ou coupures | ACC-02 | S | Droits du compte | Caisses/observateurs N | Observation sans écriture | Aucun mouvement | PASS L2.7 |
| HIS-03 | Finance | Comptage espèces par coupures | A | Livré L2.7 | Même extension canonique | Historique du constat | ACC-12 | S | Identique ACC-12 | Identique ACC-12 | Aucun second moteur | Aucun mouvement | PASS L2.7 |

`ACC-12` et `HIS-03` restent deux références historiques mais une seule livraison technique.

## 2. Moteurs canoniques à préserver

| Moteur | Source de vérité | Lectures | Écritures autorisées | RPC/primitives canoniques | Risque de duplication |
|---|---|---|---|---|---|
| FinancialEvent | `financial_events` | Historique autorisé, événements source | RPC métier atomique seulement | RPC `create_*_event`, reversals canoniques | Élevé si rapport/simulation crée un événement |
| GL double-entry | `ledger_transactions` + `ledger_postings` | Soldes et historique filtrés | Postings équilibrés via primitives financières | Transactions/postings créés par RPC canoniques | Critique : aucun solde parallèle |
| Envelope Ledger | `envelope_movements` | Soldes et mouvements enveloppes | Transfert/allocation/régularisation explicites | Primitives F2/R2 certifiées | Critique : transfert d'enveloppe ≠ bancaire |
| Obligations | Tables obligations + règlements réels | Capital restant, échéances, parties | RPC obligation/règlement canonique | Primitives obligations existantes | Élevé : ne pas dupliquer la dette dans F5/reporting |
| Budget Intelligence | Scénarios, versions, règles, runs et snapshots | Budget applicable et répartitions | Sauvegarde/approbation/application explicite | `prepare_budget_period_v2`, `save_*budget_run`, `approve_*`, `apply_*` | Élevé : aucun calcul concurrent dans le reporting |
| FinancialAvailability | Domaine/provider F4 | Soldes autorisés, engagements, planchers | Aucune mutation financière | Calcul déterministe et capacité bornée L1 | Élevé : ne pas recalculer la capacité localement |
| Projections/cash-flow | `cashflow_projection` + sources R3/F5/Budget | Flux datés attendus et scénarios | Sélection d'hypothèses uniquement | Provider/moteur cash-flow existant | Élevé : simulation ≠ événement réel |
| Scenarios | Budget Scenarios et versions historisées | Scénario applicable par période | Création/version/activation explicite | Repository/RPC Budget existants | Élevé : préserver snapshots mensuels |
| Objectives/PRIOS/Shopping | Tables et providers F4 | Besoins, plans, priorités | Mutations propres aux objets; financement séparé | Primitives existantes des modules | Moyen : orchestration, pas fusion des moteurs |
| Patrimoine/financement | Assets, valuations, investments, financing profiles | Valeur nette, échéanciers, hypothèses | Mutations F5; flux réels reliés à FinancialEvent | Actions Wealth/F5 existantes | Critique : actif, compte et obligation non doublés |
| Clôture mensuelle | Runs/snapshots R2 et positions compte×enveloppe | État figé, anomalies, cible versus réel | Confirmation canonique idempotente | Primitives R2 certifiées | Critique : un rapport ne rouvre pas un snapshot |
| Réconciliation | Observations + dossiers de rapprochement | Solde réel/théorique et écarts | Observation; régularisation distincte confirmée | `record_account_balance_observation`, régularisation canonique | Critique : observer ne régularise jamais |

## 3. Restauration canonique : cinq concepts distincts

1. **Sauvegarde/export utilisateur** : production de fichiers lisibles/portables selon les droits courants. Elle relève de L2.6 mais ne prouve pas une restauration.
2. **Restauration fonctionnelle de données** : reconstruction contrôlée d'un foyer depuis une archive canonique, dans un environnement isolé, avec contrôles d'intégrité, relations, acteurs, confidentialité et idempotence. C'est `R4-09`, livré par L2.8. Aucun bouton libre-service V1 n'est requis.
3. **Reconstruction technique depuis migrations** : base vierge → migrations → schéma/RLS/grants/tests. C'est une dette de certification runtime L1, différée après P1; elle ne bloque pas les développements L2.
4. **Reprise après incident** : procédures d'exploitation, sauvegardes du service, RPO/RTO et restauration d'infrastructure. À certifier dans les gates techniques A1/P1, distinctement de R4-09.
5. **Import/cutover Google Sheet** : gel de la source réelle, import final, rapprochement et acceptation. Il reste dans le gate CUT après A1/A2 et ne fait pas partie du développement L2.

## 4. Reporting V1 historique, sans nouveau KPI

| Restitution historique | Source canonique | Données/période/filtres | État actuel | Manque | Confidentialité/export |
|---|---|---|---|---|---|
| Prévu/réel | Budget snapshots + ledgers | Mois/scénario, enveloppe, membre autorisé | Calcul présent | Présentation et explication | Pas de total privé par différence; export via L2.6 |
| KPI rapprochement | Observations + dossiers | Compte/période autorisés | Dossiers/alertes présents | Provider et synthèse | Compte masqué/privé respecté |
| Santé justificatifs | Attachments FinancialEvent | Période, type, acteur autorisé | Pièces unitaires | Règles et KPI | Aucun contenu/nom de fichier interdit |
| Responsabilité | Actor/holder/assignee | Foyer, membre ou non attribué | Concepts présents | Contrat nullable/restitution | Pas de déduction sur un membre privé |
| Valeur nette historique | GL + valorisations + obligations | Périodes réellement disponibles | Série limitée | Consolidation prouvée | Aucun résiduel révélant un compte privé |
| Rapport clôture | Snapshot mensuel figé | Mois/scénario | Absent | Vue/rapport explicable | Respect du snapshot et des audiences |
| Bilan annuel N/N-1 | Ledgers + patrimoine | Année et comparaison N-1 | Partiel | Vue et export | Anti-inférence inter-périodes |
| Échéancier global | Obligations + financing | Horizon, partie/actif autorisé | Par objet | Composition globale | Filtrage avant agrégation |
| Timeline significative | Historique canonique | Critères déterministes + marquage manuel | Historique exhaustif | Sélection distincte | Marquage ne change pas la visibilité |
| Excel/PDF/PPTX | Contrats de lecture ci-dessus | Période et filtres identiques à l'écran | XLSX/PDF génériques; PPTX absent | Packs métier | Export jamais plus large que l'utilisateur |
| Fiscal logement | Paramètres F5B versionnés | Période/règle/version | Absent | Restitution dédiée | Propriétaire/partage autorisé |

## 5. Financement et simulations

Les mathématiques restent dans F5 : financement générique, échéancier, coût/marge, remboursement anticipé, stratégies durée/échéance, actifs et obligations. L2 complète seulement : comparaison d'offres et trajectoires (`R4-08`), échéancier/anticipation (`WLT-05`), paramètres logement/aides/fiscalité/employeur versionnés (`WLT-06`), export fiscal (`EXP-X1`) et composition globale (`R4-07`).

Toute simulation reste read-only. Un paiement réel passe par FinancialEvent/GL et le règlement d'obligation canonique. Murabaha/participatif conserve son vocabulaire propre; aucune hypothèse de prêt à intérêt obligatoire. Aucun taux, plafond ou règle fiscale n'est hardcodé.

## 6. Qualité mensuelle et décisions historiques

La qualité mensuelle compose clôture, pré-clôture R3.3, réconciliation, pièces, responsabilités, obligations, occurrences attendues, Budget Intelligence, soldes réels/théoriques et positions compte×enveloppe. Un contrôle détecte/propose/navigue; il ne crée aucune écriture.

- **Épargne** : enveloppe permanente; sa règle pilote Arreda n'est jamais hardcodée. Seuls les reliquats historiquement autorisés peuvent l'alimenter, via traitement mensuel explicite, idempotent et historisé. Un mouvement d'enveloppe n'implique pas un transfert bancaire.
- **Reste épargne / primes** : revenus variables hors budget récurrent; chaque bénéficiaire conserve physiquement sa prime sur son propre compte. Aucun montant mensuel fixe ni répartition permanente inventée.
- Tout report au mois suivant provient du moteur/snapshot canonique; un rapport ne modifie pas le mois clos.

## 7. Sous-lots d'exécution

### L2.1 — Contrats temporels, sources attendues et règles explicables

- **Objectif** : stabiliser les contrats communs de flux datés, déclencheurs, détection read-only, échéances et alertes avancées.
- **Fonctions** : `HID-01`, `REC-X3`, `R3-02`, `CAS-X1`, `ALT-X3`, `OBL-05`.
- **Statuts visés** : D/B/C/B/B/B → A.
- **Dépendances** : R3.1/R3.2/R3.3, Budget, F5/F6, obligations, L1.
- **Migrations probables** : aucune si les colonnes existantes suffisent; additive seulement pour idempotence/source/audit démontrée.
- **Backend/frontend** : adaptateurs sans doublon, contrats datés; configuration et explication dans les écrans existants.
- **Confidentialité/1/2/N** : filtrage serveur avant composition, alertes personnelles, acteurs et membres N.
- **Tests** : source unique, dates/timezone, retry/idempotence, scénario alternatif sans écriture, cross-household, valeurs privées absentes.
- **C3/C4B** : compteurs financiers et décisions strictement identiques; fixtures rollbackées.
- **Sortie** : chaque source produit une occurrence/projection unique, traçable et explicable; aucune écriture financière automatique.
- **Taille/risque** : L; risque élevé de doublon temporel.

### L2.2 — Qualité mensuelle et arbitrage décisionnel

- **Objectif** : rendre actionnables les écarts mensuels et l'arbitrage sans recalculer les moteurs.
- **Fonctions** : `BUD-10`, `R2-09`, `R2-10`, `R2-11`, `PLAN-07`, `PLAN-08`.
- **Statuts visés** : six B → A.
- **Dépendances** : L2.1 pour les sources datées; Budget, réconciliation, FinancialAvailability, Scenarios, F4/F5.
- **Migrations probables** : aucune; métadonnée additive uniquement si une décision/audit ne peut être représenté.
- **Backend/frontend** : providers d'analyse consolidés; surfaces Budget/Qualité/Scenarios existantes enrichies.
- **Confidentialité/1/2/N** : agrégats anti-inférence, responsabilité foyer/membre/non attribué, capacité bornée.
- **Tests** : écarts, pièces, rapprochements, surplus, primes, Épargne, arrondis, inconnus, 1/2/N, zéro écriture de simulation.
- **C3/C4B** : snapshots, soldes, obligations et décisions inchangés.
- **Sortie** : chaque écart est expliqué et navigable; aucune action implicite; arbitrages utilisent Scenarios/FinancialAvailability.
- **Taille/risque** : L; risque critique d'agrégat privé ou de mélange réel/projeté.

### L2.3 — Financement et comparaison de simulations

- **Objectif** : compléter le moteur F5 sans moteur concurrent.
- **Fonctions** : `WLT-05`, `WLT-06`, `R4-08`.
- **Statuts visés** : trois B → A.
- **Dépendances** : F5, obligations, Scenarios, FinancialAvailability.
- **Migrations probables** : paramètres/versionnement additifs seulement s'ils manquent réellement.
- **Backend/frontend** : réutilisation de Financing; comparaison d'offres, durée/échéance, coût/marge et avantages paramétrables.
- **Confidentialité/1/2/N** : financements/actifs visibles selon titulaires; propriétaires multiples.
- **Tests** : classique/murabaha, échéancier, anticipation, fiscalité versionnée, zéro écriture, arrondis et comparaison.
- **C3/C4B** : aucune dette, obligation ou écriture pilote créée.
- **Sortie** : simulations complètes, explicables et read-only; flux réels restent séparés.
- **Taille/risque** : L; risque élevé de double dette ou vocabulaire faux.

### L2.4 — Patrimoine historique et échéancier consolidé

**État : VALIDÉ — implémenté sur la base `b58960bb69d69da9b1ea10d006e4fa881f02fcd0`.**

Le lot compose désormais un read model unique et réutilisable : points
patrimoniaux datés et qualifiés, comparaison N/N-1 seulement lorsque les
composantes sont complètes, échéancier consolidé (obligations, financements,
occurrences attendues) avec déduplication par source économique, et export CSV
de la même série. Une période dépourvue d'historique de liquidités/passifs est
explicitement partielle : aucune valeur actuelle ou projetée n'est recopiée
dans le passé. Aucune migration ni écriture financière n'est introduite.

- **Objectif** : composer les séries et échéances déjà prouvées.
- **Fonctions** : `WLT-08`, `R4-06`, `R4-07`, `EXP-X2`.
- **Statuts visés** : B/C/B/B → A.
- **Dépendances** : L2.1, L2.3, GL, obligations, valorisations.
- **Migrations probables** : aucune série fabriquée; snapshots additifs seulement si justifiés par une date réelle.
- **Backend/frontend** : agrégateur de lecture canonique, vues Patrimoine/Rapports, export net.
- **Confidentialité/1/2/N** : suppressions/agrégations anti-inférence par audience; multi-propriétaires.
- **Tests** : absence de double comptage, périodes sans données, N/N-1, échéances fusionnées, exports filtrés.
- **C3/C4B** : totaux de référence inchangés.
- **Sortie** : historique et échéancier reproductibles uniquement depuis données disponibles.
- **Taille/risque** : L; risque critique d'inférence et double comptage.

### L2.5 — Rapports métier et timeline significative

- **Objectif** : figer les modèles de rapport indépendamment des formats de fichier.
- **Fonctions** : `R4-05`, `R4-10`.
- **Statuts visés** : deux C → A.
- **Dépendances** : L2.2 et L2.4.
- **Migrations probables** : métadonnée additive de marquage significatif si absente; aucune copie des événements.
- **Backend/frontend** : read models clôture/timeline; écrans de consultation et marquage/démarquage.
- **Confidentialité/1/2/N** : significatif ne modifie jamais l'audience; rapport filtré avant agrégation.
- **Tests** : critères déterministes, marquage, révocation, snapshot figé, redémarrage, multi-membre.
- **C3/C4B** : FinancialEvent/GL/enveloppes inchangés; métadonnées de test rollbackées.
- **Sortie** : rapport clôture et timeline distincte de l'historique exhaustif, explicables et stables.
- **Taille/risque** : M; risque élevé de réécriture historique.

### L2.6 — Formats de restitution et export fiscal

- **Objectif** : encoder les read models stabilisés, sans logique métier dans les encodeurs.
- **Fonctions** : `R4-02`, `R4-03`, `R4-04`, `EXP-X1`.
- **Statuts visés** : B/B/C/C → A.
- **Dépendances** : L2.3–L2.5.
- **Migrations probables** : aucune.
- **Backend/frontend** : pack XLSX quatre feuilles, PDF périodique, PPTX, export fiscal logement; surface Export existante.
- **Confidentialité/1/2/N** : même contrat de lecture que l'écran; métadonnées et fichiers temporaires inclus dans le contrôle.
- **Tests** : contenu/structure, périodes, caractères, Web/Windows, absence d'identifiants interdits, exports 1/2/N.
- **C3/C4B** : lecture seule.
- **Sortie** : formats reproductibles, ouvrables et strictement cohérents avec les rapports.
- **Taille/risque** : L; risque élevé de fuite par fichier.

### L2.7 — Comptage espèces facultatif par coupures

- **Statut au 25/10/2026** : livré et certifié (`ACC-12` + `HIS-03` → A).
- **Objectif** : une extension canonique et facultative du parcours d'observation espèces.
- **Fonctions** : `ACC-12`, `HIS-03`.
- **Statuts visés** : deux références C → A par une seule livraison.
- **Dépendances** : observation/réconciliation espèces existante.
- **Migration livrée** : extension additive de `account_balance_observations`, catalogue serveur des coupures et RPC idempotente; aucune nouvelle source de solde.
- **Backend/frontend** : total simple conservé; panneau optionnel billets/pièces, somme et contrôle de cohérence.
- **Confidentialité/1/2/N** : droits du compte/caisse et actor générique.
- **Tests** : total seul, détail, incohérence, zéro écriture financière, régularisation séparée.
- **C3/C4B** : aucune observation pilote durable pendant les tests.
- **Sortie** : les deux parcours fonctionnent; le détail n'est jamais obligatoire.
- **Taille/risque** : S; risque modéré de confondre observation et régularisation.
- **Preuve** : tests domaine/widget/contrat, test SQL/RLS et matrice runtime transactionnelle rollbackée; aucun FinancialEvent, posting ou mouvement d'enveloppe.

### L2.8 — Restauration fonctionnelle isolée

- **Objectif** : démontrer qu'une archive canonique reconstruit un foyer hors pilote.
- **Fonctions** : `R4-09`.
- **Statut visé** : C → A.
- **Dépendances** : L2.6, contrats L1, schéma final du Lot 2.
- **Migrations probables** : aucune sur pilote; format/version d'archive seulement si nécessaire et additif.
- **Backend/frontend** : outil/procédure contrôlée; aucun bouton libre-service requis.
- **Confidentialité/1/2/N** : droits, acteurs, partages et données sensibles reconstruits à l'identique.
- **Tests** : environnement isolé, manifest/checksums, relations, idempotence, erreurs partielles, rollback, comparaison fonctionnelle.
- **C3/C4B** : source seulement pour empreintes autorisées; jamais restaurée sur le Sandbox pilote.
- **Sortie** : reconstruction certifiée et documentée, sans perte ni élargissement de droits.
- **Taille/risque** : L; risque critique de perte ou restauration trop permissive.

**État d'exécution — 25 octobre 2026 : A / READY.** Le format canonique v1,
son manifeste et ses empreintes, le remappage complet source→cible, l'ordre de
dépendances, les contrôles GL/obligations, le rollback et l'idempotence sont
livrés dans `canonical_household_archive.dart`. Une reconstruction réelle est
exécutée dans une cible mémoire isolée par les tests 1/2/N. L'export utilisateur
F7 est explicitement non restaurable et ne peut pas être accepté par erreur.
Voir `FINANCIEL_PILOTE_L2_8_CANONICAL_RESTORATION.md`.

## 8. Graphe, ordre et parallélisation

Ordre strict recommandé :

`L2.1 → L2.2 → L2.3 → L2.4 → L2.5 → L2.6 → L2.8`

`L2.7` est indépendant après vérification du contrat d'observation et peut être livré après L2.1 ou en parallèle de L2.2/L2.3.

- L2.1 stabilise les contrats temporels utilisés par qualité, échéanciers et reporting.
- L2.2 stabilise la signification des KPI/écarts avant les rapports.
- L2.3 stabilise les résultats de financement avant échéancier global et export fiscal.
- L2.4 stabilise les séries et read models avant rapports et formats.
- L2.5 stabilise le contenu métier avant L2.6.
- L2.8 utilise le format final des exports et clôt le Lot 2.

## 9. Definition of Done globale du Lot 2

Le Lot 2 est `READY` uniquement si :

1. Les 28 IDs ci-dessus sont A, avec `ACC-12/HIS-03` implémentés une seule fois.
2. Aucun nouveau moteur financier, budgétaire, de capacité, de scénario, de patrimoine, de clôture ou de réconciliation n'existe en parallèle.
3. Toutes les simulations, détections, observations et restitutions créent zéro FinancialEvent, transaction GL, posting ou Envelope Movement.
4. Toute action financière réelle reste explicite, confirmée, idempotente et passe par les primitives canoniques.
5. Épargne et Reste épargne/primes restent distinctes selon les décisions historiques.
6. Les rapports, agrégats, graphiques, exports, alertes et erreurs respectent les trois modes de confidentialité L1 sans inférence par différence.
7. Les parcours fonctionnent pour 1, 2 et N membres sans hardcode pilote.
8. Les rapports de clôture, historiques, échéanciers et simulations sont explicables, datés et reproductibles.
9. XLSX, PDF, PPTX et exports spécialisés sont ouvrables, testés et n'exposent aucune donnée interdite.
10. Le comptage par coupures reste facultatif et séparé de toute régularisation.
11. Une archive canonique est restaurée et certifiée dans un environnement isolé, jamais sur le pilote actif.
12. Tests SQL/RLS, tests ciblés, suite Flutter, analyze, format et builds disponibles sont verts à chaque sous-lot et globalement.
13. C3/C4B, snapshots, obligations et compteurs financiers restent strictement inchangés hors métadonnée explicitement autorisée.
14. Aucune fixture durable, aucun cutover, aucune reprise de la certification runtime L1 et aucun travail D1.2/P1/IA n'est inclus.

## 10. Risques et gates

- **Chemin critique** : contrats temporels → qualité/financement → read models → rapports → formats → restauration.
- **Risque principal** : fuite par agrégation/export, suivie du double comptage et de la confusion simulation/réel.
- **Gate confidentialité** : chaque sous-lot doit prouver le filtrage serveur, l'anti-inférence et la révocation pour ses nouvelles sorties.
- **Gate comptable** : seules les primitives existantes peuvent écrire; toute simulation ou observation est read-only.
- **Gate pilote** : aucune donnée C3/C4B n'est modifiée pour faire passer une recette.

## État d’exécution L2.1 — 2026-10-22

L2.1 est livré : `HID-01`, `REC-X3`, `R3-02`, `CAS-X1`, `ALT-X3` et
`OBL-05` sont classés A. Les contrats temporels et d’explication sont communs
aux moteurs Budget, R3, F5/F6, obligations et projection ; ils ne constituent
pas de nouveau moteur financier. Les preuves ciblées sont dans
`test/lot2/l2_1_temporal_contracts_test.dart` et les suites historiques.

## État d’exécution L2.2 — 2026-10-23

L2.2 est livré sans migration ni moteur concurrent. La surface Budget compose
les lectures canoniques autorisées pour restituer prévu, réalisé, attendu et
restant, puis les indicateurs mensuels et options d’arbitrage. Le compositeur
est strictement read-only et ses explications portent règle, période, source,
raison, statut et action éventuelle.

| ID | Avant | Après | Preuve | Statut final |
|---|---|---|---|:---:|
| BUD-10 | Écarts prévu/réel sans attendu ni restitution décisionnelle commune | Prévu, réalisé, attendu et restant par enveloppe et en synthèse | `monthly_quality_analysis.dart`; tests L2.2; panneau Budget | A |
| R2-09 | Cas de rapprochement sans KPI mensuel consolidé | Ouverts et ancienneté calculés sur les dossiers canoniques autorisés | `monthly_quality_provider.dart`; tests rapprochement | A |
| R2-10 | Justificatifs unitaires sans santé mensuelle | Couverture, attachés et manquants calculés sur FinancialEvent/attachments visibles | tests justificatifs et RLS existante | A |
| R2-11 | Acteur confondu avec responsabilité potentielle | Contrat foyer/membre/non attribué; `created_by` reste seulement l’acteur | tests 1/2/N du compositeur | A |
| PLAN-07 | Surplus et revenus attendus dispersés | Reliquat et revenus variables attendus séparés; aucun budget récurrent inventé | tests prime/revenu attendu | A |
| PLAN-08 | Briques F4/F5/Scenarios séparées | Options comparables et explicables; FinancialAvailability incomplet bloque la recommandation | tests arbitrage read-only | A |

Épargne demeure une enveloppe permanente et une option ne déclenche jamais le
sweep ni un transfert bancaire. Les primes restent attendues et séparées du
budget récurrent jusqu’à leur réalisation. Les agrégats sont composés après les
contrats de lecture/RLS L1; aucune donnée privée brute n’est chargée pour être
masquée ensuite.

## État d’exécution L2.3 — 2026-10-24

L2.3 complète F5 sans nouveau moteur ni migration. Le comparateur transforme
des hypothèses locales en profils F5 éphémères, réutilise l’échéancier
canonique et FinancialAvailability, puis restitue séparément coût, échéance,
durée, apport, avantages projetés et limites. Aucune simulation ne crée de
dette, obligation ou écriture financière.

| ID | Avant | Après | Preuve | Statut final |
|---|---|---|---|:---:|
| WLT-05 | Échéancier et anticipation unitaires, saisie d’anticipation illustrative | Temporalité fin de mois déterministe, comparaison durée/échéance et résultats structurés sans mutation | `financing_simulation.dart`; tests F5/L2.3 | A |
| WLT-06 | Avantage projeté limité à un montant libre | Aide, fiscalité et contribution paramétrables par type, base, taux, plafond et période ; Murabaha conservée | `home_auto_models.dart`; panneau Logement; tests avantages | A |
| R4-08 | Aucun comparateur d’offres exploitable | Comparaison responsive de plusieurs hypothèses sur apport, financement, durée, échéance, coût, total, avantage et capacité | `financing_comparison_dialog.dart`; tests domaine/widget | A |

La comparaison expose plusieurs dimensions sans déclarer automatiquement un
« meilleur choix ». Une capacité incomplète reste « à confirmer » et aucun
montant privé n’est déduit. Les avantages projetés restent analytiques et les
avantages réels continuent d’exiger un FinancialEvent canonique.

