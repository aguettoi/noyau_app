# CERT-L1H — clôture de la certification hostile de confidentialité

## Décision

CERT-L1H est `READY / CLOSED` au 16 novembre 2026. La certification combine
des contrôles hostiles serveur, des tests applicatifs et une recette humaine
multi-session A/B/C. Elle couvre les modes `visible`, `balance_hidden` et
`private`, leurs workflows de consentement et de révocation, ainsi que les
projections transverses réellement présentes dans le produit.

Cette clôture n'étend aucun droit. Un solde masqué reste absent ou nul au sens
de la projection (`null`), jamais remplacé par zéro. Un compte privé reste
invisible aux non-titulaires. L'administration du foyer ne contourne pas la
confidentialité personnelle.

## Preuves automatisées

- 14 contrôles hostiles serveur : PASS ;
- 47 tests ciblés de confidentialité des comptes : PASS ;
- 124 tests Dashboard, Assistant déterministe, anti-inférence et projections :
  PASS ;
- 19 tests portabilité, export et intégrité ZIP : PASS ;
- suite Flutter complète : 1 356 réussis, 3 ignorés conditionnels, 0 échec ;
- `flutter analyze` : PASS ;
- format des fichiers concernés : PASS ;
- Web Release Sandbox : PASS, empreinte `main.dart.js`
  `DD5A83A1CA3335DCC43D55DCFCCA04CBAB45254129C0F8C45F06F0BC291CB1CD`.

Les contrôles serveur couvrent le titulaire, le non-titulaire du même foyer,
un autre foyer, l'audience anonyme, l'administrateur de foyer non titulaire et
les écritures directes interdites. Les projections sécurisées, RPC, grants et
politiques RLS restent la source d'autorité.

## Preuves humaines A B C

Les blocs suivants ont été certifiés sur des sessions distinctes :

- accès initial A/B/C ;
- Cycle privé par défaut ;
- partage et révocation Cycle par B ;
- propagation Realtime Cycle A/B/C ;
- persistance, refresh et reconnexion Cycle ;
- absence de fuite Cycle dans Dashboard, recherche, Assistant déterministe,
  Analyses/KPI, alertes, exports, cache et navigation ;
- lecture initiale des trois modes de confidentialité des comptes ;
- demande, rejet, annulation, approbation et application ;
- retour au mode visible ;
- propagation Realtime de `balance_hidden` sans F5 ;
- propagation Realtime de `private` sans F5 ;
- Analyses/KPI sans valeur cachée ni substitution par zéro ;
- Assistant déterministe et alertes sans fuite ;
- export ZIP expurgé et intégralement lisible avec CRC valides ;
- cache/offline, reconnexion, navigation et refresh sans réapparition de données
  révoquées.

## Corrections consolidées

- UX canonique des modes `visible`, `balance_hidden` et `private` dans le détail
  d'un compte ;
- workflow borné de demande, consentement, refus, annulation et révocation ;
- projections de comptes et soldes vivantes, fail-closed pendant les refresh ;
- invalidation Realtime des comptes, soldes et demandes de confidentialité ;
- Analyses et Dashboard sans montant pour `balance_hidden`, et sans existence
  pour `private` ;
- exports respectant `can_read_balance=false` et `opening_balance=null` ;
- génération ZIP corrigée et vérifiée avec contrôle CRC strict ;
- Cycle personnel privé par défaut, partage limité aux dates et phases,
  révocation immédiate et i18n FR/EN/AR/ary avec RTL.

## Migrations additives

- `20261115105102_cycle_personal_tracking_enrichment.sql` ;
- `20261115111345_cycle_shared_projection_realtime_invalidation.sql` ;
- `20261115112538_cycle_share_upsert_privilege.sql` ;
- `20261115183000_cert_l1h_account_privacy_activation.sql` ;
- `20261115184500_cert_l1h_realtime_revision_fix.sql`.

Aucune migration historique n'est modifiée par la clôture. Aucune migration de
base financière, aucun changement C3/C4B, aucun import définitif, cutover ou
purge n'est réalisé.

## Fixtures et reproductibilité

Quatre comptes synthétiques à solde nul ont servi à la matrice humaine. Ils ont
été retirés du Sandbox après clôture : comptes, titulaires, réglages et demandes
associés sont tous à zéro ligne. Les
scripts `cert_l1h_account_privacy_fixture_setup.sql` et
`cert_l1h_account_privacy_fixture_cleanup.sql` sont conservés avec les tests
hostiles pour reproduire puis nettoyer la certification. Leur retrait ne
supprime ni les scripts ni les preuves.

## Résiduels V1 avant Design Freeze

Ces éléments ne sont pas certifiés PASS par CERT-L1H :

1. **Assistant conversationnel IA.** Obligatoire pour la V1 avant Design
   Freeze. Il complète l'Assistant déterministe existant sans le remplacer. Le
   contexte doit être filtré par L1 avant tout appel au modèle et toute action
   réelle doit rester explicitement confirmée.
2. **Informations Cycle autorisées dans le Dashboard.** Le propriétaire peut
   recevoir ses informations utiles ; un destinataire autorisé ne reçoit que
   les dates et phases explicitement partagées ; tout autre membre ne reçoit
   rien. Symptômes, notes, flux et autres observations intimes restent privés.
3. **Calendrier partagé autonome et intégration calendrier.** Le périmètre
   fonctionnel restant doit être confirmé. La surface autonome est absente et
   n'a pas été marquée PASS. Tout raccordement Cycle doit appliquer exactement
   le même filtrage et la même révocation immédiate que le Dashboard.

## Prochaine étape Roadmap Master V3

La Roadmap Master V3 place avant le Design Freeze strict les compléments
fonctionnels ciblés encore obligatoires. Le prochain lot recommandé est donc un
lot de fermeture fonctionnelle borné : audit et livraison de l'Assistant
conversationnel V1, décision puis raccordement sécurisé du Cycle au Dashboard
et au calendrier canonique, et fermeture des compléments KPI/régularisation
encore classés PARTIAL. Le Design Freeze ne commence qu'après stabilisation et
certification de ces fonctions.
