# L1 final — agrégats, anti-inférence et intégration

## Matrice des surfaces existantes

`visible-only` signifie que le serveur/client n'additionne que les éléments lisibles. `complete=false` interdit de présenter ce nombre comme un total du foyer.

| Surface | Contrat | Complétude | Éléments cachés signalés | Reconstruction privée | État |
|---|---|---|---|---|---|
| Dashboard | visible-only | explicite | oui | non par total | automatique PASS |
| Comptes | projection serveur v2 | par ligne | oui, sans montant | non | SQL PASS |
| Patrimoine | liquidités visibles | explicite | oui | non par total | automatique PASS |
| FinancialAvailability | visible-only ou décision bornée | explicite | oui | aucun montant privé | automatique PASS |
| Budget / scénarios | références de comptes soumises aux contrats de lecture | partielle | refus/absence | tests SQL des liens | PARTIEL transverse |
| Enveloppes | projection sûre | complète hors référence privée | référence masquée | non | SQL PASS |
| Projection / clôture | security-invoker et RLS | visible-only | résultat restreint | non sur cas testés | SQL PASS |
| Objectifs / PRIOS / Shopping | données métier foyer, financement privé non détaillé | selon surface | non applicable au montant privé | non démontrée exhaustive | PARTIEL |
| Obligations | canonique, compte privé filtré par primitives | visible-only | non exhaustif | non sur cas testés | PARTIEL |
| Rapprochement | lectures invoker + garde compte | visible-only | oui par absence | non | SQL PASS |
| Recherche | contrat serveur, compte privé absent | visible-only | non | non | SQL PASS ciblé |
| Rapports / export household | comptes via projection v2, enveloppes via projection sûre | explicite par lignes | oui pour solde masqué | non sur comptes/enveloppes | automatique PASS ciblé |

## Attaques par différence

- `total - visible` : aucun total incluant le privé n'est retourné par Dashboard, patrimoine ou FinancialAvailability.
- avant/après et N/N-1 : les séries visibles ne mélangent pas une composante privée dans un total retourné.
- projection/scénario : les lectures de positions et clôture suivent RLS ; la capacité privée passe par une décision bornée.
- export/interface : comptes et enveloppes utilisent les mêmes projections serveur ; les futurs exports doivent réutiliser ces contrats.

La preuve automatique ne remplace pas le test multi-session après révocation. Les modules marqués PARTIEL restent des limites de certification, pas des fuites démontrées.

## Recette humaine finale consolidée

1. Session A (titulaire) et session B (membre du même foyer) ouvrent **Comptes** ; session C appartient à un autre foyer.
2. A partage un compte technique non financier avec B. B ouvre la liste puis le détail et garde l'application ouverte.
3. A révoque B. B doit recevoir une invalidation sans montant ni identifiant de compte secret ; le compte/détail doit disparaître après rafraîchissement.
4. B utilise Retour, une recherche et un lien direct vers l'ancien détail : aucune donnée ne réapparaît et le serveur refuse/restitue un état indisponible.
5. B ferme puis rouvre l'application et se reconnecte : la donnée reste inaccessible. C ne reçoit aucune invalidation du foyer A.
6. A, B et l'administrateur non titulaire génèrent l'export foyer : A obtient ce qu'il peut lire ; B/admin n'obtiennent ni compte privé, ni identifiant, ni montant ; un solde masqué conserve seulement les métadonnées autorisées.
7. Vérifier dans **Alertes** qu'aucun titre, texte, montant, metadata ou route ne révèle l'ancien compte.

Cette recette n'exige aucune opération financière ni donnée pilote durable.

## Recette de reconstruction isolée

Prérequis : Docker Desktop, Supabase CLI compatible et espace disque local. Commandes depuis la racine : `supabase start`, `supabase db reset`, puis exécution des tests SQL L1 sur la base locale. Résultat attendu : migrations dans l'ordre, zéro doublon, 108 fonctions privilégiées client toutes A, zéro accès anon, publication Realtime limitée à `household_realtime_invalidations`, 13 tests SQL L1 verts. Terminer par `supabase stop --no-backup`. Ne jamais utiliser le projet Sandbox pilote comme cible de cette recette.
