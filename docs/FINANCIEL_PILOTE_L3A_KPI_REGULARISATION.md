# L3A — KPI et régularisation opérationnelle

Base : `e72c8be094e5469f3d06fa0943ed99fdc5c1db98`.

## Frontière

L3A compose exclusivement les lectures canoniques existantes : FinancialEvent,
GL, Envelope Ledger, observations de soldes, rapprochements, occurrences
attendues, Budget Intelligence, R2 et F5. KPI, simulations et exports sont
read-only. La confirmation déjà présente dans R2 reste une action séparée
utilisant les primitives canoniques ; elle n'est jamais déclenchée par le
Dashboard.

## KPI-X1 — discipline et qualité

- **Avant** : délai global de clôture et indicateurs mensuels partiels ; pas de
  catalogue explicable par périmètre.
- **Après** : moyenne, médiane, classes J0/J1/J2-3/J4-7/>J7, délai attendu,
  enveloppes et justificatifs manquants, rapprochements ouverts/anciens/résolus,
  attendu non matérialisé et non-attribué. Chaque valeur porte règle, source,
  période, complétude, limitations et identifiants de drill-down.
- **Preuve** : `operational_kpis.dart`, `operational_kpi_provider.dart`, panneau
  Dashboard et tests domaine/widget.
- **Règle d'attribution** : `actor_user_id` n'est jamais une responsabilité
  économique. Un profil membre ne reçoit que les éléments possédant une
  attribution métier explicite ; sinon l'élément reste « non attribué ».
- **Statut** : A après validation globale.

## KPI-X2 — espèces partagées

- **Avant** : inventaire et coupures L2.7 disponibles par compte.
- **Après** : dernier inventaire, âge/fréquence, écarts ouverts/régularisés,
  délai de résolution, localisation explicite, non-attribué et cohérence des
  coupures. Auteur, détenteur déclaré et responsable économique restent
  distincts.
- **Confidentialité** : seules les observations renvoyées par les politiques
  L1 pour les comptes dont le solde est lisible sont chargées. Le Dashboard ne
  calcule aucun montant d'espèces global ou différentiel interdit.
- **Preuve** : lecture groupée sans N+1, analyse pure et tests dédiés.
- **Statut** : A après validation globale.

## R2-X1 — plan de régularisation

- **Avant** : comparaison actuel/cible, plan analytique par enveloppe, netting
  global et détail par compte déjà présents dans R2.
- **Après** : synthèse par membre ou « foyer/compte partagé », montants à
  virer/recevoir, retraits/dépôts espèces et nombre d'actions. Les comptes
  partagés ne sont jamais attribués arbitrairement à un membre.
- **Fiabilité** : une matrice non fiable ou des blockers empêchent la
  proposition exécutable. Le mouvement analytique d'enveloppe reste distinct
  du transfert bancaire physique.
- **Preuve** : `summarizeRegularizationByMember`, UI Fin de mois et tests
  banque/espèces/compte partagé/N membres.
- **Statut** : A après validation globale.

## DSH-X1 — Dashboard unifié

- **Avant** : Dashboard financier V2, alertes, budget, comptes, obligations,
  objectifs et organisation déjà composés.
- **Après** : catalogue « Qualité et fiabilité » intégré, filtres foyer/membre,
  période partagée, états loading/error/empty/partial, explications et accès
  aux opérations, rapprochements et Fin de mois.
- **Confidentialité** : agrégation après les contrats de lecture L1 ; les
  valeurs masquées ne sont ni additionnées ni estimées.
- **Statut** : A après validation globale.

## EXP-X3 — export d'amortissement

- **Avant** : l'audit documentaire le classait B.
- **Après constaté** : l'export XLSX métier était déjà livré par L2.6 dans
  `RestitutionExportService.amortizationXlsx` et exposé depuis Portabilité.
  Il réutilise `buildFinancingSchedule`, couvre intérêt et Murabaha, encode les
  montants en cellules numériques et les dates comme dates Excel.
- **Preuve** : `restitution_exports_test.dart` ouvre le package et compare les
  calculs aux mathématiques F5.
- **Statut** : A sans nouveau moteur ni migration.

## Temporalité et performance

Les bornes de période sont `[début, fin exclusive)` et l'horloge du Dashboard
est injectable. Les changements de mois/année et périodes vides sont couverts.
Le calcul domaine est linéaire, testé avec 20 000 opérations. Les transactions
sont bornées à 5 000 par lecture d'écran et les observations espèces sont
chargées en une requête groupée. Une agrégation paginée sera nécessaire avant
qu'un foyer dépasse durablement cette borne d'affichage.

## Absence d'écriture

Le provider L3A expose uniquement des lectures existantes. Aucune migration,
table, RPC de mutation, FinancialEvent, transaction GL, posting ou mouvement
d'enveloppe n'est ajouté par L3A.
