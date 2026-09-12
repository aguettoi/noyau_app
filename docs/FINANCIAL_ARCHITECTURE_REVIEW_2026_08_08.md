# Revue d’architecture financière — 8 août 2026

## Périmètre et statut

Ce document est une décision d’architecture préparatoire. Il ne crée aucune
migration, ne modifie aucune donnée Supabase et ne valide aucun test Sandbox
qui n’a pas été exécuté manuellement.

Les mécanismes déjà présents et conservés sont :

- Grand Livre financier en partie double, immuable et calculé par vue ;
- journal d’enveloppes séparé, immuable et calculé par vue ;
- création atomique d’une dépense/revenu avec ses mouvements d’enveloppes ;
- transfert entre enveloppes sans mouvement bancaire ;
- ouverture d’enveloppe `opening` / `opening_offset` vers l’enveloppe système
  `to_allocate`, sans transaction financière ni ligne bancaire ;
- import idempotent d’enveloppes et annulation sécurisée de son dernier lot.

Les imports et mouvements listés dans la matrice ci-dessous restent **à
valider manuellement**.

## État actuel observé

| Sujet | État actuel | Écart à traiter plus tard |
|---|---|---|
| Compte | `accounts` et `financial_transaction_lines` portent la position bancaire/cash et les contreparties système. | Le type `loan` ne fournit pas une fiche de dette, son restant et ses règlements. |
| Enveloppe | `envelopes` est un référentiel ; `envelope_movements` est son journal ; `envelope_ledger_balances` est une vue calculée. | La page principale affiche encore les archives et l’enveloppe système dans les parcours ordinaires. |
| Transaction | `financial_transactions` décrit et date une opération, avec ses lignes comptables. | Elle reste l’unique objet d’intention : elle ne distingue pas assez l’événement économique de ses écritures techniques. |
| Dépense cash | RPC `create_financial_transaction_with_envelopes` : écriture cash/charge et consommations d’enveloppes dans la même transaction SQL. | À valider réellement de bout en bout. |
| Revenu | Écriture compte/revenu et allocation automatique vers `to_allocate`. | À valider réellement de bout en bout. |
| Transfert bancaire | Grand Livre uniquement. | À valider réellement de bout en bout. |
| Transfert d’enveloppes | `create_envelope_transfer` ; deux mouvements équilibrés, sans transaction financière. | À valider réellement de bout en bout. |
| Allocation d’un budget | Le transfert d’enveloppes est disponible, mais l’origine compte d’une affectation n’est pas modélisée explicitement. | Décider entre traçabilité souple et réservation stricte. |
| Dette/créance | Pas de référentiel dédié ni de règlements partiels. | À construire avant de les exposer dans l’UI. |

## Modèle cible

```text
FinancialEvent (intention économique, immuable)
        │
        ├── financial_transactions ── financial_transaction_lines
        │       (Grand Livre : comptes, charges, produits, passifs, actifs)
        │
        ├── envelope_movements
        │       (journal budgétaire, sans faux mouvement cash)
        │
        └── obligations / obligation_settlements
                (dette ou créance, statut et restant calculé)
```

### Responsabilités

| Objet | Rôle |
|---|---|
| `FinancialEvent` | Événement saisi par l’utilisateur : type, libellé obligatoire, date, notes, auteur et identifiant d’idempotence. Il orchestre les écritures sans devenir un solde. |
| `financial_transactions` / `financial_transaction_lines` | **Ledger** comptable : source de vérité des comptes, charges, produits, actifs et passifs. Append-only, correction par contrepassation. |
| `envelopes` | **Référentiel** budgétaire : nom, statut, notes et code système éventuel. Aucun solde stocké. |
| `envelope_movements` | **Ledger** budgétaire : consommation, allocation, transfert, ouverture et contrepassation. Peut référencer l’événement et/ou l’écriture financière qui l’explique. |
| `obligations` | Référentiel d’une dette à payer ou créance à encaisser : contrepartie, date, échéance, statut. Le restant est une **projection calculée**, pas une colonne modifiable. |
| `obligation_settlements` | Lien immuable entre une obligation, son événement de règlement et les lignes du Grand Livre. Permet les règlements partiels. |
| Vues de balances/restants | **État calculé** : `account_ledger_balances`, `envelope_ledger_balances` et future vue `obligation_balances`. |
| Riverpod / pages Flutter | **Projections UI** seulement : lecture des vues, validation de formulaire et appel d’une RPC atomique. |

`FinancialEvent` doit être introduit comme racine d’audit, sans recopier les
montants calculables depuis les ledgers. Une opération qui génère plusieurs
écritures conserve un même `event_id` dans la même transaction SQL.

