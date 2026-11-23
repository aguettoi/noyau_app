# F1 — IA générative reportée après les premières ventes

Date de décision : 23 novembre 2026
Statut canonique : **DEFERRED / PRESERVED / NOT PRODUCTION-CERTIFIED**

## Décision produit

L'IA générative n'est plus un bloqueur de la V1 commerciale. Le travail F1
est préservé, mais son activation runtime est reportée après les premières
ventes et l'attribution d'un budget fournisseur adapté. Cette décision est un
report volontaire : elle ne certifie pas le runtime génératif et ne transforme
pas l'échec du provider gratuit en validation.

## Pourquoi

- l'IA générative n'est pas indispensable au coeur du MVP financier ;
- aucun provider gratuit essayé n'a atteint un niveau de fiabilité certifiable ;
- poursuivre une solution gratuite temporaire consommerait du temps sans
  améliorer la stabilité commerciale ;
- la priorité V1 devient la qualité produit, le Design Freeze et les gates de
  production ;
- un budget post-revenus permettra de retenir un fournisseur payant avec des
  engagements adaptés aux données familiales et financières.

## État technique préservé

Sont conservés et versionnés :

- contrats conversationnels provider-agnostic ;
- orchestrateur et historique multi-tour gouverné ;
- registre de capacités déterministes et projections minimisées ;
- séparation READ / RECOMMEND / PREPARE / EXECUTE ;
- règles absence ≠ zéro, devise canonique et anti-hallucination ;
- protections CERT-L1H et F2, invalidation après révocation et audit expurgé ;
- adaptateur Supabase et Edge Function `assistant-conversation` ;
- gestion contrôlée des erreurs et fallback déterministe ;
- i18n FR/EN/AR/ary et RTL ;
- validations automatisées F1 précédemment acquises : **67/67 PASS**.

Le runtime génératif réel reste **non certifié**. Les mécanismes temporaires du
single-shot (`provider_gate`, secret de gate, plafond d'essais spécifique et
télémétrie de structure) ont été retirés : ils n'apportaient aucune valeur à
la V1 endormie et augmentaient la surface d'appel.

## UX de la V1 commerciale

La V1 expose l'assistant déterministe local, fondé sur les moteurs canoniques.
La zone de saisie conversationnelle générative est désactivée par défaut via
`ENABLE_GENERATIVE_ASSISTANT=false`. Son absence ne bloque ni le démarrage, ni
la navigation, ni Finance, Foyer ou Cycle, et ne déclenche aucun appel réseau
IA permanent. Une future activation exige un build explicitement configuré et
les gates ci-dessous.

L'assistant déterministe n'est pas présenté comme substitut certifié de
l'assistant conversationnel ; il reste une fonction V1 autonome, explicable et
sans provider externe.

## Provider historique

OpenRouter et plusieurs modèles gratuits, dont
`nvidia/nemotron-3-ultra-550b-a55b:free`, ont été utilisés uniquement pendant
des expérimentations Sandbox. Aucun n'est un provider de production retenu ou
certifié.

## Conditions de réactivation F1

Le gate **AI PROD DATA-RESIDENCY & PRIVACY DECISION** est obligatoire avant
toute activation avec des données réelles :

1. budget IA et plafond de coûts définis ;
2. comparaison documentée des fournisseurs et modèles ;
3. région et résidence des données approuvées ;
4. DPA, sous-traitants, ZDR/rétention, journaux et suppression validés ;
5. SLA, stabilité, continuité et latence acceptés ;
6. qualité FR/AR/Darija mesurée ;
7. modèle fixe et contrat de sortie retenus ;
8. intégration Sandbox puis provider gate réel ;
9. certification runtime multi-tour, multilingue, privacy et coûts ;
10. autorisation explicite d'activation Production.

Le texte libre volontairement saisi par l'utilisateur peut lui-même contenir
des informations sensibles. Avant réactivation, une décision produit et
sécurité doit définir la minimisation, l'avertissement utilisateur, la base
légale, la rétention et les informations qui ne doivent jamais quitter les
moteurs FINANCIEL.

## Classement de consolidation

- **A — F1 stable à versionner** : code Flutter conversationnel, contrats,
  capacités, adaptateur Edge, Edge Function, i18n et tests F1.
- **B — diagnostic utile à conserver** :
  `F1_PROVIDER_GATE_BLOCKED_2026-11-21.md` et le présent document.
- **C — temporaire retiré** : phase/secret single-shot et télémétrie de
  structure du provider gate.
- **D — hors F1 laissé intact** : deux différences historiques de fin de ligne
  SQL, documents DOCX, inspection/aperçu du modèle Excel et travaux F2.
- **E — incertain laissé intact** : tout fichier non attribuable sans preuve au
  lot F1.

## Roadmap V1 recalculée

`F1 GENERATIVE = DEFERRED POST-FIRST-REVENUE` et n'est plus un bloqueur V1.
Il n'est ni `CERTIFIED`, ni fonctionnellement `CLOSED`, ni production-ready.

- **Avancement fonctionnel V1 estimé : 96 %**. Le dénominateur V1 exclut
  désormais le runtime génératif reporté ; les 4 % restants représentent les
  reliquats fonctionnels à confirmer avant gel, sans crédit fictif.
- **Readiness Production estimée : 68 %**. Cette estimation attribue les acquis
  au coeur fonctionnel, CERT-L1H, F2 et P1 ; les 32 % restants couvrent le
  Design Freeze/UI-UX, Developer Readiness et audit architecture, audit
  sécurité/production, régression finale multiplateforme et cutover.

Ces pourcentages sont des estimations de pilotage, pas des certifications. La
V1 ne peut atteindre 100 % avant la fermeture factuelle de tous les gates
restants.

## Prochaine étape recommandée

**DESIGN FREEZE / UI-UX**, dans un lot séparé. Ce document ne l'autorise ni ne
le démarre.
