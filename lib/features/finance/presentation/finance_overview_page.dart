import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/finance_workspace.dart';
import 'transactions_page.dart';
import '../../budget_intelligence/presentation/budget_page.dart';

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
          children: [
            DesktopPageContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fondation financière',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          const Text(
                            'Aucune donnee du foyer n est encore importee.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DesktopSection(
                    title: 'Espaces financiers',
                    subtitle: 'Accédez rapidement aux outils déjà disponibles.',
                    child: ResponsiveGrid(
                      minItemWidth: 300,
                      children: [
                        CompactListRow(
                          leading: const Icon(Icons.upload_file_outlined),
                          title: 'Prévisualisation Excel',
                          subtitle:
                              '${workspace.importEnvelopeNames.length} enveloppes détectées',
                          trailing: const Icon(Icons.chevron_right),
                        ),
                        const CompactListRow(
                          leading: Icon(Icons.account_balance_outlined),
                          title: 'Comptes et espèces',
                          subtitle: 'À créer lors de l’import validé',
                        ),
                        CompactListRow(
                          leading: const Icon(Icons.pie_chart_outline),
                          title: 'Budget',
                          subtitle:
                              'Scénarios, simulation et suivi des enveloppes',
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BudgetPage(),
                            ),
                          ),
                        ),
                        CompactListRow(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: 'Grand livre',
                          subtitle:
                              'Consulter et ajouter les transactions validées',
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const TransactionsPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
