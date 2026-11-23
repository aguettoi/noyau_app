# F2 — Cycle transverse — cadrage factuel avant GO

Date de référence : 21 novembre 2026

## Décision de périmètre

F2 réutilise le domaine Cycle L3B existant. Il ne crée ni second moteur Cycle, ni calendrier concurrent, ni élargissement implicite du partage. Il ne constitue pas le Design Freeze.

## 1. État fonctionnel existant

Le produit dispose déjà des éléments suivants :

- événements Cycle personnels avec début, fin, phase, flux, symptômes et notes ;
- historique personnel et archivage ;
- moteur de prévision explicable basé sur l'historique individuel, avec moyenne, variabilité, plage de prochaine période, plage d'ovulation estimée et niveau de confiance ;
- augmentation de l'incertitude lorsque l'historique est insuffisant ou irrégulier ;
- avertissement indiquant que les estimations de fertilité ne constituent ni une certitude médicale ni une méthode contraceptive ;
- journal strictement propriétaire pour symptômes, humeur, sommeil, énergie, stress, libido, peau, appétit, digestion, pertes, température, poids, spotting, contraception et intimité ;
- saisie propriétaire générique de contraception et d'intimité ;
- partage volontaire et révocable des **dates et phases uniquement** ;
- projection serveur partagée filtrée et invalidation Realtime ;
- affichage des événements partagés dans la surface Cycle ;
- contexte Assistant limité aux projections Cycle autorisées ;
- FR, EN, AR et ary, avec RTL ;
- protections RLS propriétaire et exclusions des journaux intimes des exports foyer, recherches, alertes, Assistant d'un autre membre et projections partagées.

CERT-L1H a certifié humainement et automatiquement le partage/révocation A/B/C, la propagation Realtime, la persistance/reconnexion et l'absence de fuite transverse sur le contrat actuel.

## 2. Écarts F2 exacts

### Dashboard

- Les projections Cycle autorisées n'alimentent pas encore le Dashboard canonique.
- Le propriétaire doit pouvoir voir une information utile et discrète issue de ses données autorisées.
- Un destinataire autorisé ne peut voir que ce que son consentement lui permet ; avec le contrat actuel, cela reste limité aux dates et phases.
- Un membre non autorisé ou d'un autre foyer ne doit recevoir aucune information ni signal d'existence.

### Prévisions et consentement

- Les prévisions personnelles existent, mais leur partage n'est pas couvert par le consentement actuel.
- `partage dates/phases` ne vaut pas `partage des prévisions`.
- F2 doit décider explicitement entre :
  1. conserver les prévisions strictement propriétaire ;
  2. ajouter un consentement distinct, explicite, limité et immédiatement révocable pour certaines prévisions.
- Sans décision explicite, aucune prévision ne sera projetée chez un autre membre.

### Calendrier canonique

- Un calendrier canonique du foyer existe déjà sous `/household/calendar` et agrège plusieurs sources.
- Les événements Cycle ne sont pas encore une source de ce calendrier canonique.
- La carte appelée « calendrier partagé » dans la surface Cycle est une liste locale des événements partagés, pas une intégration au calendrier canonique.
- F2 doit intégrer, sauf impossibilité démontrée, une source Cycle filtrée selon les droits dans ce calendrier existant, sans créer un calendrier Cycle parallèle.

### Richesse fonctionnelle encore partielle

- Le journal privé repose aujourd'hui sur `category + payload + notes` et une saisie générique ; les concepts structurés détaillés (méthode contraceptive, prise/oubli/retard, rapport protégé/non protégé, intensités et tendances) ne disposent pas tous d'une UX ou d'un schéma de validation métier dédié.
- L'historique et les prévisions existent, mais les analyses personnelles riches demandées — tendances, comparaison multi-cycle, symptômes par phase, évolution du flux, retards/avances, qualité des données — restent à consolider.
- La timeline/calendrier personnel ne distingue pas encore complètement observations, prévisions, incertitude et catégories privées dans une vue unifiée.

## 3. Changements prévus

1. Formaliser un modèle de projection Cycle autorisée unique, consommable par Dashboard et calendrier, avec provenance, propriétaire, niveau d'autorisation, caractère observé/prédit et incertitude.
2. Raccorder cette projection au Dashboard de façon minimale et discrète, sans redesign général.
3. Ajouter Cycle comme source du calendrier canonique, filtrée côté serveur/application selon les droits, avec disparition immédiate après révocation.
4. Décider puis implémenter le contrat de consentement des prévisions ; par défaut, elles restent propriétaire uniquement.
5. Compléter les saisies et analyses personnelles manquantes en réutilisant le journal propriétaire actuel, sans rendre partageable une catégorie intime.
6. Conserver une distinction visuelle et sémantique stricte entre observation et estimation, avec incertitude et avertissement non médical.
7. Raccorder Realtime, refresh, cache/offline et navigation aux nouvelles projections sans exposer de données privées résiduelles.

