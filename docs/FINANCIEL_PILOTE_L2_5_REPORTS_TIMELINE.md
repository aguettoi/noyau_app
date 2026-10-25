# L2.5 — Rapports métier et timeline significative

## Périmètre

L2.5 ferme exclusivement `R4-05` et `R4-10`. La restitution est accessible depuis **Patrimoine & financements → Historique & échéances → Rapport & timeline**. Elle ne crée aucun événement financier et ne constitue ni un journal ni un moteur comptable parallèle.

## R4-05 — Rapport de clôture

- **Avant** : la clôture R2 et les lectures canoniques existaient, sans restitution métier assemblée.
- **Après** : un rapport mensuel compose les événements financiers autorisés, l'historique analytique importé visible, l'état de clôture, ses blocages, avertissements et limites.
- **Preuve** : `lib/features/reporting/domain/business_reporting.dart`, `reporting_provider.dart`, `business_reporting_panel.dart`, tests de domaine/widget et non-régression globale.
- **Statut** : **A — terminé + validé**.

## R4-10 — Timeline significative

- **Avant** : l'historique exhaustif existait, sans sélection significative distincte.
- **Après** : la timeline compose des faits canoniques selon des règles déterministes : correction/annulation, justificatif, obligation/créance, décision de clôture, échéance attendue/projetée, décision analytique importée, ou sélection manuelle personnelle.
- **Preuve** : provenance et statut structurés dans le domaine; table additive `timeline_significance_marks`, RLS personnelle et référence obligatoire à une source visible; tests de déduplication, ordre, période, volume et SQL/RLS.
- **Statut** : **A — terminé + validé**.

## Confidentialité et anti-inférence

Les sources financières, patrimoniales et historiques restent filtrées par leurs contrats serveur L1. La marque de significativité est personnelle, ne copie aucun montant et ne change jamais l'audience de la source. Le rapport ne calcule aucun « total foyer » mélangeant des valeurs invisibles et n'expose aucun compteur de lignes privées.

## Temporalité, provenance et performance

La période mensuelle est `[début inclus, mois suivant exclu)`. Les faits distinguent `réalisé`, `attendu`, `projeté` et `historique importé`. Les requêtes transactionnelles et historiques sont filtrées côté serveur avec une limite explicite; la composition est linéaire et dédupliquée. Un test couvre 2 000 événements, sans hypothèse sur le nombre de membres.

## Écritures et données pilote

La seule écriture possible est la métadonnée personnelle de sélection/désélection. Aucun `FinancialEvent`, transaction GL, posting, mouvement d'enveloppe, obligation ou élément patrimonial n'est créé. C3 et C4B restent inchangés.