## Modélisation métier recommandée

| Scénario | Grand Livre | Journal d’enveloppes | Dette / créance |
|---|---|---|---|
| Dépense cash de 200 MAD | charge +200 ; Banque A -200 | Courses -200 | aucun impact |
| Revenu de 300 MAD | compte +300 ; produit/revenu +300 | `À répartir` +300 | aucun impact |
| Affectation 1 000 MAD vers Voyages | aucun mouvement cash | `À répartir` -1 000 ; Voyages +1 000 | aucun impact |
| Transfert d’enveloppes | aucun mouvement cash | source -300 ; destination +300 | aucun impact |
| Achat à crédit de 500 MAD | charge +500 ; passif dette +500 | enveloppe -500, une seule fois | obligation payable +500 |
| Paiement partiel de dette de 200 MAD | compte -200 ; passif dette -200 | aucun nouveau mouvement | règlement de 200 ; restant calculé 300 |
| Naissance de créance de 100 MAD | actif créance +100 ; produit selon l’événement | seulement si une règle budgétaire explicite le justifie | obligation receivable +100 |
| Encaissement de créance de 100 MAD | compte +100 ; actif créance -100 | aucun nouveau revenu automatique | règlement de 100 ; restant calculé 0 |
| Transfert bancaire | Compte A -100 ; Compte B +100 | aucun mouvement par défaut | aucun impact |

Les termes « charge + » et « produit + » représentent leur reconnaissance
comptable ; le sens débit/crédit effectif reste celui des lignes déjà imposées
par le Grand Livre.

## Allocation et provenance des fonds

Une allocation budgétaire ne doit jamais réduire un compte bancaire. Le compte
et l’enveloppe mesurent des axes différents : **où se trouve la liquidité** et
**à quoi elle est affectée**.

Recommandation initiale : conserver `À répartir` comme contrepartie budgétaire
technique, invisible dans les sélecteurs ordinaires. Les revenus et openings
alimentent ce solde ; les allocations et transferts le diminuent. Cela préserve
l’historique déjà présent, explique les déficits historiques de répartition et
évite tout faux cash.

Pour tracer le compte qui finance une allocation, introduire plus tard une
table append-only de **provenance souple** (par exemple
`budget_funding_links`) : `event_id`, `source_account_id`, `envelope_id`,
`amount`, date et note. Elle documente l’intention, mais n’est pas une seconde
source de vérité des soldes et n’empêche pas un compte de financer plusieurs
enveloppes.

Une vraie réservation stricte par compte ne doit être développée que si le
produit exige de bloquer les affectations au-delà de la liquidité disponible :
elle impose alors une politique explicite de rapprochement, de découvert et de
consommation. Ce choix est plus complexe et ne doit pas être implicite.

## UX cible des enveloppes

1. La page Enveloppes principale montre seulement les enveloppes utilisateur
   actives.
2. `À répartir` reste une ligne d’audit interne ; elle est exclue des listes
   utilisateur ordinaires et des nouveaux formulaires, sauf parcours explicite
   d’allocation budgétaire.
3. Un accès distinct **Enveloppes archivées** montre les archives, leur
   historique et l’action Réactiver.
4. Les archives et les systèmes sont exclus des listes de saisie de dépense,
   de split et de transfert ordinaires.
5. Les confirmations restent obligatoires pour archiver ou supprimer.

## Migrations proposées, non créées

1. **Événements financiers** : ajouter `financial_events` et une référence
   nullable `event_id` sur les deux journaux. Prévoir une compatibilité avec
   les transactions et mouvements historiques sans les réécrire.
2. **Obligations** : ajouter `obligations`, `obligation_settlements` et la vue
   calculée des restants. Les deux tables ne sont écrites que par RPC
   `SECURITY DEFINER` atomiques.
3. **Provenance d’allocation** (après décision métier) : ajouter
   `budget_funding_links`, sans impact sur les soldes de comptes.
4. **UX archives/système** : aucune migration nécessaire a priori ; changement
   de providers et de projections Flutter uniquement.
5. **Remboursements** : unifier le contrat historique `recovery` avec les
   types Flutter et les règles de contrepartie avant tout écran.

Chaque migration devra être additive, transactionnelle, idempotente, avec RLS
lecture seule, fonctions `SECURITY DEFINER` à `search_path` fixé et tests de
rollback. Aucune donnée historique ne doit être convertie automatiquement.

## Matrice de validation manuelle

