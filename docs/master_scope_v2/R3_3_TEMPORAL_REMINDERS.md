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

### Report personnel continu entre phases (19/10/2026)

Pour une occurrence R3.1, **Snooze** et **Pas encore** portent sur le couple occurrence/utilisateur. La clé canonique dans `user_alert_states` est `reminder-source:r3_1_occurrence:<source_id>`, dans le même foyer. Les clés `r3.1:<id>:before/day/after` restent celles des phases temporelles. Les états lu/masqué gardent leur portée de phase ; ils n'annulent pas le report commun. L'audit conserve la phase sur laquelle l'action a été demandée. Le trigger privé adapte atomiquement les actions existantes vers l'état de source ; les colonnes historiques des phases restent compatibles mais ne décident plus du snooze R3.1.

La migration additive `20261019070158_r3_3_occurrence_personal_deferral.sql` reprend les reports déjà audités. Elle ne change ni leur échéance ni l'occurrence financière. Aucun état n'est recopié vers les phases suivantes.

La correction additive `20261019070807_r3_3_equal_time_phase_order.sql` départage les phases simultanées (offsets de zéro jour possibles) : AFTER prime sur JOUR J, qui prime sur BEFORE. Le test SQL couvre explicitement une arrivée dans l'ordre inverse. La correction `20261019071027_r3_3_current_phase_read_window.sql` exclut aussi une ancienne phase lorsque la suivante est déjà exigible mais attend encore le prochain cycle pg_cron : aucun ancien rappel ne ressuscite dans cet intervalle ; la phase pertinente devient disponible après sa matérialisation canonique. Les versions locales correspondent aux trois versions effectivement enregistrées dans le Sandbox ; aucune migration antérieure n'a été réécrite.

La lecture `visible_financial_reminders` est `SECURITY INVOKER` : RLS, destinataire, état personnel, occurrence encore attendue et intention active sont vérifiés côté serveur. Avant expiration, aucune phase ne peut contourner le report. Après expiration, seule la dernière phase exigible et active est présentée ; les anciennes phases ne sont pas ressuscitées, même si elles arrivent dans un ordre différent. Les cycles pg_cron continuent à matérialiser les phases canoniques indépendamment des préférences de chaque membre.

L'application relit le serveur à l'expiration du prochain report (timer annulé à la destruction du provider), au refresh, à la réouverture et après invalidation Realtime. Une occurrence réalisée/ignorée ou une intention suspendue/arrêtée n'est plus présentée. Le scheduler résout les rappels réalisés/ignorés selon son comportement existant. Le fuseau et la protection serveur exigeant une date strictement future restent inchangés.

Preuves : matrice SQL authentifiée rollbackée `supabase/tests/r3_3_occurrence_personal_deferral.sql` (1/2/N, deux foyers, retries, cycles répétés, expiration, lu/masqué, réalisation/ignorance/suspension/arrêt et compteurs financiers) ; tests domain des phases et de l'isolation personnelle ; tests widget de disparition et d'erreur RPC ; non-régression des tests timezone/minuit/DST. Aucun nouveau test manuel n'est préparé dans le foyer pilote.

Le scheduler et toutes les actions R3.3 sont non financiers. Ils n'insèrent jamais dans `financial_events`, `financial_transactions`, `financial_transaction_lines`, `envelope_movements` ou `obligations`. **Pas encore** ne réalise ni n'ignore l'occurrence : il reporte seulement sa notification personnelle et conserve une trace auditée.

La donnée métier partagée reste visible aux membres autorisés. Les préférences, états lu/masqué/snoozé et audits d'action restent propres à l'utilisateur. Les politiques RLS conservent l'isolation par foyer et la cardinalité 1/2/N.

## Partiel et reporté

- La détection historique assistée des récurrents est reportée au sous-lot **R3.3.x**. L'historique et le matcher R3.1 sont disponibles, mais un score robuste de périodicité et le refus durable d'une suggestion doivent être conçus sans faux positifs ; aucune récurrence ne sera créée automatiquement.
- La distribution multicanale reste **P1 — obligatoire avant version finale / publication**. R3.3 couvre uniquement le moteur métier canonique, le scheduler serveur et le centre in-app. P1 devra distribuer une même alerte canonique vers Windows, Android, iOS et Web/navigateur (plus badges lorsque disponibles), y compris application fermée, sans créer de moteur de rappel propre à chaque plateforme.
- P1 devra séparer explicitement : alerte métier canonique, état personnel, préférences personnelles et livraisons techniques. Le modèle cible est foyer → membre → appareil/endpoint → canal → autorisation/préférence, avec déduplication, retry/offline, expiration des endpoints, changement de fuseau et traçabilité par livraison.
- Les références R3.3 `source_kind`, `source_id` et `action_type` préservent le contexte nécessaire aux futurs deep links. La livraison système devra appliquer une politique de confidentialité : contenu générique sur écran verrouillé ou canal partagé lorsque le détail est sensible ou non autorisé.
- Les seuils avancés d'enveloppes/échéances sont prévus dans le catalogue de règles, sans être déclarés couverts tant que leur source canonique et leur UI ne sont pas raccordées.

## Préparation IA

Les rappels exposent des références explicites, priorités, échéances et actions déterministes. Une future couche de conseil pourra les lire avec les autorisations existantes. R3.3 n'intègre aucun LLM, aucune clé, aucun prompt et aucune écriture IA.
