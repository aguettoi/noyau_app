# L2.6 — Restitutions métier multi-formats

## Contrat livré

Un read-model unique, strictement en lecture, compose les données déjà autorisées par les contrats serveur L1. Les formateurs XLSX, PDF et PPTX n'effectuent aucun calcul financier autonome et ne lisent jamais les tables brutes de comptes.

- **R4-02** : XLSX métier à quatre feuilles exactes : `Solde enveloppes`, `Journal`, `Soldes cash`, `Dettes et créances`.
- **R4-03** : rapports PDF mensuel, trimestriel, semestriel et annuel, avec période, statut des faits, sources et limites de complétude.
- **R4-04** : présentation PPTX autonome et ouvrable, structurée en synthèse, activité, patrimoine, échéances, limites et conclusion.
- **EXP-X1** : export XLSX fiscalité logement distinguant estimation et avantage constaté, paramètres et source, sans prétention de déclaration officielle.
- **Financements** : tableau d'amortissement XLSX provenant exclusivement de `buildFinancingSchedule`, y compris intérêt et murabaha.

Les exports F7 existants restent disponibles. Les noms sont stables par type et période, avec un horodatage UTC à la seconde pour éviter les collisions.

## Confidentialité et invariants

Le dataset utilise les providers/RPC autorisés existants. Un compte privé non partagé est absent ; un solde non lisible n'est jamais exporté. Aucun total global n'est reconstitué depuis une donnée masquée. La génération est locale et ne produit ni `FinancialEvent`, ni transaction/posting GL, ni mouvement d'enveloppe, ni mutation de snapshot.

## Extractions intelligentes candidates

- **V1 (livré)** : pack quatre feuilles, rapports périodiques, présentation, amortissement, fiscalité logement.
- **V1.1 (candidat)** : dossier annuel consolidé et dossier patrimoine partageable avec audience explicite.
- **V2 (candidat)** : packs de transmission paramétrables et contrôle assisté de qualité, sans accès plus large que l'utilisateur courant.

Ces candidats sont des recommandations et non de nouvelles promesses V1.

## Preuves

`test/portability/restitution_exports_test.dart` couvre les frontières de période, les quatre feuilles et types de cellules, les quatre périodicités PDF, la structure OOXML PPTX, l'absence d'une donnée privée sentinelle, les financements intérêt/murabaha et la distinction fiscale projeté/réel.