| Scénario | Impact compte | Impact enveloppe | Charge / revenu | Dette / créance | Résultat attendu | Test auto | Sandbox | Statut |
|---|---|---|---|---|---|---|---|---|
| Dépense cash + enveloppe | - montant | - montant, split exact | charge reconnue une fois | aucun | groupes équilibrés, aucun doublon | partiel | à faire | non validé |
| Revenu | + montant | `À répartir` + montant | revenu reconnu une fois | aucun | balances immédiates | partiel | à faire | non validé |
| Transfert compte | A - / B + | aucun | aucun | aucun | transaction équilibrée | partiel | à faire | non validé |
| Transfert enveloppes | aucun | A - / B + | aucun | aucun | groupe budgétaire nul | partiel | à faire | non validé |
| Ajustement | selon sens | aucun par défaut | contrepartie ajustement | aucun | aucune enveloppe implicite | partiel | à faire | non validé |
| Dépense à crédit | aucun | - montant une seule fois | charge reconnue | dette créée | aucun cash initial | absent | à faire après implémentation | non implémenté |
| Paiement partiel dette | - paiement | aucun | aucune seconde charge | restant diminué | règlement idempotent | absent | à faire après implémentation | non implémenté |
| Créance sans cash | aucun | règle explicite seulement | produit selon événement | créance créée | aucun cash | absent | à faire après implémentation | non implémenté |
| Encaissement créance | + paiement | aucun | aucun second produit | restant diminué | encaissement partiel possible | absent | à faire après implémentation | non implémenté |
| Split multi-enveloppes | - montant | somme des sorties = montant | charge une fois | aucun | refus si écart/doublon | partiel | à faire | non validé |
| Import comptes final | selon preview | aucun | aucun | aucun | import atomique, rapport | partiel | à faire | non validé |
| Import enveloppes final | aucun | openings/offsets attendus | aucun | aucun | created/existing/ignored, undo sûr | partiel | à faire | non validé |
| Reprise SIMULATION.xlsx final | selon règles approuvées | selon règles approuvées | selon règles approuvées | selon règles approuvées | preview + confirmation + rapprochement | absent | à faire en dernier | non validé |

## Recette multiplateforme

| Plateforme | Cas obligatoires |
|---|---|
| Windows | sélection/enregistrement de CSV, UTF-8/BOM/CRLF, fenêtre réduite, dialogues, authentification, import et refresh. |
| Web | téléchargement template, upload CSV, UTF-8, navigation responsive, authentification et refresh. |
| Android | picker natif, permissions, clavier numérique MAD, navigation, dialogues, réseau intermittent et reprise. |

## Stratégie de nettoyage finale

Ne rien nettoyer avant le gel fonctionnel. Le futur outil devra d’abord
identifier les données par marqueurs de test explicites et par jeux de tests
documentés, produire un rapport sec, exiger une confirmation humaine, puis
contrepasser les écritures immuables au lieu de les supprimer. Les rares
référentiels sans historique devront être supprimés uniquement après preuve
qu’ils ne sont liés à aucune donnée réelle. Une vérification des vues de solde,
des groupes équilibrés et de l’isolation des foyers clôturera ce nettoyage.

## Processus final SIMULATION.xlsx

Utiliser uniquement la version finale fournie au moment de la clôture : analyser
les onglets réellement présents, mapper comptes/enveloppes/historiques selon le
contrat alors validé, produire un preview et un rapport de rapprochement,
demander confirmation, importer par lots atomiques idempotents, puis conserver
le rapport. Aucun fichier actuel n’est une source définitive figée.

## Roadmap proposée

1. Geler le comportement Comptes et Enveloppes ; corriger seulement les bugs.
2. Finaliser la recette réelle des opérations déjà codées et des imports.
3. Décider la sémantique de provenance souple ou réservation stricte.
4. Créer le modèle `FinancialEvent` et les obligations, avec migrations et RPC
   atomiques auditées.
5. Implémenter dette/créance, règlements partiels et contrepassations.
6. Isoler l’UX des archives et masquer les systèmes des parcours ordinaires.
7. Finaliser la reprise de `SIMULATION.xlsx` après nettoyage audité.
8. Exécuter la recette Windows, Web et Android avant tout nettoyage final.

## Décisions métier requises

1. Une enveloppe doit-elle être seulement une affectation budgétaire, ou une
   réservation stricte contre un ou plusieurs comptes ?
2. À la naissance d’une dette, doit-on toujours consommer l’enveloppe, ou
   proposer une règle choisie par le foyer ?
3. À la naissance d’une créance, faut-il reconnaître immédiatement un revenu,
   ou distinguer avance/remboursement sans produit ?
4. L’accès aux archives doit-il être une page dédiée ou un filtre explicite ?
