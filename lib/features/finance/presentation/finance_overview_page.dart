import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/finance_shell_navigation.dart';
import '../../../core/localization/finance_residual_locale.dart';
import '../../../core/theme/app_design_system.dart';
import 'transactions_page.dart';
import 'member_compensations_page.dart';
import '../../budget_intelligence/presentation/budget_page.dart';
import '../../wealth/presentation/wealth_page.dart';

class FinanceOverviewPage extends ConsumerWidget {
  const FinanceOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = FinanceResidualWords.of(context);
    return SafeArea(
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
                          words.text('overview.title'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(words.text('overview.subtitle')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DesktopSection(
                  title: words.text('overview.spaces'),
                  subtitle: words.text('overview.spaces_subtitle'),
                  child: ResponsiveGrid(
                    minItemWidth: 300,
                    children: [
                      CompactListRow(
                        leading: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        title: words.text('overview.wealth'),
                        subtitle: words.text('overview.wealth_subtitle'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const WealthPage(),
                          ),
                        ),
                      ),
                      CompactListRow(
                        leading: const Icon(Icons.compare_arrows),
                        title: words.text('overview.compensations'),
                        subtitle: words.text('overview.compensations_subtitle'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MemberCompensationsPage(),
                          ),
                        ),
                      ),
                      CompactListRow(
                        leading: const Icon(Icons.upload_file_outlined),
                        title: words.text('overview.import'),
                        subtitle: words.text('overview.import_subtitle'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => FinanceShellNavigation.of(context)
                            .selectDestination(
                              FinanceShellNavigation.importsIndex,
                            ),
                      ),
                      CompactListRow(
                        leading: const Icon(Icons.account_balance_outlined),
                        title: words.text('overview.accounts'),
                        subtitle: words.text('overview.accounts_subtitle'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => FinanceShellNavigation.of(context)
                            .selectDestination(
                              FinanceShellNavigation.accountsIndex,
                            ),
                      ),
                      CompactListRow(
                        leading: const Icon(Icons.pie_chart_outline),
                        title: words.text('overview.budget'),
                        subtitle: words.text('overview.budget_subtitle'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BudgetPage(),
                          ),
                        ),
                      ),
                      CompactListRow(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: words.text('overview.ledger'),
                        subtitle: words.text('overview.ledger_subtitle'),
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
}
