# L2.8 — restauration fonctionnelle canonique isolée

Date de certification : 25 octobre 2026.

## Frontière du lot

L2.8 couvre `R4-09` : reconstruire les données fonctionnelles d'un foyer à
partir d'une archive canonique dans une cible vide et isolée. Ce mécanisme
n'est ni une restauration PostgreSQL/Supabase, ni un import Google Sheet, ni
un bouton de restauration libre-service.

L'export utilisateur ZIP existant reste filtré selon les droits du demandeur.
Son `manifest.json` porte `restore_eligible=false`; le restaurateur le refuse.
Une archive canonique porte au contraire le format
`financiel-pilote-household-archive`, la version `1`, l'identifiant du foyer
source, la date UTC, le nombre de lignes et l'empreinte SHA-256 de chaque jeu.

## Périmètre version 1

Restauré et contrôlé :

- foyer et membres métier, avec identités Auth cibles fournies séparément ;
- comptes et enveloppes ;
- `FinancialEvent`, transactions GL et postings ;
- mouvements d'enveloppes ;
- obligations et règlements ;
- actifs, propriétaires, valorisations, investissements, opérations
  d'investissement et financements patrimoniaux ;
- observations de solde et inventaires espèces par coupures.

Non restauré par R4-09 : utilisateurs/mots de passe Auth, secrets, sessions,
Storage binaire, configuration Supabase, journaux d'infrastructure, sauvegarde
physique PostgreSQL et données Google Sheet de cutover. Ces éléments sont
respectivement `N/A` ou relèvent de P1/A1/CUT.

## Ordre et mapping

Ordre canonique : foyer → membres → comptes → enveloppes → événements →
transactions → postings → mouvements d'enveloppes → obligations → règlements
→ actifs → valorisations → observations espèces.

Les UUID source ne sont jamais réutilisés comme preuve d'identité dans la
cible. Le restaurateur crée un mapping source→cible pour le foyer et chaque
objet. Les membres reçoivent une correspondance explicite vers des identités
techniques de la cible ; aucune identité Auth n'est inventée. Les références
et acteurs sont réécrits uniquement depuis ce mapping. Une référence absente
fait échouer l'opération entière.

## Sécurité et intégrité

- cible obligatoirement vide pour une première restauration ;
- isolation cross-household vérifiée avant encodage et après décodage ;
- archive inconnue, incomplète, altérée ou de version incompatible refusée ;
- écritures préparées dans un état temporaire puis publiées en une fois ;
- rollback implicite complet si une validation échoue ;
- seconde exécution de la même archive détectée par son empreinte, sans doublon ;
- seconde archive sur une cible non vide refusée ;
- débit = crédit pour chaque transaction GL ;
- règlements d'obligation plafonnés au montant initial ;
- paramètres de confidentialité conservés comme données fonctionnelles et
  jamais élargis par le mapping ;
- aucune écriture vers le foyer source ou C3.

Les soldes dérivés ne sont pas stockés par le restaurateur : ils restent à
recalculer par les moteurs canoniques à partir des postings et mouvements
restaurés. Aucun ajustement fictif n'est créé pour forcer une égalité.

## Procédure certifiée

1. Produire l'archive canonique depuis une extraction autorisée et cohérente.
2. Créer une cible technique vide et isolée.
3. Créer les identités Auth techniques nécessaires hors archive.
4. Fournir le mapping des membres source vers ces identités.
5. Décoder et valider manifeste, version, empreintes et foyer.
6. Restaurer dans l'ordre canonique via `IsolatedHouseholdRestorer`.
7. Comparer valeurs métier, relations, acteurs et cardinalités plutôt que les
   UUID.
8. Recalculer les soldes dérivés avec les moteurs canoniques.
9. Détruire la cible technique après certification si elle n'est plus utile.

## Preuves automatisées

`test/portability/canonical_household_restoration_test.dart` exécute une vraie
reconstruction dans un magasin isolé sans accès au foyer pilote. Il couvre
1/2/N membres, remapping, confidentialité, patrimoine, inventaire espèces,
archive corrompue/incompatible/non restaurable, référence orpheline, GL
déséquilibré, atomicité et idempotence. Les tests d'encodeurs confirment aussi
que l'export utilisateur reste lisible et explicitement non restaurable.

Limite assumée : cette certification reconstruit le périmètre fonctionnel
R4-09 dans une cible isolée en mémoire. La reconstruction physique d'une base
Supabase depuis toutes les migrations et la reprise d'infrastructure restent
des certifications techniques distinctes ; elles ne sont pas déclarées PASS
par L2.8.
