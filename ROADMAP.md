# Roadmap Noyau

## Phase 0 - Fondation financiere

**Statut : terminee**

- Montants exacts (`Money`) et Grand Livre a double entree.
- Modeles de membres, comptes, ecritures et lignes comptables.
- RLS, audit et migrations locales du socle Supabase.
- Referentiel des 25 enveloppes provenant du classeur source.
- Configuration Supabase uniquement par variables `--dart-define`.

## Phase 1 - Import fiable du classeur

**Statut : terminee dans le code - activation Supabase manuelle en attente**

- Registre extensible de 29 importeurs, un par onglet du classeur connu.
- Selection explicite des onglets, validation, apercu, differences et confirmation avant tout archivage.
- Fenetre de resolution des anomalies et action d'annulation du dernier import archive.
- Diagnostic debutant par ligne et par champ, avec explication et proposition de correction.
- Lecture d'un Google Sheet partage par lien, soumise au meme parcours de validation que le fichier Excel.
- Importeurs specialises pour Enveloppes, Journal, Scenarios, Shopping list et PRIOS.
- Archivage transactionnel de toutes les cellules non vides et des formules, avec empreinte SHA-256.
- Session, journal par onglet, RLS et annulation logique prepares dans la migration locale.
- Connecteur Flutter/Supabase pret a appeler les RPC d'archivage et d'annulation.

Avant la premiere utilisation reelle, appliquer manuellement les migrations locales depuis le Dashboard Supabase, puis creer/authentifier le foyer. Aucun secret serveur n'est requis par l'application.

## Phase 2 - Materialisation budget et revenus

- Creation confirmee des comptes, membres, enveloppes et ecritures issues des archives Phase 1.
- Mapping explicite des comptes source avant la materialisation du Journal dans le Grand Livre.
- Salaires, primes, charges fixes, cle variable et preparation mensuelle.
- Alimentations, transferts, rapprochements et reste a vivre.

## Phase 3 - Objectifs et organisation du foyer

- Shopping list, priorites, voiture, epargne et recuperations.
- Taches, routines, maintenance, calendrier et alertes.

## Phase 4 - Simulations, collaboration et restitution

- Credit immobilier, amortissement, remboursement anticipe, IR et participation employeur.
- Mode decision, patrimoine net, graphiques, export PDF/Excel et synchronisation hors connexion.
