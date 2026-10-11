# R2 — clôture mensuelle et fiabilité

Statut : partiellement finalisé le 10/10/2026.

## R2.3 — corrections de recette humaine

- La cible compte × enveloppe est calculée en priorité depuis le budget/scénario actif, les `funding_source_preference` et la recommandation canonique de l’enveloppe.
- Si aucune source ne permet de déterminer un compte unique, le manque est affiché : aucune banque ni aucun membre n’est deviné.
- Une cible saisie à la main est une dérogation mensuelle OWNER, auditée et assortie d’un motif.
- Le point de départ reste OPTION B : matrice globale explicite, sans reconstruction historique. Les totaux par enveloppe et par compte doivent réconcilier les deux ledgers.
- L’initialisation est indisponible tant que les rapprochements et inventaires du mois ne sont pas fiabilisés.
- L’inventaire espèces affiche le théorique mais laisse le réel vide. Un écart exige un commentaire et ne corrige jamais silencieusement le GL.
- Le score Santé est explicable par domaine et reste distinct du verdict « prêt à clôturer ».
- La régularisation et les virements restent une preview jusqu’à confirmation ; l’exécution utilise les transferts canoniques et revérifie les cibles côté serveur.

## Sources canoniques réutilisées

- Grand Ledger et comptes pour les positions théoriques.
- Dossiers de rapprochement pour les écarts ouverts.
- Observations de caisse pour les inventaires.
- FinancialEvent et justificatifs privés pour la complétude documentaire.
- Compensations F3 pour les montants encore à verser ou confirmer.
- Journal des enveloppes et flux de transfert canoniques pour toute exécution confirmée.

## Architecture

`monthly_close_periods` conserve l'état mensuel. `monthly_close_events` constitue l'audit append-only des clôtures, dérogations et réouvertures. `monthly_envelope_account_targets` porte la cible mensuelle configurable compte × enveloppe sans recopier un solde.

## Source compte × enveloppe

L'étude R2.2 retient l'option B. La matrice n'est pas reconstructible exhaustivement : C3 a ouvert séparément les comptes et les enveloppes, tandis que les transferts historiques de compte ou d'enveloppe ne portent pas toujours l'autre dimension. `envelope_account_position_batches` et `envelope_account_position_entries` forment donc une projection analytique append-only minimale. Un point de départ est saisi explicitement après inventaire et n'écrit ni GL ni mouvement d'enveloppe. Sa validité exige que chaque somme par compte égale le Grand Ledger et que chaque somme par enveloppe égale l'envelope ledger. Toute différence rend la matrice non fiable et bloque R2C.

Une régularisation R2C confirmée crée uniquement les virements de compte canoniques nécessaires puis inscrit, avec les mêmes `FinancialEvent`, les deltas analytiques compte × enveloppe. La simulation reste sans écriture. La confirmation est OWNER, atomique, idempotente et refuse un fingerprint devenu obsolète. La cible mensuelle reste strictement distincte de la position actuelle.

Après le point de départ, les mouvements d'enveloppe liés à un événement comportant exactement un compte physique sont projetés automatiquement et référencent le mouvement source. Un transfert de compte sans ventilation d'enveloppe, un transfert d'enveloppe sans compte, ou tout événement ambigu n'est jamais attribué arbitrairement : les écarts deviennent visibles et la matrice repasse à l'état « à fiabiliser ».

La fonction `monthly_close_snapshot` calcule les conditions depuis les sources métier. Une clôture refuse tout blocker. Un OWNER peut déroger aux warnings avec un motif obligatoire. Une réouverture est réservée à un OWNER et exige un motif.

Le solveur Dart de régularisation est pur et produit seulement des propositions de transferts minimisées par compensation des surplus et déficits. Il ne crée aucun FinancialEvent.

## UI/UX

La surface Fin de mois est accessible depuis Pilotage. Elle utilise le Design System partagé, une liste responsive, des états loading/error, un score explicable, une checklist guidée, un centre À faire et un contrôle final. La réouverture OWNER est désormais exposée avec motif, retour utilisateur et historique. Les catégories du centre ouvrent les surfaces canoniques Comptes, Transactions et Compensations. Les cibles mensuelles compte × enveloppe sont consultables et modifiables avant clôture via le RPC audité.

## Limites

- Les KPI par profil restent attribués au foyer tant que les données ne prouvent pas le membre responsable.
- Le snapshot ne fournit que des compteurs : le centre À faire ouvre le bon module, mais pas encore l'objet précis.
- Le foyer pilote n'est volontairement pas initialisé automatiquement : aucun historique compte × enveloppe n'est inventé. Un OWNER doit effectuer l'inventaire humain initial avant que R2C soit utilisable sur ce foyer.
- La recette visuelle humaine des surfaces R2 reste requise.
- La certification iOS réelle reste P1 faute d'environnement Apple.
