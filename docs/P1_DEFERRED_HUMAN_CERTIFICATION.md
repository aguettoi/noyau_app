# P1 — Certifications humaines différées

Ces contrôles restent obligatoires avant la certification finale, le cutover et
la mise en production. Un statut différé ne constitue jamais un PASS.

## P1-B Darija final retest

**Statut : `PASS — validation humaine du 12 novembre 2026`**

Préconditions :

- ouvrir le Web Sandbox réel sur `http://localhost:4173` ;
- utiliser une session authentifiée et sélectionner la langue Darija (`ary`) ;
- ne confirmer aucune opération financière.

### Analyses

1. Ouvrir **Accueil → Voir les analyses**.
2. Vérifier que la période affiche `هاد الشهر`.
3. Vérifier que l’alerte de rapprochement affiche
   `حساب خاصو المطابقة`.
4. Vérifier que le nom du compte reste strictement inchangé et qu’il est suivi
   de `ما كاينة حتى معاينة.` lorsqu’aucun constat n’existe.
5. Ouvrir les explications KPI visibles et confirmer l’absence de libellé
   français résiduel, hors données utilisateur ou historiques.

### Finaliser le mois

1. Depuis **Analyses**, ouvrir **Préparer la fin de mois**, puis le parcours de
   clôture sans confirmer l’action finale.
2. Contrôler les formulations Darija révisées, notamment :
   - `مراحل واضحة باش تسالي الشهر` ;
   - `واش التسجيلات موثوقين` ;
   - `المراحل الموجهة` ;
   - `حالة الشهر` ;
   - les libellés de rapprochement, inventaire, justificatif et compensation.
3. Vérifier que les pourcentages sont rendus dans un ordre non ambigu, par
   exemple `86٪` et `100٪`, jamais `% 86`.
4. Vérifier que les montants `MAD`, les valeurs négatives et les noms dynamiques
   restent lisibles et inchangés.
5. Confirmer l’absence de français résiduel, hors données utilisateur,
   historiques, marques et termes techniques volontairement conservés.

### Critère de sortie

Validation humaine acquise sur les deux surfaces après correction des
formulations Darija et du rendu bidi des pourcentages. Ne pas rejouer sauf
régression du code concerné.

## Autres contrôles humains P1-B

**Statut : les contrôles humains Web exécutables dans P1-B sont acquis. La
confidentialité des comptes reste `DEFERRED / BLOCKED BY CERT-L1H`.**

À exécuter dans la même session que le contrôle Darija :

- [x] Auth réelle : connexion, déconnexion, restauration après actualisation
  et après fermeture/réouverture du navigateur.
- [x] Clavier/accessibilité : `Tab`, `Shift+Tab`, focus visible, absence de
  piège à focus, ouverture de Ctrl+K et navigation sans souris.
- [x] Réseau : baseline connectivité, snapshots Enveloppes/Courses, absence de
  diagnostics techniques dans l'UI, création locale Course par les deux portes
  d'entrée, état pending, reconnexion, synchronisation automatique et absence
  de doublon validés humainement.
- [x] Fichiers : sélecteur Web, modèle de test, prévisualisation, annulation
  sans import et téléchargement réel d'un export validés humainement.
- [ ] Confidentialité des comptes : `DEFERRED / BLOCKED BY CERT-L1H`. Ce report
  n'est pas un FAIL fonctionnel P1-B. Le modèle L1 et sa projection de lecture
  existent, mais le gate d'activation maintient volontairement les RPC de
  mutation interdits aux utilisateurs authentifiés. Aucun sélecteur incomplet
  ne doit être exposé avant certification et activation contrôlée.

Acquis humains à ne pas rejouer sauf régression du code concerné :

- [x] Routage, historique Back/Forward et routes secondaires.
- [x] Responsive 390/430/720/900/1200/1440 et action Comptes mobile.
- [x] English LTR.
- [x] Arabic RTL.
- [x] Courses Darija : `التقضية` et état vide associé.
- [x] Analyses et Fin de mois Darija, textes système et pourcentages bidi.

Ne pas créer de recettes séparées ni transformer une impossibilité
d’automatisation en défaut produit.

Après certification Offline, exécuter un audit de performance Web mesuré
(démarrage, Auth → Dashboard, navigation, waterfall, requêtes, providers,
volume, N+1, rebuilds, bundle et chargement différé) avant toute optimisation.

### Contrat Offline V1 partagé — état avant retest humain

**Statut : `P1-B Offline Web = PASS humain`. Windows reste à certifier
séparément en runtime ; Android conserve sa certification P1-A.**

- Lecture locale certifiée automatiquement : **Enveloppes** et **Courses**.
  Une copie datée est conservée après une lecture distante réussie et signalée
  comme potentiellement obsolète pendant la coupure.
- Saisies locales autorisées : **tâches** et **articles de courses** uniquement.
  Elles gardent une identité stable, persistent entre navigations/reprises et
  restent affichées avec leur état de synchronisation.
- Reconnexion : sonde commune Flutter, revalidation utilisateur/foyer,
  synchronisation idempotente, puis rafraîchissement ciblé des Courses, Tâches,
  Calendrier, Alertes et Dashboard concernés.
- Mutations financières (FinancialEvent, GL, EnvelopeMovement, rapprochement,
  clôture, import définitif et transferts) : **serveur obligatoire** ; aucune
  réussite locale n'est simulée.
- Isolation : chaque copie locale est liée à l'utilisateur et au foyer exacts ;
  elle est refusée hors de ce périmètre et purgée au logout ou au changement de
  foyer. Les contrôles RLS restent la frontière d'autorisation distante.

Audit V1 des autres surfaces :

- les écrans statiques et préférences locales conservent leur fonctionnement
  sans réseau sans nécessiter de copie de données distante ;
