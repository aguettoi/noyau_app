# L2.4 — Patrimoine historique et échéancier consolidé

## Contrat livré

- `WLT-08` : historique fondé uniquement sur des valorisations datées réellement
  disponibles. La valeur actuelle complète reste distincte des points historiques
  partiels. Une valeur nette historique n'est calculée que si toutes ses
  composantes sont connues à cette date.
- `R4-06` : comparaison N/N-1 déterministe. Une absence de point complet est
  expliquée au lieu d'être remplacée par une estimation.
- `R4-07` : échéancier commun des obligations, financements F5 et occurrences
  attendues R3. Une obligation portée par un financement canonique n'est pas
  répétée comme une seconde échéance économique.
- `EXP-X2` : export CSV de la série affichée, comprenant date, composantes,
  complétude et explication. L'export est une lecture sans effet financier.

## Provenance et temporalité

Les valorisations saisies sont qualifiées comme telles. Les échéances projetées
ne deviennent jamais des paiements observés. Les dates de financement réutilisent
le calcul calendaire F5/L2.3, y compris les fins de mois. Les points historiques
peuvent conserver la dernière valorisation connue après sa date, mais ne recopient
jamais les liquidités ou passifs actuels dans le passé.

## Confidentialité

Le fournisseur compose exclusivement des contrats de lecture déjà autorisés :
comptes filtrés L1, obligations visibles, valorisations household-scoped et
occurrences R3 protégées. L'export ne contient aucun identifiant de compte ni
total caché permettant de reconstituer un solde privé. Une série incomplète reste
incomplète plutôt que de produire un agrégat révélateur.

## Invariants

- zéro FinancialEvent, GL posting ou mouvement d'enveloppe créé ;
- aucun snapshot opportuniste ni nouvelle source de vérité ;
- aucune migration ;
- aucune donnée pilote créée ou modifiée ;
- fonctions compatibles 1/2/N parce qu'aucun membre n'est codé en dur.
