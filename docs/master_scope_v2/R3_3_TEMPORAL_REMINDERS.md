# R3.3 — Rappels temporels et règles légères

## Couvert maintenant

R3.3 étend le centre **Organisation du foyer > Alertes** de F6. Il ne crée pas de boîte de réception concurrente. Les rappels persistés référencent leur source canonique et ne dupliquent ni l'occurrence R3.1, ni la période R2, ni la projection R3.2.

- occurrences R3.1 : rappel avant, le jour même et relance après échéance ; la phase la plus récente remplace les phases antérieures ; une occurrence réalisée ou ignorée résout ses rappels ; une intention suspendue ou arrêtée n'en produit pas ;
- pré-clôture R2 : rappel vers **Fin de mois**, sans rendre l'inventaire compte × enveloppe obligatoire ;
- risques R3.2 : réutilisation directe du résultat déterministe de la projection, avec une clé stable pour éviter les doublons ;
- actions personnelles : lu, masqué, snooze, date/heure choisie et **Pas encore**, avec audit append-only ;
- règles personnelles légères : activation, jours avant/après, heure locale et priorité ;
- scheduler Supabase `pg_cron` toutes les quinze minutes, indépendant de l'ouverture de l'application et idempotent ;
- Realtime et refresh sur rappels, règles, préférences et états personnels.

Le fuseau est résolu depuis le profil d'un membre actif du foyer (OWNER prioritaire), avec `Africa/Casablanca` uniquement comme repli lorsque aucun profil ne fournit de fuseau. Les dates métier restent celles de leurs sources.

## Invariants

Le scheduler et toutes les actions R3.3 sont non financiers. Ils n'insèrent jamais dans `financial_events`, `financial_transactions`, `financial_transaction_lines`, `envelope_movements` ou `obligations`. **Pas encore** ne réalise ni n'ignore l'occurrence : il reporte seulement sa notification personnelle et conserve une trace auditée.

La donnée métier partagée reste visible aux membres autorisés. Les préférences, états lu/masqué/snoozé et audits d'action restent propres à l'utilisateur. Les politiques RLS conservent l'isolation par foyer et la cardinalité 1/2/N.

## Partiel et reporté

- La détection historique assistée des récurrents est reportée au sous-lot **R3.3.x**. L'historique et le matcher R3.1 sont disponibles, mais un score robuste de périodicité et le refus durable d'une suggestion doivent être conçus sans faux positifs ; aucune récurrence ne sera créée automatiquement.
- Les notifications natives Windows/Android/iOS et leur livraison lorsque l'appareil est hors ligne restent en **P1**. R3.3 couvre le scheduler serveur et le centre in-app.
- Les seuils avancés d'enveloppes/échéances sont prévus dans le catalogue de règles, sans être déclarés couverts tant que leur source canonique et leur UI ne sont pas raccordées.

## Préparation IA

Les rappels exposent des références explicites, priorités, échéances et actions déterministes. Une future couche de conseil pourra les lire avec les autorisations existantes. R3.3 n'intègre aucun LLM, aucune clé, aucun prompt et aucune écriture IA.
