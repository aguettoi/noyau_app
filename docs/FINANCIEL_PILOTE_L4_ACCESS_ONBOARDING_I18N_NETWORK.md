# L4 — Accès, onboarding, aide, langues et résilience réseau

## Périmètre livré

L4 étend les primitives Auth et foyer existantes sans créer de second moteur.
La surface publique présente le produit avant authentification et propose les
parcours connexion, inscription et « J’ai une invitation ». Les téléchargements
Windows/APK sont pilotés exclusivement par `WINDOWS_DOWNLOAD_URL` et
`ANDROID_DOWNLOAD_URL`; sans URL certifiée ils restent explicitement « bientôt ».

Le parcours guidé est progressif, reprenable et skippable. Il enregistre des
états personnels `notStarted`, `inProgress`, `configured` et `skipped` pour les
modules, sans écrire de donnée financière ni répliquer les configurations
canoniques. Le centre d’aide est statique, recherchable et disponible hors
connexion. Les actions rapides sont accessibles au clavier (`Ctrl+K`) et au
tactile depuis le menu Aide/configuration.

## Langues et RTL

Le socle de locale durable couvre français (`fr`), arabe (`ar`), darija en
écriture arabe marocaine (`ary`) et anglais (`en`). Material, Widgets et
Cupertino assurent la direction RTL pour arabe/darija. Le vocabulaire Darija
vise des termes marocains simples et conserve les noms produit/métier lorsqu'une
traduction créerait une ambiguïté. La landing et les commandes essentielles sont
couvertes; l'extraction exhaustive des anciennes chaînes métier reste couplée à
D1.2 et à la recette linguistique humaine.

## Matrice réseau

| Classe | Exemples | Hors ligne | Retour réseau |
|---|---|---|---|
| Lecture cacheable | aide, calendrier déjà chargé, snapshot Dashboard | lecture clairement datée | refresh canonique |
| Brouillon local | tâche, course domestique, note d'onboarding | création/édition/suppression locale | soumission via l'adapter canonique avec clé d'idempotence |
| Serveur obligatoire | FinancialEvent, GL, transfert, clôture, rapprochement | refus clair; jamais présenté comme réussi | nouvelle validation serveur obligatoire |

Les états de brouillon sont `localDraft`, `pending`, `syncing`, `synced`,
`conflict`, `rejected`, `actionRequired`. Aucun conflit financier important
n'est résolu silencieusement. La déconnexion purge progression foyer et
brouillons locaux; la langue reste un réglage de l'appareil. Aucun montant privé
n'est requis par le stockage L4.

## Sécurité et limites différées

- aucune table, RPC ou migration L4;
- aucune écriture FinancialEvent, GL ou Envelope Movement;
- RLS/Auth existants restent les seules frontières serveur;
- liens Auth réels, lifecycle natif, notifications natives et paquets de
  distribution restent à certifier en P1;
- validation humaine des corpus arabe/darija/anglais et audit exhaustif des
  chaînes historiques restent nécessaires avant le verdict produit final;
- cache L4 limité à des préférences et brouillons minimisés, jamais une base
  comptable alternative.

## Preuves

- `test/experience/l4_experience_test.dart` couvre landing, invitation,
  distributions sans URL inventée, aide locale, RTL et classification offline;
- tests Auth/foyer et shell existants rejoués;
- suite Flutter, analyse, format et builds Windows/Web exécutés au closing;
- compteurs C3/C4B contrôlés en lecture seule avant/après.

## Passage de fermeture des écarts

### R5-02

- **Avant** : progression persistée, mais choix de modules déclaratifs.
- **Correction** : neuf raccordements ouvrent les surfaces canoniques foyer,
  membres, comptes, budget/enveloppes, organisation, objectifs, rappels et
  confidentialité. Au retour, une lecture canonique décide si le module est
  réellement configuré; une simple visite laisse l'état `inProgress`.
- **Preuve** : le shell fournit les callbacks réels au parcours; skip et reprise
  restent personnels et persistants.
- **Statut** : A fonctionnel, recette humaine finale conservée.

Le contrôle de retour utilise les tables/RPC canoniques. En particulier,
`household_members.user_id` est lu pour les membres et
`list_account_privacy_summaries_v2` pour la confidentialité; une erreur ou une
surface simplement visitée ne produit jamais un faux état `configured`.

