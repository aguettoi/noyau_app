# Analyse exhaustive Google Sheet vers application

## Sources analysées

L’analyse porte sur SIMULATION.xlsx, SIMULATION 210926 POUR CODEX.xlsx et le classeur Cutover certifié du 29 septembre 2026. Le dernier contient 32 feuilles. Les décisions ci-dessous reposent sur les données, formules et relations observées, pas uniquement sur les noms d’onglets.

## Matrice fonctionnelle

| Fonction Sheet | Feuilles | Équivalent application | Statut | Différence | Décision proposée |
|---|---|---|---|---|---|
| Journal quotidien signé | Journal | FinancialEvent, Grand Ledger, historique | COUVERTE | Le Sheet mélange alimentation et dépense; l'app sépare les événements | DÉJÀ MIEUX COUVERT |
| Solde des enveloppes | Enveloppes | Envelope ledger et page Enveloppes | COUVERTE | Formules remplacées par journal append-only | DÉJÀ MIEUX COUVERT |
| Soldes banques et espèces | Enveloppes, TDB | Comptes, GL, inventaires | COUVERTE | Le Sheet juxtapose réel et théorique; l'app conserve les constats | DÉJÀ MIEUX COUVERT |
| Tableau de bord | TDB | Dashboard V2 | COUVERTE | L'app évite le double comptage comptes/enveloppes | DÉJÀ MIEUX COUVERT |
| Scénarios salariaux | SCENARIOS, Test Nv salaires, variantes | Budget Intelligence et Scenarios | COUVERTE | Les feuilles dupliquent des versions; l'app versionne les règles | DÉJÀ MIEUX COUVERT |
| Charges fixes et communes | SCENARIOS, variantes salaires | Règles programmables et contributions | COUVERTE | Clés N membres et approbations plus robustes | DÉJÀ MIEUX COUVERT |
| Répartition membres | SCENARIOS | BudgetContributionCalculator | COUVERTE | Règles génériques 1/2/N | DÉJÀ MIEUX COUVERT |
| Compte recommandé par enveloppe | Feuille 16 | PAY-01/PAY-03 | COUVERTE | Les X et IF deviennent des références structurées | DÉJÀ MIEUX COUVERT |
| Enveloppe sur plusieurs comptes | Feuille 16 | Funding multi-comptes | PARTIELLE | Pas de matrice cible durable pour clôture | REPRENDRE AUTREMENT en R2 |
| Shopping list | Shopping list | Shopping List | COUVERTE | Cycle d’achat et dépense canonique ajoutés | DÉJÀ MIEUX COUVERT |
| Priorités | PRIOS | PRIOS et FinancialAvailability | COUVERTE | Cascade canonique et historique | DÉJÀ MIEUX COUVERT |
| Projets et objectifs | PRIOS, Dépenses à fin Juillet | Objectifs, Shopping, PRIOS | COUVERTE | Modules séparés reliés sans double comptage | DÉJÀ MIEUX COUVERT |
| Acquisition voiture | Acquisit voiture | Asset véhicule, financement, objectif, TCO | COUVERTE | Modèle générique lié aux obligations | DÉJÀ MIEUX COUVERT |
| Coûts auto/km | PLANNING EMPRUNT 55K | AUTO-01, coûts, kilométrage | PARTIELLE | Certaines hypothèses km/carburant du Sheet ne sont pas reprises | À confirmer puis REPRENDRE AUTREMENT |
| Prêt familial 55K | PLANNING EMPRUNT 55K | Obligations et financement F5 | COUVERTE | Les lignes OK sont remplacées par settlements dérivés | DÉJÀ MIEUX COUVERT |
| Organisation ménage | Orga ménage | F6 tâches, routines, responsables, calendrier | À ÉTENDRE | Durée, pièce, nombre de personnes et charge restent partiels | REPRENDRE AUTREMENT |
| Budget courses | Journal, Enveloppes, scénarios | Budget et enveloppe Courses | COUVERTE | Aucun module courses séparé n'est nécessaire | CONSERVER TEL QUEL |
| Simulations prêts 180/240 mois | SIMULATION EMPRUNT 180/240 et banques | Moteur financement F5 | À ÉTENDRE | Entrée par échéance cible et comparaison multi-offres à enrichir | REPRENDRE AUTREMENT |
| Murabaha Arreda | SIMULATION EMPRUNT ARREDA | HOME-01 et financement murabaha | COUVERTE | Réel/projeté séparés et obligation canonique | DÉJÀ MIEUX COUVERT |
| Remboursement anticipé | Simulations Arreda | Simulateur F5 | COUVERTE | Réduction durée/échéance sans écriture | DÉJÀ MIEUX COUVERT |
| Impact fiscal IR | Simulations Arreda | HOME-02 paramétrable | À ÉTENDRE | Règles retenues, versionnement et export fiscal à cadrer | REPRENDRE AUTREMENT |
| Contribution employeur | Simulations Arreda | HOME-02 | COUVERTE | Projeté et réel séparés | DÉJÀ MIEUX COUVERT |
| Frais notaire | SIMULATION NOTAIRE | Hypothèses logement/scénarios | À ARBITRER | Aucun calculateur dédié | Garder comme hypothèse sauf usage récurrent |
| Vente appartement | SIMULATION VENTE APPARTEMENT | Scenarios, patrimoine, valorisations | PARTIELLE | Comparaison de vente détaillée non dédiée | REPRENDRE via Scenarios |
| Comparaison banques | COMPARAISON | Scenarios et financing profiles | À ÉTENDRE | Comparateur multi-offres UX incomplet | REPRENDRE AUTREMENT |
| Ancien programme | ANCIEN PROGRAMME | Shopping, Objectifs, PRIOS, Scenarios | POST-V1 | Archive remplacée par les moteurs actuels | ABANDONNER comme moteur |
| Mapping import | MAPPING | Assistant Import/Cutover | COUVERTE | Empreinte, preview, décisions et idempotence ajoutées | DÉJÀ MIEUX COUVERT |
| Historique financier | Journal | C4B historique analytique | COUVERTE | Historique séparé du financier réel | DÉJÀ MIEUX COUVERT |
| Inventaire comptes/caisse | Enveloppes, TDB | Constats et rapprochements | COUVERTE | Snapshot et résolution auditables | DÉJÀ MIEUX COUVERT |
| Compensation entre membres | Répartition manuelle implicite | Compensations F3 | COUVERTE | Workflow débiteur/créancier, transfert et réception | DÉJÀ MIEUX COUVERT |
| Dettes et créances | Plannings, Journal | Obligations, Recovery, settlements | COUVERTE | Remaining dérivé, write-off et reversal | DÉJÀ MIEUX COUVERT |
| Cycle de clôture mensuelle | Implicite TDB/Journal/Enveloppes | Briques disponibles, orchestration absente | ABSENTE | Pas de clôture, réouverture ni score | R2 |
| Récurrents/abonnements | Charges fixes | Budget fixe seulement | ABSENTE | Pas d’attendu/réel/variation opérationnelle | R3 |
| Projection de trésorerie datée | Scénarios et prêts | FinancialAvailability partiel | ABSENTE | Pas de cashflow J+30/J+90 consolidé | R3 |
| Rapports périodiques | TDB et feuilles de synthèse | Exports F7 | À ÉTENDRE | Modèles mensuel/annuel/PPTX absents | R4 |

