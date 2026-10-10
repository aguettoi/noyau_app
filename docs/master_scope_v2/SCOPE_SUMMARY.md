# Résumé exécutif du Master Scope V2

## Résultat

Le socle F1 à F8 couvre les moteurs financiers et la majorité des workflows quotidiens. Le travail restant ne justifie pas de reconstruire la comptabilité : il concerne surtout l’orchestration de la clôture mensuelle, la projection, les restitutions, l’expérience produit et, sous réserve d’arbitrage, l’offline et la confidentialité fine.

| Mesure | Nombre |
|---|---:|
| Fonctions analysées | 132 |
| COUVERTE | 69 |
| PARTIELLE | 13 |
| ABSENTE | 27 |
| À ÉTENDRE | 16 |
| À ARBITRER | 5 |
| POST-V1 | 2 |
| P0 | 79 |
| P1 | 34 |
| P2 | 19 |

Les niveaux de priorité décrivent la criticité dans la trajectoire complète, y compris les fonctions déjà couvertes à protéger. Ils ne représentent donc pas uniquement le backlog.

## P0 restant

- Clôture mensuelle guidée, score de fiabilité, close/reopen audités.
- Centre À faire financier complet.
- Régularisation globale membre, compte, enveloppe et minimisation des virements.
- Décision explicite sur le caractère obligatoire ou non de l’offline au lancement.
- Gel R8, audit A1/A2 et cutover final après certification.

## P1 restant

- Récurrents et projection de trésorerie J+30/J+90.
- KPI qualité de saisie, rapprochement et justificatifs.
- Exports structurés, rapports périodiques, bilan annuel et simulateur d’emprunt enrichi.
- Onboarding métier, Auth e-mail/deep links et notifications natives.
- Certification Windows, Web et Android.

## P2 et arbitrages

- PowerPoint, aide/tutoriels, multilingue, landing page et commandes rapides.
- Organisation ménage enrichie uniquement selon les usages encore actifs du Sheet.
- Cycle menstruel, IA, confidentialité fine et restauration de sauvegarde après décision formelle.
- iOS réel et inventaire caisse par coupures peuvent rester post-V1 selon la décision de lancement.

## Contrôles croisés

- 74 surfaces significatives de l’audit UI/UX rapprochées des fonctions et routes.
- 58 routes/états logiques et 20 workflows rapprochés du scope.
- 93 migrations inventoriées et preuves ciblées citées.
- 32 feuilles du classeur Cutover certifié classées par fonction, remplacement ou archive.
- Aucun moteur financier V1 utile ne doit être redéveloppé.
- Les fonctions moins visibles sont accessibles; leur découvrabilité relève de R1/D1.

## Moteurs à réutiliser

FinancialEvent, Grand Ledger, envelope ledger, obligations, Budget Intelligence, FinancialAvailability, Scenarios, Objectives, Calendar/Alerts F6, Search/Exports/Realtime F7 et financing F5.

## Verdict

Le Master Scope Final V2 est prêt comme référence fonctionnelle jusqu’au gel. Il doit être mis à jour par changement de statut après chaque vague, sans effacer l’historique des décisions.
