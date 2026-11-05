# D1.2-G — Plus, import rapide, administration et support

Baseline : `b755142951492d01a66c586cd71665b1beaad293`.

## Matrice de destination

| Fonction historique | Surface conservée | Destination D1.2-G |
|---|---|---|
| Assistant L5 | `AssistantPage` | Plus > Outils > Assistant |
| Reporting périodique | `BusinessReportingPanel` | Plus > Outils > Rapports |
| Exports et reconstruction L2.8 | `PortabilityPage` | Plus > Outils > Portabilité et sauvegarde |
| Imports CSV historiques | `ImportsPage` | Imports > Import avancé |
| Import classeur/cutover | `ImportPreviewPage` | Imports > Import avancé |
| IMP-BULK | nouveau parcours, moteur financier canonique | Imports > Import rapide Excel |
| Membres et invitations | `HouseholdMembersDialog` | Plus > Foyer et accès > Membres |
| Langue, foyer, moyens de paiement | `HouseholdSettingsPage` | Plus > Application > Paramètres |
| Tutoriels | `HelpCenterPage` | Plus > Application > Aide |
| Configuration progressive | `GuidedOnboardingPage` | Plus > Application > Reprendre la configuration |

Aucune fonction historique n'est supprimée. Rapports, portabilité, import rapide et import avancé sont désormais distingués.

## Contrat IMP-BULK

Le modèle officiel `FINANCIEL_PILOTE_import_rapide.xlsx` n'expose aucun UUID. Le parseur contrôle la structure, les dates, les montants, la devise, les références métier et les doublons internes. Les erreurs sont bloquantes avant confirmation ; les références membre/compte/enveloppe peuvent être corrigées explicitement en masse.

La présentation ne réalise aucune écriture directe. Après confirmation explicite seulement, `quick_bulk_import_financial_events` :

- revalide le foyer, les droits et toutes les lignes avant la première écriture ;
- limite le lot à 500 opérations et à la devise MAD, cohérente avec les moteurs actuels ;
- refuse un compte non découvrable afin de préserver L1 ;
- résout les références métier côté serveur ;
- appelle exclusivement les RPC canoniques de dépense/revenu ;
- dérive une clé stable par ligne depuis l'empreinte du fichier ;
- bénéficie de l'atomicité PostgreSQL : toute erreur annule le lot entier.

IMP-BULK n'est ni l'import avancé, ni une restauration, ni le cutover Google Sheet. Aucun import réel, aucune purge et aucune donnée pilote ne sont exécutés pendant D1.2-G.

## Dette explicitement hors lot

Les formats d'export L2.6/L2.8 et l'assistant L5 sont réutilisés sans reconstruction. La certification plateforme réelle reste P1. L'audit architectural global reste différé conformément au chemin critique.