### NET-X1

- **Avant** : modèle et persistance locale sans soumission réelle.
- **Correction** : coordinateur de synchronisation déclenché à la reconnexion,
  adapters tâches/courses vers les gateways existantes, revalidation stricte du
  couple utilisateur/foyer, identifiant stable transmis à la création et
  conservation en `actionRequired` en cas d'échec.
- **Preuve** : test de réponse perdue puis retry; une seule clé canonique est
  utilisée et le brouillon n'est purgé qu'après réponse serveur positive.
- **Durcissement de fermeture** : les signaux de reconnexion concurrents
  partagent une seule exécution; un conflit de clé primaire après perte de la
  réponse est traité comme le succès idempotent de ce brouillon.
- **Limite** : le stockage et les adapters sont raccordés, mais toutes les
  surfaces de saisie concernées ne proposent pas encore explicitement la mise
  en file lors d'une panne. Le statut demeure B tant que cette UX et toute la
  matrice timeout/session/révocation ne sont pas couvertes de bout en bout.

### R5-06 / R5-07 / R5-08

- **Avant** : sélecteur et corpus L4 réduit.
- **Contrôle** : l'inventaire statique recense 2 695 occurrences candidates
  (`Text`, labels, hints, tooltips, SnackBars et dialogues) dans `lib/`.
- **Inventaire lexical de fermeture** : 177 fichiers Dart de production;
  2 178 constructions `Text`, 568 labels, 5 hints, 50 tooltips, 75 SnackBars et
  99 dialogues. Ces classes se recouvrent et incluent données dynamiques,
  libellés déjà indirects et faux positifs; elles ne constituent donc pas un
  nombre de traductions. Les 207 erreurs/exceptions et 3 sorties debug sont
  inventoriées séparément.
- **Écart** : l'ancien corpus V1 n'est pas intégralement extrait ni traduit.
- **Statut** : B. Le fallback ne doit pas être présenté comme une traduction.

### R5-12

- **Avant** : accessibilité ciblée L4 et couverture responsive historique.
- **Correction** : toutes les nouvelles commandes ont une voie tactile et
  clavier; les surfaces critiques conservent leurs tests responsive existants.
- **Limite** : l'audit fonctionnel systématique des anciens widgets reste à
  terminer avant classement A; la certification visuelle demeure D1.2/P1.
- **Statut** : B.

## Validation de fermeture du 27 octobre 2026

- tests L4 ciblés : 7/7 PASS;
- suite Flutter : 1 034 PASS, 3 skips conditionnels;
- `flutter analyze lib test` : PASS;
- format : 355 fichiers, 0 modification;
- Windows release : PASS;
- Web release : PASS (avertissements Wasm provenant du package tiers `image`);
- C3 : 6 comptes, 26 enveloppes, 3 obligations / 598 277,40 MAD,
  9 FinancialEvents, 5 transactions GL, 10 postings, 18 mouvements;
- C4B : 1 581 lignes, 45 décisions;
- migration et écriture serveur L4 : aucune.

Le closing est publiable mais reste **PARTIAL** : R5-06, R5-07, R5-08,
R5-12 et NET-X1 restent B. Aucun fallback de traduction, PASS d'accessibilité
ou synchronisation financière fictive n'est revendiqué.

## Matrice des adapters offline réellement raccordés

| Action | Offline | Brouillon | Adapter canonique | Identité stable | Revalidation | Conflit/résultat |
|---|---|---|---|---|---|---|
| Tâche domestique | oui | `task` | `OrganizationGateway.createTask` | UUID du brouillon transmis comme `id` | session + foyer + RLS | succès: purge; sinon `actionRequired` |
| Course domestique | oui | `grocery_item` | `DailyLifeActions.addGrocery` | UUID du brouillon transmis comme `id` | session + foyer + RLS | succès: purge; sinon `actionRequired` |
| Note onboarding | local seulement | `onboarding_note` | préférence locale | clé stable | utilisateur local | reste locale |
| FinancialEvent / GL / transfert / clôture | non | préparation uniquement | RPC canonique lors de l'action utilisateur | idempotence RPC existante | serveur complète | jamais synchronisé silencieusement |