## Inventaire des 32 feuilles du classeur certifié

- Référentiels/configuration : MAPPING, SCENARIOS.
- Scénarios salariaux : Test Nv salaires et six variantes, dont Feuille 25/26.
- Pilotage : TDB.
- Projets : Shopping list, PRIOS, Dépenses à fin Juillet 2026.
- Opérations : Journal, Enveloppes, Feuille 16.
- Organisation : Orga ménage.
- Financements : PLANNING EMPRUNT 55K, sept simulations 180/240 mois, deux simulations Arreda.
- Immobilier : SIMULATION NOTAIRE, SIMULATION VENTE APPARTEMENT, COMPARAISON.
- Historique : ANCIEN PROGRAMME, Acquisit voiture.

## Fonctions à ne pas recopier

1. Les variantes salaires sont des versions de scénario : Budget Intelligence les remplace.
2. Les feuilles par banque partagent un moteur mathématique : étendre F5, ne pas créer un moteur par banque.
3. ANCIEN PROGRAMME reste une archive, pas une source de mutation.
4. TDB est une inspiration de pilotage, pas un contrat visuel.
5. Notaire, vente et comparaison restent des simulations tant qu’aucune décision réelle n’est confirmée.

## Écarts Sheet encore pertinents

- Clôture mensuelle guidée et score de fiabilité.
- Matrice cible enveloppes/comptes pour la régularisation globale.
- Hypothèses auto/km et charge de travail ménage, uniquement si encore utilisées.
- Comparateur multi-offres, entrée par échéance cible et impact fiscal versionné.
- Projection de trésorerie datée et récurrents confirmables.
