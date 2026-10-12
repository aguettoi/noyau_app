# Progression UI/UX

## R2.7

- Le paramétrage centralisé distingue désormais une recommandation mono-compte, une règle multi-comptes, une règle selon bénéficiaire et l'enveloppe système.
- L'absence de moyen de paiement reste facultative et n'empêche plus l'état « Configurée » dès que la règle structurelle est connue.
- `Habits` affiche « Règle commune — plusieurs comptes » ; `Reste epargne (primes Ibrahim et Nora)` affiche « Selon le bénéficiaire / membre » ; `À répartir` n'est plus présenté comme une enveloppe métier à paramétrer.
- La localisation actuelle reste volontairement « à fiabiliser » jusqu'à l'inventaire humain initial ; la recommandation future n'est jamais présentée comme une preuve de position historique.

## R2.5

- La surface Scénarios budgétaires reçoit les six scénarios reconstruits depuis la source certifiée ; `DEPART` est le seul scénario actif et par défaut.
- Les revenus 12 800 MAD / 15 000 MAD sont libellés comme paramètres de référence du scénario pilote, jamais comme revenus réels actuels.
- `Reste epargne (primes Ibrahim et Nora)` reste hors budget mensuel récurrent ; aucune allocation de 1 500 MAD n'est créée.
- L'aperçu du programme explique désormais la « Répartition des dépenses communes » en vocabulaire utilisateur : montant disponible après dépenses personnelles et pourcentage appliqué. Les termes techniques de stratégie de clé restent internes au moteur.
- Fin de mois affiche `Budget MM/AAAA — Scénario DEPART` et utilise les comptes de financement du scénario. Les répartitions multi-comptes, dont `Habits`, sont calculées proportionnellement avec correction déterministe du centime.
- Le scénario est historisé sur le mois au premier snapshot ; un changement le mois suivant ne réécrit pas le mois précédent. Le moyen de paiement est une recommandation facultative et non un blocker de cible/clôture.
- Les rattachements structurels réellement absents restent visibles et bloquants. Sur le foyer pilote, `Epargne` et `Reste epargne (primes Ibrahim et Nora)` exigent encore une décision humaine de compte cible avant une preview complète.

## R2.4

- Paramétrage global des enveloppes dans une grille Desktop/Web et des cartes mobiles, sans configuration fenêtre par fenêtre.
- Sélecteurs filtrés sur les comptes actifs et moyens de paiement actifs/compatibles avec compte et titulaire.
- État visible `À configurer`, `Moyen inactif` ou `Configurée`.
- Accès direct depuis Enveloppes et depuis l’alerte `Paramétrage minimal manquant` de Fin de mois, avec retour conservé.
- Source Budget/scénario explicitement affichée ; absence de scénario reliée à la surface Budget canonique.
- Cas multi-comptes renvoyé vers les règles structurelles du scénario, sans dérogation mensuelle permanente.

## R2.3

- Parcours guidé transformé en étapes actionnables avec états et motifs de blocage.
- Centre À faire conserve le contexte précis et ouvre directement le compte concerné.
- Matrice compte × enveloppe plein écran : grille Desktop/Web, cartes par enveloppe sur mobile, contrôles lignes/colonnes et absence d’overflow.
- Cibles automatiques identifiées par leur source ; dérogations manuelles visuellement distinctes.
- Inventaire espèces sécurisé : champ réel vide, écart live, motif conditionnel.
- Santé du mois décomposée et séparée du statut de clôture.

## R2

- Surface Fin de mois accessible depuis Pilotage.
- Design System partagé (`FpPageHeader`, `FpCard`, tokens et breakpoints).
- Desktop/Web : largeur utile exploitée par des cartes compactes et des groupes adaptatifs.
- Mobile : contenu scrollable, actions tactiles, aucun tableau desktop imposé.
- États loading, error, empty/sain et blocked.
- Score de santé expliqué par blockers et warnings ; aucune couleur n'est la seule porteuse de sens.
- Réouverture OWNER : confirmation, motif obligatoire, état de chargement, succès/erreur et historique visibles.
- Centre À faire : accès direct aux modules Comptes, Transactions et Compensations ; ciblage de l'objet précis encore à compléter.
- Cibles compte × enveloppe : liste et formulaire responsive reliés au RPC canonique, verrouillés lorsque le mois est clôturé.
- Position actuelle / cible / écart : exposés avec état explicite « à fiabiliser » tant que le point de départ n'est pas réconcilié.
- Point de départ : formulaire OWNER multi-lignes, contrôlé par les deux ledgers et sans écriture financière.
- Régularisation globale : prévisualisation détaillée par enveloppe, confirmation explicite et virement canonique idempotent ; recette visuelle humaine restante.
- Recette visuelle humaine multi-plateforme à réaliser dans P1/R8.
