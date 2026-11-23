# F1 — Assistant conversationnel gouverné — état officiel après Provider Gate

> Historique de diagnostic. La décision produit canonique du 23 novembre 2026
> est désormais documentée dans
> `F1_GENERATIVE_AI_DEFERRED_POST_REVENUE_2026-11-23.md` : F1 génératif est
> volontairement reporté après les premières ventes, préservé mais non certifié
> pour la production.

Date de référence : 21 novembre 2026

## Verdict

**F1 global : NOT READY — BLOCKED BY SANDBOX AI PROVIDER / PROVIDER GATE**

Cet état ne remet pas en cause la stabilisation de l'architecture F1. Il interdit en revanche de présenter le runtime génératif comme certifié.

## État acquis

- Architecture et code F1 : **CONSOLIDATED STABILIZATION PASS**.
- Validations automatisées consolidées : **67/67 PASS**.
- Protections CERT-L1H directement impactées : **PASS**.
- Architecture conservée : provider-agnostic, capacités déterministes autorisées, minimisation du contexte, séparation READ / RECOMMEND / PREPARE / EXECUTE, absence distincte de zéro, devise canonique et barrières anti-hallucination.
- Runtime génératif réel : **NOT CERTIFIED**.

## Provider Gate final

- Résultat : **FAIL**.
- Cause observée : `HTTP 404 — endpoint preflight indisponible`.
- Durée : `4,452 s`.
- Aucune nouvelle tentative n'est autorisée dans ce lot.
- `nvidia/nemotron-3-ultra-550b-a55b:free` n'est pas retenu comme provider fiable ou certifié.
- Aucun quatrième modèle gratuit ne doit être recherché dans F1.

## Dette et reprise future

Le choix définitif du fournisseur, du modèle et de la région est reporté à un lot dédié. Cette reprise doit conserver l'architecture provider-agnostic existante et ne doit pas rouvrir les travaux automatisés déjà acquis sans régression démontrée.

Avant toute donnée réelle, tout cutover ou toute ouverture commerciale, le gate suivant reste bloquant :

**AI PROD DATA-RESIDENCY & PRIVACY DECISION**

Ce gate devra certifier au minimum : fournisseur, modèle fixe, région d'exécution, résidence des données, politique de rétention, utilisation éventuelle des données par le fournisseur, journalisation, sous-traitants, suppression, disponibilité, latence, coûts, continuité de service et conformité aux protections CERT-L1H.

## Interdictions conservées

- aucune donnée réelle ou compte réel transmis à un provider non certifié ;
- aucun secret, montant masqué, compte privé ou donnée Cycle intime envoyé inutilement ;
- aucun contournement architectural pour adapter F1 à un provider défaillant ;
- aucun statut READY sans conversation générative réelle, multi-tour et multilingue certifiée en runtime.
