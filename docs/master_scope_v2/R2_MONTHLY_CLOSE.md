# R2 — clôture mensuelle et fiabilité

Statut : R2.7 matérialisé le 12/10/2026 ; l'inventaire humain initial compte × enveloppe reste requis avant la première clôture pilote.

## R2.7 — règles structurelles et épargne de fin de mois

- Les 26 enveloppes sont classées sans inventer leur position physique actuelle : 23 règles mono-compte, `Habits` en répartition scénario, `Reste epargne (primes Ibrahim et Nora)` selon le bénéficiaire réel, et `À répartir` comme référentiel système.
- `Epargne` est structurellement rattachée à `Islamique / Arreda Ibrahim`. Cela ne déplace pas son solde historique et ne prouve pas sa position bancaire actuelle.
- `Habits` reste multi-comptes : dans `DEPART`, 344,24 MAD sont ciblés vers CIH Ibrahim et 655,76 MAD vers Banque Nora.
- `Reste epargne (primes Ibrahim et Nora)` reste distincte, hors budget récurrent, sans allocation fixe ; sa localisation suit le membre et le compte réellement bénéficiaires.
- À la clôture, seuls les reliquats positifs de `Navette`, `Nourriture` et `Sorties WE` sont transférés économiquement vers `Epargne`. Zéro et déficits produisent une trace à zéro ; aucune autre enveloppe n'est balayée.
- Le sweep réutilise `create_envelope_transfer_event`. Il ne produit aucun posting GL ni transfert bancaire. La projection compte × enveloppe déplace les montants vers `Epargne` sur les mêmes comptes physiques ; un transfert réel vers Arreda reste une action bancaire canonique distincte.
- Le traitement est mensuel, append-only, verrouillé et idempotent par foyer/mois/source. Une clôture déjà effectuée ne rejoue jamais le sweep.
- Une matrice compte × enveloppe fiable est obligatoire : R2.7 n'initialise aucune position historique arbitraire.
- R2.7.1 sépare explicitement la règle économique de la localisation physique : la colonne « Titulaire / règle » est dérivée des étapes Budget (`single_member`, `custom_percentage`, membres associés), jamais de `recommended_account_id` ni de la titularité bancaire.
- Les charges personnelles affichent le membre concerné. Les dépenses communes mono-compte affichent « Foyer — clé du scénario » ; `Habits` affiche « Foyer — plusieurs comptes » ; les primes restent « Selon le bénéficiaire / membre ».

## R2.5 — scénario budgétaire pilote

- La source certifiée `SIMULATION_CUTOVER_FINAL_20260929.xlsx.xlsx` (SHA-256 `f3cbc99e335586d5628791017e5fd8119430a03d32674ba1d11f284157c8f8bc`) fournit six scénarios reconstructibles sans hypothèse.
- `DEPART` est actif et par défaut du 01/10/2026 au 31/03/2027. Les cinq scénarios d'évolution sont disponibles mais inactifs.
- Les sources de référence de `DEPART` sont 12 800 MAD pour Ibrahim et 15 000 MAD pour Nora. Elles décrivent la simulation pilote, pas les revenus réels actuels.
- `Wifi Home` et `WIFI` sont consolidés dans l'unique enveloppe canonique `Wifi`. `Besoin personnel` est relié à `Besoin perso`.
- `Habits` conserve deux comptes de financement dans le scénario. La preview R2 répartit le solde courant selon les poids du scénario, sans dérogation mensuelle.
- `Reste epargne (primes Ibrahim et Nora)` est explicitement exclu du budget récurrent. Les primes/surplus futurs passent par les moteurs canoniques lorsqu'ils sont réellement constatés.
- La configuration ne produit aucun FinancialEvent, transaction GL ni mouvement d'enveloppe.
- Le scénario utilisé est figé sur `budget_periods.scenario_id` lors du premier snapshot mensuel. Octobre peut ainsi conserver `DEPART` même si novembre sélectionne ensuite `APRES ACQUISITION VOITURE`.
- Le moyen de paiement recommandé reste facultatif : la cible compte × enveloppe dépend du compte canonique, pas d'une carte ou d'un moyen particulier.
- Les soldes non nuls `Epargne` et `Reste epargne (primes Ibrahim et Nora)` n'ont pas de localisation compte certaine dans la source. Le produit les laisse donc à configurer humainement au lieu d'inventer une cible.

## R2.3 — corrections de recette humaine

- La cible compte × enveloppe est calculée en priorité depuis le budget/scénario actif, les `funding_source_preference` et la recommandation canonique de l’enveloppe.
- Si aucune source ne permet de déterminer un compte unique, le manque est affiché : aucune banque ni aucun membre n’est deviné.
- Une cible saisie à la main est une dérogation mensuelle OWNER, auditée et assortie d’un motif.
- Le point de départ reste OPTION B : matrice globale explicite, sans reconstruction historique. Les totaux par enveloppe et par compte doivent réconcilier les deux ledgers.
- L’initialisation est indisponible tant que les rapprochements et inventaires du mois ne sont pas fiabilisés.
- L’inventaire espèces affiche le théorique mais laisse le réel vide. Un écart exige un commentaire et ne corrige jamais silencieusement le GL.
- Le score Santé est explicable par domaine et reste distinct du verdict « prêt à clôturer ».
- La régularisation et les virements restent une preview jusqu’à confirmation ; l’exécution utilise les transferts canoniques et revérifie les cibles côté serveur.

