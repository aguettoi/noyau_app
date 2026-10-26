import 'package:flutter/material.dart';

import '../../../core/theme/app_design_system.dart';

class HelpArticle {
  const HelpArticle(this.category, this.title, this.body);
  final String category;
  final String title;
  final String body;
}

const helpArticles = <HelpArticle>[
  HelpArticle(
    'Premiers pas',
    'Créer ou rejoindre un foyer',
    'Créez un foyer après inscription, ou connectez-vous avec l’adresse qui a reçu une invitation.',
  ),
  HelpArticle(
    'Finances',
    'Compte et enveloppe',
    'Un compte indique où se trouve l’argent. Une enveloppe décrit à quoi il est destiné.',
  ),
  HelpArticle(
    'Budget',
    'Scénario et clôture',
    'Le scénario prépare une cible. La clôture compare la situation réelle sans inventer de mouvement.',
  ),
  HelpArticle(
    'Organisation',
    'Rappels et calendrier',
    'Les rappels signalent une action attendue. Ils ne créent jamais une opération financière.',
  ),
  HelpArticle(
    'Confidentialité',
    'Donnée privée et partage',
    'Une donnée privée reste personnelle. Un partage est explicite, limité et révocable.',
  ),
  HelpArticle(
    'Réseau',
    'Travailler sans connexion',
    'Les lectures déjà chargées peuvent rester visibles. Les actions financières attendent toujours une confirmation du serveur.',
  ),
];

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});
  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  var _query = '';
  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final results = helpArticles
        .where(
          (item) =>
              normalized.isEmpty ||
              '${item.category} ${item.title} ${item.body}'
                  .toLowerCase()
                  .contains(normalized),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Aide et mode d’emploi')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          TextField(
            key: const Key('help-search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Rechercher dans l’aide',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (results.isEmpty)
            const Text('Aucun guide ne correspond à cette recherche.'),
          for (final article in results)
            Semantics(
              container: true,
              label: '${article.category}. ${article.title}',
              child: Card(
                child: ExpansionTile(
                  title: Text(article.title),
                  subtitle: Text(article.category),
                  children: [
                    Padding(
                      padding: AppSpacing.dialog,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(article.body),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
