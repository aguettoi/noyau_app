# D1.2-C — Argent Core

## Contrat de présentation

La présentation réutilise exclusivement les providers, use cases et RPC canoniques. Aucun calcul financier, ledger, transfert d’enveloppe ou écriture de compte n’a été réimplémenté dans les widgets.

### Transactions

- recherche, filtres rapides Toutes/Dépenses/Revenus/Transferts, puis filtres avancés repliables ;
- montant, type, libellé, compte réellement utilisé et enveloppe restent centraux ; date et notes sont derrière « Plus d’options » ;
- compte et enveloppe restent indépendants ; une recommandation ne verrouille jamais le compte ;
- dettes, créances, règlements, encaissements, abandons, ventilations et contrepassations conservent leurs flux canoniques.

### Comptes

- la vue simple conserve nom, type, titulaires, état et solde uniquement lorsqu’il est autorisé ;
- un solde non autorisé est privé, jamais remplacé par zéro ;
- le détail conserve solde théorique/réel, observation, inventaire espèces, rapprochement et historique ;
- le total est explicitement limité aux soldes visibles et signale une couverture partielle.

### Enveloppes et ENV-TPL

- la vue principale conserve le disponible canonique, les entrées, sorties et la dernière activité ;
- mouvements, affectations, transferts entre enveloppes, recommandations et archivage restent accessibles ;
- catalogue unique de 21 modèles en sept familles ; recherche, sélection multiple, aucune sélection et création personnalisée ;
- création via `createRemoteEnvelopeProvider` ; les noms localisés sont des propositions modifiables ;
- FR, EN, AR, Darija et 1/2/N.

## Zones rouges — structure

| Zone | Avant | Après D1.2-C |
|---|---:|---|
| Transactions | 5 608 lignes, 37 classes | flux conservés ; filtres quotidiens extraits dans `transaction_quick_filters.dart` ; saisie progressive ; aucun repository ajouté |
| Comptes | 2 130 lignes | composants simples/avancés séparés par widgets dédiés ; contrat privacy conservé |
| Enveloppes | 1 661 lignes | catalogue et écran ENV-TPL extraits dans deux fichiers ; dashboard raccordé au provider canonique |

Le découpage complet des workflows historiques de Transactions n’est pas mécanique : déplacer les dialogues sans bénéfice fonctionnel augmenterait le risque sur FinancialEvent/GL. Le découpage reste progressif et limité aux composants autonomes.

## Preuves et invariants

- tests ciblés Transactions, Comptes, rapprochement, Enveloppes et ENV-TPL ;
- quinze goldens desktop/mobile/tablette/formulaire/privacy/dépassement/dark/RTL/vide ;
- aucune migration, aucune mutation financière de recette, C3/C4B inchangés ;
- aucun accès Supabase direct nouveau depuis Presentation.
