# FINANCIEL PILOTE — Registre canonique des fonctions V3

Date de décision : 14 novembre 2026
Total canonique traçable : **173**

## Source de vérité

| Étape | Total annoncé | Total identifiable | Décision |
|---|---:|---:|---|
| Master Scope V2 | 132 | 132 | Base cohérente |
| Historical Scope Audit | 163 dans la matrice principale | 167 | Quatre lignes réelles après une rupture de tableau |
| Remaining Scope After L1 | 167 | 167 | Référence pré-L3A |
| L3A | 175 | 172 | Erreur arithmétique de +3 : cinq IDs seulement ont été ajoutés |
| L3B | — | +0 | Réutilisation d'IDs existants |
| L4 | — | +1 | `NET-X1` |
| Roadmap V3 initiale | 169 | 169 | Sous-comptage de 4 dû à la rupture de tableau |
| Registre corrigé | — | **173** | Référence canonique |

## IDs réintégrés sans recréation

| ID | Statut vérifié | Preuve principale |
|---|---|---|
| `HID-01` | DONE | Déclencheur type/date des scénarios budgétaires |
| `HID-02` | DONE | Catégories d'organisation exposées par L3B |
| `LEG-01` | DONE | Contrat de lancement finalisé par L1 |
| `LEG-02` | DONE | Modèle membre/foyer finalisé par L1 |

## Totaux de statut corrigés

| Statut | Nombre |
|---|---:|
| DONE | 155 |
| PARTIAL | 6 |
| DEFERRED | 10 |
| PLANNED | 2 |
| **TOTAL** | **173** |

## Historique auditable de l'anomalie

1. Le registre pré-L3A comportait 167 fonctions.
2. L3A a ajouté cinq identifiants mais a annoncé 175 au lieu de 172.
3. L4 a ajouté `NET-X1`, portant le total réel à 173.
4. Le générateur V3 s'est arrêté à une rupture de tableau et a omis `HID-01`, `HID-02`, `LEG-01` et `LEG-02`, produisant 169.
5. Aucun ID n'a été inventé pour corriger les comptes.

Les listes atomiques historiques restent dans `FINANCIEL_PILOTE_HISTORICAL_SCOPE_AUDIT.md` et `FINANCIEL_PILOTE_V1_REMAINING_SCOPE_AFTER_L1.md`. Tout générateur futur doit lire toutes les tables et vérifier l'unicité des IDs ainsi que le total attendu de 173.
