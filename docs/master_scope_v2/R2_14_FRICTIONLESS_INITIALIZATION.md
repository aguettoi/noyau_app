# R2.14 — Initialisation sans friction

Le parcours normal masque la matrice compte × enveloppe. Il exploite les
preuves, confirmations et déductions certaines, puis ne demande que les
localisations encore nécessaires. Une règle structurelle reste une proposition
et n'est jamais transformée en preuve historique.

## Consommateurs

- **Catégorie A — matrice non requise** : transactions quotidiennes, comptes,
  enveloppes, Budget Intelligence, scénarios, obligations, rapprochement,
  patrimoine, dashboard, recherche, export et historique.
- **Catégorie B — état incomplet accepté** : préparation mensuelle, consultation
  de fin de mois et brouillon d'inventaire. Une enveloppe peut rester « à
  déterminer » sans position fictive.
- **Catégorie C — localisation requise au moment de l'action** : réallocation
  physique compte à compte, sweep d'épargne et toute opération analytique qui
  doit déplacer une enveloppe depuis un compte précis. Ces actions conservent
  le contrôle de fiabilité existant et renvoient vers l'information manquante.

Le statut « à déterminer » est household-scoped, partagé et non financier. Il
ne crée ni FinancialEvent, ni écriture GL, ni mouvement d'enveloppe. Le mode
« Ventilation détaillée » reste disponible pour l'audit et les utilisateurs
experts.
