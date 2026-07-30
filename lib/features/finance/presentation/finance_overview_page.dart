import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/finance_workspace.dart';

class FinanceOverviewPage extends ConsumerWidget {
  const FinanceOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(financeWorkspaceProvider);
    return workspace.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Lecture des donnees source impossible : $error')),
      data: (workspace) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Fondation financiere',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Aucune donnee du foyer n est encore importee.'),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Previsualisation Excel'),
                subtitle: Text(
                  '${workspace.importEnvelopeNames.length} enveloppes detectees',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.account_balance_outlined),
                title: Text('Comptes et especes'),
                subtitle: Text('A creer lors de l import valide'),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.receipt_long_outlined),
                title: Text('Grand livre'),
                subtitle: Text('Aucune ecriture importee'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
