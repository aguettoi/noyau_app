# L3B — Organisation quotidienne, rappels et données privées

## Livraison

L3B étend les moteurs F6/R3.3/L1 sans créer de calendrier, centre d’alertes,
Shopping financier ni moteur de confidentialité parallèle.

| ID | État | Preuve livrée |
|---|---|---|
| ORG-06 | A | Centre d’alertes existant étendu par le rappel de saisie quotidien. |
| ORG-07 | A | Préférences personnelles in-app étendues; notifications natives restent P1. |
| ORG-08 | A | Contrats, garanties et maintenance structurés et projetés dans CalendarItem. |
| R6-01 | A | Organisation ménage enrichie par pièce, durée, charge et responsable 1/2/N. |
| ORG-X1 | A | Courses domestiques dédiées; aucune confusion avec Shopping financier. |
| ORG-X2 | A | Métadonnées ménage saisissables et visibles dans les tâches F6. |
| ORG-X3 | A | Maison structurée et calendrier canonique réutilisé. |
| HID-02 | A | Référentiel `categories` canonique exposé depuis Vie quotidienne. |
| R6-02 | A | Cycle utilisable, privé par défaut, partage ciblé et révocable. |
| CYC-X1 | A | Phases, dates, flux, symptômes et notes; partage limité aux dates/phases. |

## Sécurité et confidentialité

- `member_cycle_events` est lisible et modifiable uniquement par son propriétaire.
- Le rôle administrateur du foyer ne donne aucun accès aux détails personnels.
- `read_shared_cycle_calendar` ne retourne que l’identifiant, le propriétaire,
  les dates et la phase après consentement explicite. Notes, symptômes et flux ne
  figurent jamais dans ce contrat.
- La révocation supprime immédiatement la projection partagée.
- Les nouvelles tables foyer utilisent les RLS household et le signal Realtime
  expurgé L1; aucune table L3B n’est publiée brute.
- Les tests SQL transactionnels couvrent membre non autorisé, cross-household,
  partage, révocation et anti-inférence par minimisation du résultat.

## Rappel quotidien

À partir de 20 h dans le fuseau canonique, le centre d’alertes propose `Fait` et
`Pas encore`. `Fait` acquitte seulement l’état personnel. `Pas encore` enregistre
une échéance à exactement quinze minutes de l’action. Aucun de ces gestes n’écrit
dans FinancialEvent, GL ou Envelope Ledger. Les notifications natives restent P1.

## Données et compatibilité

La migration `20261026195613_l3b_daily_life_private_cycle.sql` est additive et
appliquée au Sandbox. Toutes les fixtures de sécurité sont rollbackées. C3, C4B,
soldes, obligations et snapshots restent inchangés.

La dette Dashboard au-delà de 5 000 opérations est déjà couverte par la lecture
paginée stable livrée avec L3A; elle n’est pas dupliquée dans L3B.
