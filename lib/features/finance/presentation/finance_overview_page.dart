import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/finance_shell_navigation.dart';
import '../../../core/theme/app_design_system.dart';
import 'transactions_page.dart';
import '../../budget_intelligence/presentation/budget_page.dart';

class FinanceOverviewPage extends ConsumerWidget {
  const FinanceOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
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
                        'Accédez aux fonctions structurantes de votre foyer financier.',
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
                      title: 'Import & migration',
                      subtitle: 'Préparer ou contrôler l’import de vos données',
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => FinanceShellNavigation.of(
                        context,
                      ).selectDestination(FinanceShellNavigation.importsIndex),
                    ),
                    CompactListRow(
                      leading: const Icon(Icons.account_balance_outlined),
                      title: 'Comptes & rapprochements',
                      subtitle: 'Soldes, espèces et rapprochements',
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => FinanceShellNavigation.of(
                        context,
                      ).selectDestination(FinanceShellNavigation.accountsIndex),
                    ),
                    CompactListRow(
                      leading: const Icon(Icons.pie_chart_outline),
                      title: 'Budget',
                      subtitle: 'Scénarios, préparation du mois et suivi',
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BudgetPage(),
                        ),
                      ),
                    ),
                    CompactListRow(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: 'Grand Livre',
                      subtitle: 'Transactions, dettes, créances et historique',
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
  );
}