## R2.4 — paramétrage canonique des enveloppes

- Une surface centralisée expose toutes les enveloppes avec solde, règle de titularité, compte recommandé, moyen recommandé et état.
- Le cas simple réutilise exclusivement `envelopes.recommended_account_id`, `recommended_payment_method_id` et `set_envelope_recommendation` de F2.
- Les comptes archivés et moyens inactifs ne sont jamais proposés. Le serveur revérifie foyer, activité, compte lié et titulaire, puis inscrit l’évolution dans un audit non financier.
- Une absence de recommandation renvoie depuis Fin de mois vers cette configuration structurelle. La dérogation mensuelle reste une exception OWNER motivée.
- La source de cible est affichée comme `Budget MM/AAAA — Scénario …`. Sans scénario applicable, l’UI propose la configuration Budget et n’invente rien.
- Une enveloppe structurellement multi-comptes reste décrite par les étapes du scénario Budget. Les montants `fixed` ou pourcentages homogènes sont répartis proportionnellement, avec correction du centime final ; tout cas ambigu reste bloqué.
- Cette configuration ne crée ni FinancialEvent, ni transaction GL, ni mouvement d’enveloppe.

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

R2.14 conserve cette couche canonique mais retire la matrice du parcours normal.
Les preuves et déductions certaines sont préparées sans question ; les règles
structurelles ne produisent que des propositions. L'utilisateur peut reporter
une localisation avec « Je ne sais pas / plus tard ». Ce statut ne crée aucune
position fictive et ne bloque que les opérations qui ont réellement besoin du
compte porteur (réallocation physique, sweep ou transfert analytique ciblé).
La matrice complète reste disponible dans le mode avancé.

## R2.9 — preuve du point de départ

Le préremplissage initial distingue désormais trois provenances : preuve de la source certifiée, confirmation humaine traçable et déduction par équilibrage unique. Une recommandation structurelle n'est jamais une preuve de localisation actuelle. La validation finale reste explicite et atomique ; elle n'écrit ni Grand Ledger, ni FinancialEvent, ni mouvement d'enveloppe.

Pour la source certifiée `f3cbc99e335586d5628791017e5fd8119430a03d32674ba1d11f284157c8f8bc`, sept enveloppes non nulles sont entièrement prouvées : Nourriture et Navette sur Espèces maison ; Traite voiture, Wifi, Besoin perso et Reste épargne sur Banque Nora ; Épargne sur Islamique / Arreda Ibrahim par confirmation métier. Habits est partiellement prouvée à 761,17 MAD sur Banque Nora ; son résiduel de 874,40 MAD reste à localiser entre les comptes d'Ibrahim. Les dix autres enveloppes non nulles restent indéterminables au niveau du compte physique. Les huit enveloppes à solde nul ne demandent aucune position.

Une régularisation R2C confirmée crée uniquement les virements de compte canoniques nécessaires puis inscrit, avec les mêmes `FinancialEvent`, les deltas analytiques compte × enveloppe. La simulation reste sans écriture. La confirmation est OWNER, atomique, idempotente et refuse un fingerprint devenu obsolète. La cible mensuelle reste strictement distincte de la position actuelle.

## R2.10 — netting global et exécution canonique

La simulation compare la matrice physique actuelle aux cibles mensuelles, conserve chaque déplacement analytique par enveloppe, puis calcule globalement le plus petit ensemble déterministe de virements entre comptes. Des flux opposés s'annulent : un virement physique peut ainsi être expliqué par plusieurs justifications analytiques, sans perdre la ventilation compte × enveloppe.

La confirmation OWNER exige une date économique explicite. Le serveur recalcule indépendamment le net global, vérifie la cible mensuelle courante et le fingerprint de la matrice, puis exécute uniquement les transferts de comptes canoniques. Les justifications et deltas de matrice sont enregistrés dans la même transaction. Un retry avec la même clé est idempotent et une proposition obsolète est refusée.

Le titulaire du compte sert à expliquer l'action physique, jamais à déduire la responsabilité économique. Un transfert entre comptes de membres différents ne crée donc pas automatiquement une compensation F3 : cette dernière reste réservée à une dette/créance interne explicitement reconnue. Banque vers espèces est présenté comme un retrait/alimentation, espèces vers banque comme un dépôt ; aucun revenu, dépense ou mouvement d'enveloppe supplémentaire n'est créé.

## R2.11 — provenance du point de départ

Chaque position d'ouverture conserve une provenance explicite : preuve de la source certifiée, confirmation métier, arbitrage d'inventaire ou déduction mathématiquement unique. Une saisie libre est un arbitrage par défaut et ne peut donc jamais être relue comme une preuve historique. Les preuves préremplies restent verrouillées ; une cellule libre peut être qualifiée comme confirmation métier explicite.