## 4. Migrations éventuelles

Le cadrage ne justifie pas encore une migration certaine.

- **Aucune migration nécessaire** si Dashboard et calendrier peuvent consommer les projections/RPC existants et si le `payload` propriétaire actuel suffit aux nouvelles saisies.
- **Migration additive seulement** si une décision produit exige :
  - un consentement distinct pour les prévisions ;
  - une projection serveur dédiée au calendrier canonique ;
  - des champs structurés dont la validation ne peut pas être sûre dans le `payload` actuel.
- Toute migration éventuelle devra être nouvelle, additive, RLS-first et révocable. Aucune migration historique ne devra être modifiée.
- Les nouvelles données intimes resteront owner-only côté serveur ; elles ne devront jamais être intégrées à une projection foyer brute.

## 5. Tests et certifications nécessaires

### Automatisés

- prévisions : historique insuffisant, régulier, irrégulier, dates limites, recalcul, observation versus estimation, incertitude ;
- journal privé : création, modification, archivage et validation de chaque catégorie structurée retenue ;
- RLS hostile : propriétaire, membre autorisé, membre non autorisé, autre foyer et anon ;
- partage/révocation : dates/phases, éventuel consentement prévisions distinct, non-rétroactivité et disparition Realtime ;
- Dashboard : propriétaire, autorisé, non autorisé, autre foyer, cache périmé et révocation ;
- calendrier canonique : mêmes profils, filtres, navigation, refresh, offline et suppression immédiate après révocation ;
- anti-inférence : recherche, Assistant, exports, alertes, notifications, KPI, Dashboard, calendrier, cache/offline et Realtime ;
- aucune apparition de symptômes, notes, flux, libido, pertes, contraception, rapports sexuels, protection, température, poids ou autres observations intimes hors du propriétaire ;
- i18n FR/EN/AR/ary, RTL, dates, accessibilité, responsive et dark ;
- non-régression CERT-L1H ciblée et suite Flutter consolidée, analyze, format et builds concernés.

### Humains

- matrice A/B/C sur Dashboard et calendrier : partage, visibilité limitée, révocation sans F5, refresh et reconnexion ;
- propriétaire : compréhension des observations/prévisions et de l'incertitude ;
- consentement éventuel des prévisions : libellé explicite, granularité et révocation ;
- preuve visuelle que les informations intimes n'apparaissent sur aucune surface destinataire ;
- FR/EN/AR/ary et RTL sur les nouvelles surfaces ;
- Web, Windows et Android ; iOS limité à la configuration tant qu'aucun runtime iOS n'est disponible.

## 6. Impacts confidentialité / CERT-L1H

- Le contrat certifié reste la borne minimale : privé par défaut, dates/phases partageables volontairement, révocation immédiate, données intimes strictement privées.
- Ajouter Dashboard ou calendrier crée de nouveaux consommateurs et impose une recertification hostile ciblée de ces projections.
- Étendre le partage aux prévisions modifie le contrat d'autorisation : cela exige un consentement séparé et la réouverture ciblée de CERT-L1H sur partage, révocation, Realtime, cache/offline et anti-inférence.
- Une simple dissimulation Flutter est insuffisante : le client non autorisé ne doit pas recevoir les valeurs.
- Aucune estimation d'ovulation ou de fertilité ne doit être présentée comme diagnostic, certitude ou contraception.

## 7. Plan d'exécution minimal

1. **Décision de contrat** : confirmer si les prévisions restent owner-only ou deviennent partageables par consentement distinct.
2. **Contrat de projection** : définir les DTO/capabilities Cycle autorisés et leurs règles de minimisation.
3. **Tests de sécurité d'abord** : figer les cas propriétaire/autorisé/non autorisé/autre foyer et les interdictions d'inférence.
4. **Backend minimal** : réutiliser l'existant ; ajouter uniquement les migrations/RPC indispensables et additives.
5. **Application** : providers uniques pour Dashboard et calendrier, invalidations Realtime et cache sûr.
6. **Présentation minimale** : Dashboard discret, source Cycle du calendrier canonique, saisies/analyses personnelles manquantes ; aucun redesign global.
7. **Non-régression** : Cycle, Dashboard, calendrier, Assistant, exports, recherche, notifications, offline et plateformes.
8. **Certification humaine A/B/C** : partage, révocation, anti-fuite et compréhension des prévisions.
9. **Clôture** : documentation, revue du diff, tests consolidés et verdict F2 avant Design Freeze.

## Gate avant code

Aucun code F2 ne doit commencer avant validation explicite de ce cadrage et décision sur le partage des prévisions.