- Dashboard, Comptes, Transactions, Budget, Dettes/créances, Calendrier,
  patrimoine, analyses et clôture restent distants ou serveur-obligatoires tant
  qu'un contrat de confidentialité, fraîcheur et invalidation propre à chaque
  projection n'a pas été certifié ;
- leur absence de cache n'autorise jamais l'affichage d'une exception brute ni
  l'interprétation d'une panne réseau comme une liste réellement vide ;
- l'extension de la lecture locale à ces projections est une amélioration P1
  distincte, après la certification humaine du socle Enveloppes/Courses.

## CERT-L1H — confidentialité des comptes et anti-inférence

**Statut : `READY / CLOSED LE 2026-11-16`. Certification hostile multi-session
achevée sur les surfaces existantes. Les preuves détaillées sont conservées dans
`docs/CERT_L1H_CLOSURE_2026-11-16.md`.**

La certification a été exécutée dans cet ordre :

1. certification hostile L1 ;
2. validation des protections anti-inférence ;
3. activation contrôlée des RPC de mutation de confidentialité ;
4. exposition de l'UX canonique dans **Argent → Comptes**, uniquement pour les
   modes réellement définis par L1 : `visible`, `balance_hidden`, `private` ;
5. certification humaine multi-session des demandes, consentements, refus,
   applications et révocations ;
6. contrôle transverse après chaque changement sur Comptes, Accueil, Analyses,
   Patrimoine, projections et totaux, recherche, alertes, exports,
   Assistant/AI, cache/offline et Realtime, afin de démontrer qu'aucune donnée
   cachée ne peut être reconstruite directement ou indirectement.

Contraintes de sortie :

- un solde non autorisé reste absent/null et n'est jamais remplacé par zéro ;
- un administrateur de foyer ne contourne pas automatiquement la
  confidentialité personnelle ;
- les contrats RLS, 1/2/N et les frontières anti-inférence restent effectifs ;
- ne pas inventer un quatrième mode « partage limité ». Toute évolution de ce
  besoin exige une décision produit séparée après audit ;
- la V1 ne peut pas être déclarée terminée si les modes L1 certifiés restent
  uniquement backend sans UX utilisateur fonctionnelle.

## Reliquat Cycle après CERT-L1H et avant Design Freeze

**Statut : `FUNCTIONAL FOLLOW-UP REQUIRED / NOT PART OF CURRENT CERT-L1H
MUTATION SCOPE`.**

- La projection Cycle partagée existe aujourd'hui dans **Foyer → Mon espace →
  Dates et phases partagées avec vous**. Elle est alimentée par
  `read_shared_cycle_calendar` et reste limitée aux dates et phases après
  consentement explicite.
- Il n'existe pas encore de surface autonome clairement nommée « calendrier
  partagé » ni de raccordement des projections Cycle au calendrier canonique
  utilisé par Accueil. Le contrôle CERT-L1H d'un calendrier partagé transverse
  est donc `NON TESTABLE / SURFACE ABSENTE`; l'absence ne vaut pas PASS.
- La ROADMAP historique place le calendrier partagé dans le **Lot 3 / gate L3**
  et le Cycle dans **L3B / R6-02 / CYC-X1**. Le contrat D1.2-B exclut
  explicitement le Cycle de la source calendrier du Dashboard actuel.
- Avant Design Freeze et finalisation V1, auditer puis décider le raccordement
  du Dashboard et du calendrier canonique selon ce contrat :
  - propriétaire : informations Cycle utiles autorisées sur son Dashboard ;
  - destinataire explicitement autorisé : dates et phases uniquement ;
  - membre non autorisé ou autre foyer : aucune information Cycle ;
  - symptômes, notes, flux, libido, pertes, contraception, rapports sexuels,
    protection, température, poids et autres observations intimes : toujours
    absents, y compris des KPI, résumés, Assistant, alertes, graphiques,
    recommandations, exports et caches ;
  - après révocation : disparition immédiate de toutes les projections
    destinataires sans réapparition depuis cache ou Realtime.
- Ce reliquat ne doit créer ni second moteur Cycle, ni projection parallèle, ni
  exposition avant certification hostile des contrats de lecture et
  d'anti-inférence.

## Reliquat Assistant conversationnel avant Design Freeze

**Statut : `V1 REQUIRED / NON TESTABLE — CONVERSATIONAL SURFACE ABSENT`.**

- L'Assistant déterministe L5 existant reste une fonction distincte, fiable et
  explicable. Il ne doit être ni supprimé ni présenté comme un assistant
  conversationnel libre.
- Le besoin conversationnel est déjà couvert par les identifiants historiques
  `AI-X2`, `R6-03` et `AI-X3`; aucun nouvel identifiant fonctionnel n'est créé.
  Leur preuve actuelle couvre le socle déterministe/provider-ready et les
  propositions contrôlées, mais pas une conversation IA libre en production.
- Avant Design Freeze et finalisation V1, livrer puis certifier l'architecture
  hybride suivante : question naturelle → contexte minimal autorisé → moteurs
  déterministes canoniques → réponse explicable. Toute action réelle reste une
  proposition explicitement confirmée et revalidée.
- Le contexte transmis doit appliquer les contrats L1 avant tout appel à un
  modèle : `visible` selon l'audience, `balance_hidden` sans montant ni
  reconstruction possible, `private` sans existence pour un non-titulaire, et
  données personnelles sensibles uniquement selon leur consentement propre.
- Le contrôle conversationnel CERT-L1H courant est donc `NON TESTABLE /
  SURFACE ABSENTE`; cette absence ne vaut pas PASS et ne bloque pas la poursuite
  des contrôles hostiles sur les surfaces réellement existantes.