La traçabilité reste consultable après validation avec montant, compte, enveloppe, provenance, référence, acteur, date, batch et note globale. Cette qualification n'altère aucun calcul futur : la position validée reste la situation actuelle utilisée par R2.10, quelle que soit l'origine de sa connaissance.

Après le point de départ, les mouvements d'enveloppe liés à un événement comportant exactement un compte physique sont projetés automatiquement et référencent le mouvement source. Un transfert de compte sans ventilation d'enveloppe, un transfert d'enveloppe sans compte, ou tout événement ambigu n'est jamais attribué arbitrairement : les écarts deviennent visibles et la matrice repasse à l'état « à fiabiliser ».

## R2.12 — assistant de ventilation d'inventaire

L'assistant construit une proposition locale à partir des soldes résiduels, des positions déjà établies et des règles structurelles. Toute position existante est une contrainte immuable. Une recommandation sert uniquement à ordonner les comptes admissibles : elle ne devient jamais une preuve historique.

La prévisualisation détaille chaque enveloppe, compte, montant et raison avant toute modification. L'acceptation ne remplit que le brouillon et qualifie chaque nouvelle cellule comme `Arbitrage d’inventaire`, avec une référence R2.12. La validation définitive reste celle du point de départ R2.9/R2.11. L'assistant ne crée ni FinancialEvent, ni Grand Ledger, ni mouvement d'enveloppe, ni transfert physique.

### R2.8 — Inventaire initial contrôlé compte × enveloppe

L'écran `Fin de mois → Établir le point de départ` permet à un OWNER de déclarer explicitement la localisation physique du stock existant. Il démarre vide : les recommandations structurelles ne préremplissent jamais la matrice. Elles sont affichées comme aide facultative et ne sont appliquées qu'après une action humaine explicite. Les enveloppes à solde nul ne demandent aucune saisie.

La revue est disponible par enveloppe et par compte, avec progression, total affecté, total restant et écarts détaillés. La confirmation finale reste désactivée tant que chaque enveloppe, chaque compte et le total foyer ne sont pas exactement réconciliés. La RPC append-only existante enregistre atomiquement un batch historisé et idempotent sans FinancialEvent, Grand Ledger, mouvement d'enveloppe ni modification de solde.

La maintenance future est partielle : une opération canonique non ambiguë (un compte physique et une enveloppe) alimente automatiquement la projection. Les opérations qui ne portent qu'une dimension ou dont l'attribution est ambiguë restent volontairement à fiabiliser et ne sont jamais ventilées arbitrairement.

La fonction `monthly_close_snapshot` calcule les conditions depuis les sources métier. Une clôture refuse tout blocker. Un OWNER peut déroger aux warnings avec un motif obligatoire. Une réouverture est réservée à un OWNER et exige un motif.

Le solveur Dart de régularisation est pur et produit seulement des propositions de transferts minimisées par compensation des surplus et déficits. Il ne crée aucun FinancialEvent.

## UI/UX

La surface Fin de mois est accessible depuis Pilotage. Elle utilise le Design System partagé, une liste responsive, des états loading/error, un score explicable, une checklist guidée, un centre À faire et un contrôle final. La réouverture OWNER est désormais exposée avec motif, retour utilisateur et historique. Les catégories du centre ouvrent les surfaces canoniques Comptes, Transactions et Compensations. Les cibles mensuelles compte × enveloppe sont consultables avant clôture. Leur source normale est automatique ; seule une dérogation OWNER motivée est modifiable mensuellement.

## Limites

- Les KPI par profil restent attribués au foyer tant que les données ne prouvent pas le membre responsable.
- Le snapshot ne fournit que des compteurs : le centre À faire ouvre le bon module, mais pas encore l'objet précis.
- Le foyer pilote n'est volontairement pas initialisé automatiquement : aucun historique compte × enveloppe n'est inventé. Un OWNER doit effectuer l'inventaire humain initial avant que R2C soit utilisable sur ce foyer.
- La recette visuelle humaine des surfaces R2 reste requise.
- Les sources multi-comptes sont désormais matérialisées via `DEPART`. Le foyer pilote doit encore recevoir les recommandations structurelles humaines de `Epargne` et `Reste epargne (primes Ibrahim et Nora)` ; aucun historique n'est reconstruit.
- R2.6 place toutes les charges personnelles avant les dépenses communes dans les six scénarios certifiés. Dans `DEPART`, Wifi est donc déduit de la capacité de Nora avant la répartition commune : 3 858,33 MAD pour Ibrahim et 7 350,00 MAD pour Nora, soit 34,42377232 % / 65,57622768 %. `Habits` reste une dépense commune répartie sur deux comptes et n'entre pas dans le calcul préalable de cette clé.
- Cette correction porte uniquement sur le modèle réutilisable courant. Les périodes et snapshots mensuels déjà enregistrés restent immuables.
- La certification iOS réelle reste P1 faute d'environnement Apple.
