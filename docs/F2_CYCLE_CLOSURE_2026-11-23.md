# F2 — Cycle transverse — clôture

Date : 23 novembre 2026

Statut : `F2 CERTIFIED / CLOSED`

## Périmètre certifié

F2 étend le domaine Cycle canonique sans créer de second moteur ni de second
calendrier. Il livre un moteur déterministe versionné, une projection minimisée
commune au Dashboard et au calendrier, ainsi que deux consentements totalement
indépendants : dates/phases et prévisions.

Les prévisions sont des estimations non médicales. Elles ne constituent ni un
diagnostic, ni une preuve d'ovulation, ni une méthode contraceptive.

## Architecture fonctionnelle

- Moteur `cycle-v2.0.0`, déterministe et sans IA générative.
- Backtesting walk-forward sans accès aux observations futures.
- Prévision menstruelle, ovulation estimée et fenêtre fertile estimée séparées.
- Abstention explicite si l'historique est insuffisant, incohérent ou trop
  instable.
- Niveau de confiance, régularité, taille d'échantillon, variabilité et
  incertitude transportés avec les projections.
- Source Cycle intégrée au calendrier canonique `/household/calendar`.
- Aperçu Cycle discret sur le Dashboard selon les droits du lecteur.
- Invalidation Realtime des événements, consentements et projections.

## Consentements et confidentialité

- Dates/phases et prévisions utilisent deux consentements indépendants.
- Les deux sont désactivés par défaut.
- Le partage dates/phases n'accorde jamais le partage des prévisions.
- La révocation des prévisions conserve les dates/phases si leur consentement
  reste actif.
- Les symptômes, notes, flux, LH, BBT, contraception, intimité et autres
  observations personnelles ne figurent jamais dans la projection partagée.
- Le propriétaire reste le seul lecteur et auteur des entrées privées.
- Un administrateur non propriétaire, un membre non autorisé, un autre foyer et
  l'audience anonyme ne peuvent pas contourner ces règles.

## Matrice finale

| Contrôle | Automatisé | Humain | Résultat | Preuve | Statut final |
|---|---:|---:|---|---|---|
| Observations réelles propriétaire | Oui | Oui | 7 périodes rendues | Tests moteur + Nora | PASS |
| Prévisions propriétaire | Oui | Oui | Règles, ovulation et fenêtre fertile visibles comme estimations | Moteur v2 + Nora | PASS |
| Consentement dates/phases OFF | Oui | Oui | B ne reçoit aucune observation | SQL/RLS + A/B | PASS |
| Consentement dates/phases ON | Oui | Oui | 7 observations apparaissent chez B sans F5 | Realtime A/B | PASS |
| Consentement prévisions OFF | Oui | Oui | B ne reçoit aucune prévision | SQL/RLS + A/B | PASS |
| Consentement prévisions ON | Oui | Oui | 3 prévisions apparaissent chez B sans F5 | Realtime A/B | PASS |
| Révocation sélective des prévisions | Oui | Oui | Prévisions supprimées, observations conservées | Realtime A/B | PASS |
| Realtime | Oui | Oui | Propagation partage/révocation sans F5 | Provider + recette | PASS |
| Refresh | Oui | Oui | Prévisions révoquées absentes | Recette B | PASS |
| Déconnexion/reconnexion | Oui | Oui | Aucune résurrection | Recette B | PASS |
| Cache/offline après révocation | Oui | Partiel | Contrats automatisés et reconnexion humaine ; aucune campagne de saisie Cycle offline | Tests cache + reconnexion | PASS pour le contrat F2 borné |
| Calendrier transverse | Oui | Oui | 7 observations, aucune prévision révoquée, autres sources conservées | Calendrier B | PASS |
| Symptômes | Oui | Oui | Absents chez B | SQL/RLS + recette | PASS |
| Notes | Oui | Oui | Absentes chez B | SQL/RLS + recette | PASS |
| Flux | Oui | Oui | Absent chez B | SQL/RLS + recette | PASS |
| LH | Oui | Oui par absence | Donnée owner-only, jamais projetée | Contraintes + inspection B | PASS |
| BBT | Oui | Oui par absence | Donnée owner-only, jamais projetée | Contraintes + inspection B | PASS |
| Autre membre du foyer non autorisé | Oui | Non rejoué | Aucun accès selon RLS hostile | Test SQL | PASS automatisé |
| Administrateur non propriétaire | Oui | Non rejoué | Aucun contournement | Test SQL | PASS automatisé |
| Autre foyer | Oui | Non rejoué | Aucun accès | Test SQL | PASS automatisé |
| Audience anonyme | Oui | Non rejoué | Aucun accès/RPC | Grants + test SQL | PASS automatisé |
| FR | Oui | Oui | Libellés et distinction observation/estimation lisibles | Goldens + recette | PASS |
| AR/RTL | Oui | Oui | RTL, navigation et contenu Cycle fonctionnels, sans overflow bloquant | Golden + recette | PASS |

