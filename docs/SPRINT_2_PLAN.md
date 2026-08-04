# Sprint 2 — Plan de réalisation

## Sprint 2.1 — Transactions et Grand Livre

### Objectifs

- Introduire le Grand Livre comme source de vérité transactionnelle.
- Gérer les transactions, la double écriture, les virements, remboursements,
  splits, pièces jointes, commentaires, catégories, tags et récurrences.

### Dépendances

- Sprint 1 livré avec les comptes et titulaires relationnels.
- Schéma `accounts` et contrôle du foyer actif disponibles.

### Livrables

- Modèle comptable, repositories et migrations du Grand Livre.
- Écrans de saisie, liste, détail et recherche de transactions.
- Virements équilibrés, remboursements et transactions ventilées.
- Tests unitaires, widget et intégration de l’écriture double.

### Risques

- Cohérence des écritures lors d’une annulation ou d’une correction.
- Gestion des comptes archivés et des données historiques sans compte associé.

### Critères de validation

- Chaque mouvement modifie le Grand Livre de manière atomique et traçable.
- Les virements sont équilibrés ; les échecs ne laissent aucune écriture partielle.
- Toutes les actions restent isolées au foyer actif.

## Sprint 2.2 — Enveloppes, budgets et objectifs

### Objectifs

- Raccorder enveloppes et budgets au Grand Livre.
- Construire prévisions, rapports de période et objectifs d’épargne.

### Dépendances

- Sprint 2.1 validé ; écritures du Grand Livre disponibles.

### Livrables

- Allocation, alimentation et transfert entre enveloppes.
- Calcul des soldes théoriques, prévisions et écarts.
- Objectifs avec progression et date estimée d’atteinte.

### Risques

- Règles de période mensuelle et reprise de solde.
- Rapprochement entre budget, espèces et comptes bancaires.

### Critères de validation

- Les soldes sont exclusivement dérivés des écritures validées.
- Une clôture ou un transfert est auditable et réversible selon les règles métier.

## Sprint 2.3 — Dashboard et simulations

### Objectifs

- Construire le dashboard, les KPI, cashflow, patrimoine, investissements et
  simulateurs de décision.

### Dépendances

- Données fiables des Sprints 2.1 et 2.2.

### Livrables

- Vue de trésorerie, patrimoine net et reste à vivre.
- KPI de budget et de progression d’objectifs.
- Simulations d’achat, remboursement anticipé et scénarios.

### Risques

- Lisibilité des indicateurs malgré un volume croissant de données.
- Hypothèses de simulation distinctes des données réellement comptabilisées.

### Critères de validation

- Chaque chiffre du dashboard est traçable vers le Grand Livre.
- Les simulations n’écrivent aucune donnée réelle sans confirmation explicite.

## Sprint 2.4 — IA et recherche intelligente

### Objectifs

- Ajouter prévisions, conseils, recherche et analyse patrimoniale assistées.

### Dépendances

- Grand Livre, catégorisation et données historiques validés.
- Politique de confidentialité et d’autorisation utilisateur définie.

### Livrables

- Recherche en langage naturel sur les données du foyer.
- Suggestions de catégorisation et d’anomalies.
- Prévisions de trésorerie et analyses patrimoniales explicables.

### Risques

- Confidentialité des données financières.
- Réponses imprécises ou non explicables.

### Critères de validation

- Toute recommandation indique les données et hypothèses utilisées.
- L’IA ne modifie jamais une donnée financière sans confirmation explicite.
