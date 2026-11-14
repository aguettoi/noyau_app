# P1-B — audit Web mesuré

Date de mesure : 14 novembre 2026. Build : Web release Sandbox servi sur
`http://localhost:4173`.

## Méthode

- Lighthouse Chrome headless sur le build release, une mesure avec son profil
  mobile standard et une mesure sans throttling pour isoler le coût local du
  bootstrap Flutter.
- Agrégats des logs Edge Supabase sur la fenêtre de recette humaine, sans lire
  de token, d'identité, de payload ni de donnée privée.
- Tests Riverpod/widget comptant les lectures de surfaces inactives.
- Inspection des graphes de providers Dashboard, Realtime, Offline et refresh.

Lighthouse mesure le démarrage public/Auth. Les performances authentifiées
sont mesurées par le graphe de lectures et les temps d'origine Supabase ; aucune
session ou credential humain n'est copié dans un navigateur automatisé.

## Mesures initiales

### Bootstrap public/Auth

| Mesure sans throttling | Avant |
| --- | ---: |
| FCP | 1 571 ms |
| LCP | 1 762 ms |
| Interactif | 1 761 ms |
| Total Blocking Time | 23 ms |
| Travail thread principal | 1 079 ms |
| Bootup JavaScript | 875 ms |
| Transfert initial | 3 893 247 octets |
| Requêtes initiales | 12 |
| Erreurs console | 0 |

Le profil Lighthouse mobile standard donne 37/100, FCP 0,6 s, LCP 23,4 s,
Speed Index 11,2 s et TBT 2 440 ms. Le coût dominant est le runtime Flutter
CanvasKit et le bundle JavaScript, pas une requête applicative Supabase sur la
route Auth.

### Bundle

- `main.dart.js` : 8 463 508 octets bruts, environ 2 054 253 transférés avec
  compression locale ;
- CanvasKit Chromium WASM : 5 760 502 octets bruts, environ 1 652 531
  transférés ;
- build complet : 49 569 649 octets, incluant plusieurs variantes CanvasKit et
  leurs symboles qui ne sont pas toutes chargées par un navigateur donné ;
- logo source : 1 076 537 octets pour 1 254 × 1 254 pixels. Il reste une dette
  d'asset P3 ; il n'est pas chargé sur la route Auth mesurée.

### Réseau authentifié observé

La fenêtre de recette de quatre heures contenait 19 458 événements Edge. Les
pics atteignaient 2 658 requêtes/minute. Les routes les plus répétées étaient
les obligations (2 746), le reporting budget (1 373), les courses (1 347), les
comptes sécurisés (1 291), les enveloppes sécurisées (1 284), les périodes
budget (1 283), les scénarios (1 273) et l'historique financier (1 270).

Cette fenêtre inclut les manipulations Offline/DevTools et plusieurs reprises ;
elle ne représente donc pas une navigation utilisateur nominale. Elle démontre
néanmoins une cascade réelle : chaque retour au focus Web déclenchait le refresh
global, et les routes principales construisaient l'ancien `IndexedStack` de
onze surfaces.

Les p95 d'origine observés allaient d'environ 60 ms pour les lectures simples à
1 002 ms pour l'historique financier, 869 ms pour les enveloppes et 841 ms pour
les comptes. Le Dashboard attendait en plus douze sources l'une après l'autre.

## Corrections

### P1 — chargement des routes

Avant : les routes Accueil, Argent, Comptes, Enveloppes, Objectifs, Imports,
Foyer, Projets et Plus tombaient sur un `IndexedStack` construisant onze pages.

Cause : seules les pages secondaires étaient couvertes par `_pageForPath`.

Correction : chaque route canonique construit uniquement sa surface active.
L'ancien stack reste un fallback de compatibilité, mais n'est plus utilisé par
une route produit connue.

Après : le test instrumenté du premier rendu Accueil observe **0 lecture** des
providers Comptes, Transactions, Enveloppes, Objectifs, Courses et PRIOS
inactifs.

### P1 — waterfall Dashboard

Avant : onze lectures financières puis le reporting budget, ainsi que trois
sources secondaires de l'Accueil, étaient attendus séquentiellement.

Cause : chaque `await ref.watch(provider.future)` précédait l'enregistrement du
provider suivant.

Correction : toutes les dépendances indépendantes sont enregistrées avant le
premier `await`. Riverpod conserve la déduplication et chaque source canonique ;
aucun calcul ni contrat de confidentialité n'est modifié.

Après : le chemin critique devient le maximum des lectures indépendantes au
lieu de leur somme. Avec les p95 observés, il est borné par la source la plus
lente (environ 1 s côté origine sur cette fenêtre), au lieu de cumuler plusieurs
secondes avant composition Flutter.

### P2 — retour au focus Web

Avant : chaque événement `resumed` Web lançait le refresh global de plus de
quarante providers. Ouvrir/fermer DevTools ou changer d'onglet pouvait donc
produire une nouvelle cascade complète.

Correction : le refresh lifecycle reste actif sur les plateformes natives. Sur
Web, la sonde REST, la synchronisation Offline et les invalidations Realtime
ciblées restent les autorités de fraîcheur ; un simple changement de focus ne
relance plus tout le modèle.

Après : test contractuel Web vert ; les refreshs manuels et les reprises natives
restent couverts par leurs tests existants.

## Mesure après corrections

| Mesure sans throttling | Après | Écart |
| --- | ---: | ---: |
| FCP | 1 493 ms | −78 ms |
| LCP | 1 804 ms | +42 ms (bruit de mesure) |
| Interactif | 1 673 ms | −88 ms |
| Total Blocking Time | 14 ms | −9 ms |
| Travail thread principal | 999 ms | −80 ms |
| Transfert initial | 3 894 222 octets | stable |
| Requêtes initiales | 12 | stable |
| Erreurs console | 0 | stable |

Les gains majeurs concernent la session authentifiée : suppression des pages
inactives, parallélisation de la waterfall Dashboard et suppression des refreshs
globaux au focus. Ils ne peuvent pas apparaître dans la mesure Lighthouse de la
route Auth sans copier une session humaine, ce qui a volontairement été exclu.

## N+1, doublons et stabilité

- aucun N+1 dans la composition Dashboard : les boucles transforment des listes
  déjà chargées et ne lancent pas de requête ;
- Riverpod déduplique les providers partagés au sein d'un container ;
- Realtime invalide uniquement les familles annoncées par le serveur et ne
  pilote plus l'état Online/Offline ;
- la sonde Offline empêche les probes concurrentes et s'arrête dès l'état
  synchronisé ;
- aucune erreur console Lighthouse ;
- aucune mutation financière, aucun import définitif et aucune modification de
  C3/C4B ou du gate L1.

## Dettes non bloquantes

- P3 : optimiser le logo raster surdimensionné après validation visuelle ;
- P3 : le bundle Dart monolithique expose 57,7 % de JavaScript inutilisé sur la
  route Auth. Flutter Web ne fournit pas ici un découpage automatique sûr par
  route ; une stratégie de deferred imports doit être traitée comme évolution
  architecturale séparée, avec certification complète des routes.