## Preuves automatisées

- Tests F2/CERT-L1H impactés : 112 PASS, 1 SKIP conditionnel.
- Suite Flutter consolidée : 1 425 PASS, 3 SKIP conditionnels, 0 FAIL.
- Goldens Cycle : 27/27 PASS.
- Contrôles SQL hostiles F2 : PASS.
- `flutter analyze` : PASS.
- Format F2 et `git diff --check` : PASS.
- Builds Release Web, Windows et Android : PASS.

## Benchmark et calibration

- 9 scénarios synthétiques : régulier, court, long, variable, tendances,
  incomplet, instable et incohérent.
- 64 prédictions walk-forward.
- 2 abstentions attendues et déclenchées.
- MAE agrégée par confiance finale : haute 0,725 jour ; moyenne 2,875 jours ;
  basse 6,667 jours.
- Mesures MAE, biais moyen et taux à ±1, ±2 et ±3 jours conservées dans le
  benchmark. Aucune revendication de performance clinique ou comparative.

## Recette humaine du 23 novembre 2026

Sessions : Nora, propriétaire (A), et Ibrahim, membre actif du même foyer (B).

- A a vu 7 périodes historiques et les 3 estimations avec une incertitude de
  ±3 jours.
- Consentements initialement OFF : aucune observation ni prévision chez B.
- Dates/phases seules : 7 observations chez B sans F5, aucune prévision.
- Prévisions activées séparément : les 3 estimations sont apparues sans F5.
- Révocation des prévisions seulement : disparition immédiate des estimations,
  maintien des dates/phases.
- Refresh puis reconnexion : aucune résurrection des prévisions révoquées.
- Calendrier canonique : observations partagées présentes, prévisions révoquées
  absentes, autres événements du foyer conservés.
- FR puis arabe/RTL : PASS fonctionnel, aucune fuite intime ou obstruction
  fonctionnelle observée.

## Fixture fictive et nettoyage

La certification a ajouté exclusivement cinq événements `period` fictifs à la
propriétaire Nora dans le Sandbox, sans flux, symptômes, notes, LH ni BBT :

- `f2c1e000-0000-4000-8000-000000000001` — 2026-06-07 ;
- `f2c1e000-0000-4000-8000-000000000002` — 2026-07-05 ;
- `f2c1e000-0000-4000-8000-000000000003` — 2026-08-02 ;
- `f2c1e000-0000-4000-8000-000000000004` — 2026-08-30 ;
- `f2c1e000-0000-4000-8000-000000000005` — 2026-09-27.

Les événements préexistants des 25 octobre et 16 novembre 2026 ne font pas
partie de la fixture et doivent être conservés. Le consentement dates/phases
créé pour la recette doit être retiré avec la fixture ; le consentement des
prévisions avait déjà été révoqué pendant la recette.

Nettoyage exécuté après enregistrement de cette preuve :

- 5 événements fictifs supprimés par UUID ;
- consentement dates/phases de recette supprimé ;
- aucun consentement prévisions ne subsistait après la révocation humaine ;
- 2 périodes préexistantes conservées ;
- contrôle post-nettoyage : 0 ligne de fixture, 0 consentement dates/phases et
  0 consentement prévisions Nora vers Ibrahim.

## Migrations F2

- `20261121221356_f2_cycle_forecast_consent.sql` ;
- `20261121222027_f2_cycle_forecast_active_participant_policy.sql` ;
- `20261121224551_f2_cycle_engine_v2.sql` ;
- `20261121224750_f2_cycle_measurement_constraints.sql`.

Les quatre migrations sont additives, présentes localement et appliquées au
Sandbox sous les mêmes versions. Aucune migration historique n'est modifiée
fonctionnellement par F2.

## Limites et dette reportée

- La recette certifie la fonctionnalité et la confidentialité, pas la justesse
  biologique d'une estimation individuelle.
- Aucun diagnostic, conseil médical ou garantie contraceptive n'est fourni.
- Le design actuel n'est pas considéré comme validé. Sa finition premium,
  hiérarchie, densité et cohérence visuelle restent explicitement reportées au
  Design Freeze/refonte UI-UX ultérieure.
- iOS reste limité à la configuration tant qu'aucun runtime Apple n'est
  disponible.

## Verdict

Toutes les obligations fonctionnelles et de confidentialité F2 disposent d'une
preuve automatisée ou humaine proportionnée. Les consentements indépendants,
la révocation Realtime, la persistance après reconnexion, le calendrier
transverse et l'absence de données intimes chez le destinataire sont certifiés.

**F2 CERTIFIED / CLOSED**
