# R3.2 — Projection de trésorerie consolidée

## Architecture

R3.2 est un compositeur Dart déterministe et strictement read-only. Il lit les soldes canoniques du Grand Ledger, les enveloppes, les intentions et occurrences R3.1 ainsi que les échéanciers F5. Il ne possède aucune table, aucun cache comptable et aucune primitive de mutation.

FinancialAvailability reste la référence pour répondre à « puis-je financer cette décision ? ». Budget Intelligence reste la référence des allocations. R3.2 répond uniquement à « quels flux sont attendus et quel solde en résulte à une date ? ».

## Sources et priorité anti-double-comptage

1. Une occurrence R3.1 persistée prime sur toute projection synthétique de sa récurrence.
2. Une occurrence réalisée ou ignorée est exclue. Une occurrence partielle ne contribue que pour son reliquat.
3. Une échéance F5 de même montant, dans une fenêtre de trois jours autour d'une dépense R3.1, est exclue : R3.1 prime.
4. Les allocations Budget ne sont jamais traitées comme des mouvements bancaires. Elles sont des règles d'affectation, pas des sorties de trésorerie.
5. FinancialAvailability, le calendrier et les alertes ne sont pas additionnés : ce sont des projections ou présentations des mêmes sources.
6. Objectifs, PRIOS et Shopping restent hypothétiques tant qu'aucun engagement financier canonique daté ne les matérialise.

## Agrégation

- Revenu : augmente le foyer et, si connu, le compte destination.
- Dépense/échéance : diminue le foyer et, si connu, le compte source.
- Transfert interne : diminue la source, augmente la destination, effet foyer nul.
- Compte, enveloppe ou membre inconnu : le flux reste visible dans le foyer sans localisation inventée.
- Enveloppe : projection budgétaire distincte de la position bancaire physique.

Horizons : fin du mois, mois suivant, 3, 6 et 12 mois. Les récurrences actives sont prolongées en mémoire jusqu'à l'horizon ; suspendues et arrêtées ne le sont pas.

## Certitude et explication

Chaque flux expose sa date, son montant, sa source et ses références connues. Le contrat accepte les niveaux certain, estimé et hypothétique. Les occurrences R3.1 et échéances contractuelles F5 sont certaines ; aucune hypothèse Budget/Objectif n'est injectée silencieusement.

Les risques sont déterministes : premier passage négatif d'un compte connu ou de la trésorerie globale. Aucun score opaque n'est utilisé.

## Epargne, Habits et Reste épargne

Habits conserve sa réalité multi-compte par les références des flux et des positions canoniques. Reste épargne reste distincte d'Epargne. Le sweep de fin de mois de Navette, Nourriture et Sorties WE vers Epargne est expliqué comme règle budgétaire ; sans preuve d'un transfert bancaire, R3.2 ne crée ni ne projette un faux mouvement vers Arreda.

## Sécurité, RLS, Realtime et performance

R3.2 n'ajoute aucune surface SQL : il réutilise exclusivement les providers household-scoped déjà protégés par RLS. Il ne peut donc pas contourner l'isolation foyer. Les invalidations globales/Reatime invalident également la projection. Le calcul charge les sources une fois puis agrège en mémoire, sans requête par jour, compte ou enveloppe.

## Limites connues

- Le choix interactif d'un scénario alternatif est reporté jusqu'à ce qu'un contrat explicite transforme ses différences en flux datés sans confondre allocations et trésorerie.
- Une règle Budget sans occurrence ou échéance datée n'est pas inventée comme flux.
- Le montant futur du sweep Epargne n'est pas estimé sans reliquat mensuel calculable et confirmé.
- Les propositions automatiques et simulations avancées appartiennent à R3.3.
