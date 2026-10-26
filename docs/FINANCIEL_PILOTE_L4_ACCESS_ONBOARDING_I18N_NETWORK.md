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
