# F2 — Cycle transverse — dossier de certification technique

Date : 2026-11-22

Statut : CERTIFIED / CLOSED le 23 novembre 2026

## Contrat livré

- Le partage des dates/phases et le partage des prévisions sont deux consentements indépendants.
- Les prévisions sont privées par défaut, activées explicitement par propriétaire et destinataire, puis révocables.
- Une révocation invalide immédiatement les projections, le calendrier et le Dashboard via le canal Realtime sécurisé.
- Les symptômes, notes, flux et autres observations intimes ne figurent jamais dans la projection partagée.
- Les prévisions sont marquées comme estimations et incluent un niveau d'incertitude ; elles ne constituent ni diagnostic ni méthode contraceptive.
- Le moteur déterministe `cycle-v2.0.0` est versionné, explicable et indépendant de toute IA générative.
- Le moteur s'abstient lorsque l'historique est insuffisant, incohérent ou excessivement instable.
- Le backtesting walk-forward interdit toute utilisation de données futures.

## Surfaces

- Dashboard : aperçu discret des informations Cycle autorisées.
- Calendrier canonique : source Cycle intégrée à `/household/calendar`, sans second calendrier.
- Espace propriétaire : historique, observations, prévisions et incertitude distingués.
- Consentements : contrôles séparés pour dates/phases et prévisions.
- Realtime : invalidation des consentements, projections, calendrier et Dashboard.

## Sécurité et migrations

- `20261121221356_f2_cycle_forecast_consent.sql`
  - table RLS `member_cycle_forecast_shares` ;
  - projection minimisée `read_authorized_cycle_timeline` ;
  - droits `authenticated` uniquement ;
  - trigger d'invalidation sécurisé.
- `20261121222027_f2_cycle_forecast_active_participant_policy.sql`
  - lecture des métadonnées de consentement limitée aux membres actifs.
- `20261121224551_f2_cycle_engine_v2.sql`
  - projection v2 avec abstention et métadonnées de qualité ;
  - distinction règles, ovulation et fenêtre fertile estimées ;
  - saisies privées structurées LH/BBT.
- `20261121224750_f2_cycle_measurement_constraints.sql`
  - contraintes strictes sur les saisies LH/BBT ;
  - interdiction d'utiliser ces champs pour une autre catégorie.

Les migrations sont additives. Aucune migration historique n'est modifiée par F2.

## Preuves automatiques

- Contrôles hostiles Sandbox : propriétaire, destinataire, administrateur non autorisé, autre foyer et révocation — PASS.
- Tests F2/CERT-L1H impactés : 112 PASS, 1 SKIP conditionnel.
- Benchmark synthétique : 9 scénarios, 64 prédictions walk-forward, 2 abstentions attendues.
- MAE historique agrégée par confiance finale : haute 0,725 j ; moyenne 2,875 j ; basse 6,667 j.
- Suite Flutter : 1 425 PASS, 3 SKIP conditionnels, 0 FAIL.
- `flutter analyze` : PASS.
- Format des fichiers F2 : PASS.
- Builds Release Web, Windows et Android : PASS.

## Certification humaine finale

- Recette A/B du 23 novembre 2026 : PASS.
- Consentements indépendants, partage et révocation sans F5 : PASS.
- Refresh, reconnexion et absence de réapparition depuis le cache : PASS.
- Calendrier transverse et absence de données intimes chez B : PASS.
- FR et AR/RTL : PASS fonctionnel.
- Preuve complète : `docs/F2_CYCLE_CLOSURE_2026-11-23.md`.

## Invariants

- Aucune mutation financière.
- Aucun changement C3/C4B.
- F1 reste figé NOT READY ; aucun appel provider IA n'a été ajouté par F2.
