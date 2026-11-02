# L5 — Assistant encadré

## Contrat livré

L5 fournit un assistant V1 déterministe utilisable sans fournisseur externe,
sans abonnement et sans coût obligatoire. Il compose exclusivement des résumés
déjà autorisés issus des moteurs canoniques. Il ne possède aucun accès service
role, aucun credential IA et aucun chemin d'écriture financière.

```text
UI Flutter
  → Assistant use case / controller Riverpod
    → AssistantContextBuilder (minimum autorisé par cas)
      → providers canoniques soumis à Auth/RLS/L1
    → AssistantProvider
      → DeterministicAssistantProvider (V1 obligatoire)
      → provider génératif optionnel futur (jamais base brute)
```

## Contexte et confidentialité

`AuthorizedAssistantContext` contient seulement l'identité de l'appelant et du
foyer, le cas d'usage, des compteurs/indicateurs autorisés et les catégories de
sources. Il exclut les lignes brutes, identifiants de comptes, noms, notes,
descriptions libres, soldes cachés et données Cycle. Les agrégats utilisés ne
permettent pas de reconstruire un montant privé. Un indicateur explicite signale
qu'une donnée cachée a été exclue sans en révéler l'existence détaillée.

Les huit cas V1 sont budget, résumé mensuel, anomalies, PRIOS, organisation,
shopping, patrimoine/financement et aide produit. Chaque réponse distingue
fait, calcul/règle, suggestion et incertitude. Une donnée insuffisante produit
une incertitude, jamais une invention.

## Actions

Une proposition est un objet structuré avec type, objectif, paramètres,
justification, sources, risque, expiration et état. Le workflow impose
proposition puis confirmation et revalidation. La V1 L5 n'autorise que les
actions de navigation vers les surfaces canoniques. Tout type financier est
refusé fermé et n'atteint aucun executor. Les états couverts sont `proposed`,
`confirmed`, `rejected`, `expired`, `executed` et `failed`.

## Audit et contenu non fiable

L'audit local persistant contient uniquement utilisateur, foyer, cas d'usage,
horodatage, mode, catégories de sources et état de proposition. Il n'enregistre
ni prompt brut, ni secret, ni contexte privé. Les libellés, notes, imports et
contenus externes ne sont jamais interprétés comme des instructions.

## Provider optionnel

`AssistantProvider` est indépendant de l'UI. Un futur adapter génératif recevra
uniquement le contexte déjà filtré et n'aura aucun pouvoir d'écriture. Son
absence ou son échec conserve le mode déterministe. Aucun provider génératif
n'est requis ou configuré dans L5; coût externe obligatoire : **0,00 MAD**.

## Limites reportées

- qualité conversationnelle générative et provider éventuel : décision future;
- certification réseau/provider réel : uniquement si un provider est autorisé;
- recette visuelle et lecteurs d'écran réels : D1.2/P1;
- toute nouvelle action métier exécutable exigera un adapter canonique,
  revalidation, permission serveur, idempotence et tests dédiés.
