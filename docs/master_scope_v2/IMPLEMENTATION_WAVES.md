# Vagues d’implémentation

L’ordre directeur de la Roadmap Master V2 est conservé. Le reporting R4 suit R2/R3 car il dépend des définitions de clôture et de projection. La décision offline/confidentialité doit être prise tôt, mais l’implémentation reste après les flux métier prioritaires.

| Vague | Contenu | Sortie attendue | Justification |
|---|---|---|---|
| R0 | Master Scope V2 | Inventaire, gaps, arbitrages et dépendances | Référence de gel |
| R1 continu | UI/UX évolutive | Toute nouvelle surface utilise le Design System | Évite une dette supplémentaire |
| R2A | Clôture et checklist | IMPLÉMENTÉ — dossier mensuel, blockers/warnings, close/reopen audités | Fondation du cycle |
| R2B | Centre À faire | IMPLÉMENTÉ — projection actionnable des sources canoniques | Réutilise F2/F3/F6 |
| R2C | Régularisation globale | IMPLÉMENTÉ — cibles mensuelles et plan minimal read-only | Exécution via flux canoniques |
| R2D | KPI qualité | IMPLÉMENTÉ — santé explicable, pièces, rapprochement, inventaires | Foyer/non attribué par défaut |
| R3A | Récurrents confirmables | Attendu/réel/variation et échéancier | Alimente projection |
| R3B | Projection J+30/J+90 | Cashflow expliqué et scénarios | Réutilise FinancialAvailability |
| R3C | Rappels et règles | 20h, snooze, pré-clôture, préférences | Livraison native en P1 |
| R4A | Exports structurés | XLSX 4 feuilles, PDF, échéancier | Repose sur R2/R3 |
| R4B | Bilan annuel et PPTX | N/N-1, faits marquants, perspectives | Après modèle stable |
| R4C | Emprunt enrichi | Échéance cible, offres, IR, exports | Étend F5 |
| R5A | Onboarding et invitations | Configuration guidée skippable | Avant vrais utilisateurs |
| R5B | Aide, i18n et RTL | Centre aide et langues | Après stabilisation des textes |
| R5C | Landing et commandes | Distribution et command palette | Dépend du packaging |
| R6 | Organisation complémentaire | Uniquement les écarts Sheet utiles | Cycle/IA restent arbitrés |
| R7 conception | Offline/confidentialité | ADR, menaces, périmètre, conflits | Go/no-go obligatoire |
| R7 exécution | Si validé | Queue chiffrée et/ou visibilité fine | Impact transversal |
| R8 | Gel et D1 final | Aucune fonction obligatoire ouverte; recette 74+ surfaces | Gate avant P1 |
| P1 | Certification | Windows, Web, Android, Auth, deep links, notifications | Validation réelle |
| A1/A2 | Audit et corrections | Sécurité, performance, Supabase, Git, CI/CD | Gate cutover |
| FINAL | Cutover | Vrais comptes, dernier Sheet, mois réel | Abandon du Sheet |

## Critères de passage

- R2 : close/reopen auditables, observation sans écriture financière.
- R3 : projections explicables, aucune création réelle sans confirmation.
- R4 : tous les totaux proviennent des sources canoniques.
- R7 : aucun développement sans arbitrage.
- R8 : validation visuelle humaine, pas seulement des tests.
