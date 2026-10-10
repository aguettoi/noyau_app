# Arbitrages ouverts

| ID | Décision attendue | Options | Recommandation | Impact |
|---|---|---|---|---|
| ARB-01 | Offline exigé au lancement | P0, P1 ou post-V1 | Décider avant gel R2 | Architecture des mutations |
| ARB-02 | Flux autorisés offline | lecture, quotidien, toutes mutations | Commencer par lecture/flux maîtrisés | Conflits et doubles écritures |
| ARB-03 | Confidentialité fine | household seul ou personnel/partagé/rôles | Concevoir serveur-first | RLS, Search, Export, IA |
| ARB-04 | Cycle menstruel | absent, privé, partage explicite | Après ARB-03 | Données sensibles |
| ARB-05 | IA V1 | aucune, explication, recommandations | Reporter avant garde-fous | Confidentialité/décision |
| ARB-06 | Données accessibles à l’IA | agrégats, transactions, patrimoine, privé | Moindre accès | Consentement et sécurité |
| ARB-07 | Attribution KPI qualité | actor, payeur, responsable, foyer | Foyer/non attribué sans preuve | Évite accusation erronée |
| ARB-08 | Blocages clôture | stricts, avertissements, mix | Mix explicable | UX close/reopen |
| ARB-09 | Clôture avec anomalies | interdite ou override OWNER motivé | Override limité et audité | Gouvernance du mois |
| ARB-10 | Enveloppe répartie sur comptes | règle durable, mensuelle, aucune | Règle légère si nécessaire R2 | Régularisation globale |
| ARB-11 | Frais notaire | calculateur ou hypothèse scénario | Hypothèse sauf usage répété | Évite surmodélisation |
| ARB-12 | Vente immobilière | scénario ou workflow dédié | Scénario générique d’abord | Réutilisation F5 |
| ARB-13 | Comparateur prêts | offres génériques ou banques nommées | Offres paramétrables | Pas de hardcoding |
| ARB-14 | Fiscalité marocaine | règles versionnées ou saisie libre | Versionner après validation métier | Risque de règle périmée |
| ARB-15 | Restauration portabilité | export seul ou restauration certifiée | Concevoir séparément | Risque données élevé |
| ARB-16 | PPTX V1 | obligatoire ou P2 | P2 après XLSX/PDF | Ne bloque pas R2 |
| ARB-17 | Langues V1 | FR+AR ou quatre langues | Architecture complète, traductions par phases | Volume de recette |
| ARB-18 | Darija | arabe, latin, les deux | Décision éditoriale | Glossaire et RTL |
| ARB-19 | Landing Web | Flutter Web ou site distinct | Même backend/marque, logique non dupliquée | Déploiement/Auth |
| ARB-20 | Organisation ménage | tâches suffisantes ou champs dédiés | Ajouter seulement les champs encore utilisés | Évite surmodélisation |
| ARB-21 | Timeline significative | règles, sélection humaine, IA | Déterministe d’abord | Dépend reporting |
| ARB-22 | Inventaire par coupures | V1 ou post-V1 | Post-V1 sauf besoin démontré | Non bloquant |
| ARB-23 | iOS | certification V1 ou compatibilité | Compatibilité sans environnement Apple | Décision lancement |
| ARB-24 | Commandes mobiles | complet ou recherche seule | Desktop d’abord | Complexité UX |
