# Matrice de couverture fonctionnelle

Cette matrice decrit l'etat du code local. Les migrations ne sont volontairement pas appliquees a distance.

| Volet source | Origine | Couverture actuelle | Statut | Suite necessaire |
|---|---|---|---|---|
| Enveloppes | `Enveloppes` | 25 noms de reference, validation et archivage source | Couvert Phase 1 | Creer les lignes `envelopes` apres confirmation du foyer |
| Journal quotidien | `Journal` | Colonnes, montants signes, dates, details et enveloppes valides; archivage immutable | Partiel | Mapping explicite compte source puis ecritures Grand Livre |
| Scenarios et salaires | `SCENARIOS`, feuilles salaires | Validation de structure, ecarts de libelles et archivage de valeurs/formules | Partiel | Regles versionnees de salaires, primes et repartition |
| Shopping list | `Shopping list` | Validation des articles, estimations, priorites et etats; archivage | Partiel | Modele achats/objectifs et decisions d'achat |
| Priorites / voiture | `PRIOS`, `Acquisit voiture` | Validation `PRIOS`; archivage complet des deux onglets | Partiel | Objectifs, financement et projection de date |
| Comptes, cash et rapprochement | `SCENARIOS`, `TDB`, `Enveloppes` | Modeles comptes/Grand Livre; sources archivees | Partiel | Ecran de mapping des comptes, soldes reels et rapprochement |
| Taches menageres | `Orga menage`, `Feuille 16` | Validation structurelle et archivage | Partiel | Entites taches, affectations, routines et calendrier |
| Emprunts et amortissement | 8 onglets emprunt, notaire, vente, comparaison | Import source avec formules conservees par onglet | Partiel | Modele dette, amortissement mensuel, IR et prise en charge employeur |
| Audit import | Tous onglets | Choix manuel des onglets, erreurs expliquees par ligne/champ, resolution, session, empreinte SHA-256, journal par onglet et annulation logique | Couvert Phase 1 | Appliquer la migration puis activer le connecteur avec un foyer authentifie |
| Liaison Google Sheets | Lien de partage Google Sheets | Telechargement du classeur via le lien, sans secret et avec la meme validation avant import | Couvert Phase 1 | Le document doit etre partage avec le lien ou accessible au compte utilisateur |
| Acces et secrets | Configuration Flutter / Supabase | Variables `--dart-define`, aucune cle publiee dans le code | Couvert Phase 0 | Authentification et roles operationnels |
| Hors connexion, temps reel, export, graphes | Cahier des charges | Non implemente | Absent | Phase 4 |

## Regle de passage

Une archive Phase 1 ne materialise jamais silencieusement une formule, un compte ou une ecriture. Chaque materialisation future devra referencer la session d'import, son onglet, la cellule source et son motif de confirmation.
