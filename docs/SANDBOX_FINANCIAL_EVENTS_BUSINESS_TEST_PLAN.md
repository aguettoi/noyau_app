# FinancialEvent — plan de tests Sandbox

À exécuter seulement lorsque `ready_for_business_tests=true`, avec données isolées et clés d’idempotence neuves.

1. Dépense cash : compte −, charge +, enveloppe −, un événement.
2. Dette, règlement partiel puis final : charge unique, cash seulement aux règlements, restant 300 puis 0.
3. Créance income et encaissements partiel/final : revenu unique, cash +, restant 400 puis 0.
4. Recovery : aucun revenu ; refund d’enveloppe seulement si la source est liée et sans doublon.
5. Allocation : enveloppe + et lien de provenance, sans mouvement bancaire.
6. Transferts compte et enveloppe : respectivement A −/B +, puis enveloppe A −/B + sans mouvement bancaire.
7. Idempotence, rollback, isolation cross-household et immutabilité directe.
8. Après chaque cas : équilibre débit/crédit, soldes comptes/enveloppes, obligations et absence de double comptabilisation.
