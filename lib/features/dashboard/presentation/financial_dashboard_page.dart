import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/finance_shell_navigation.dart';
import '../../../core/theme/app_design_system.dart';
import '../../budget_intelligence/presentation/budget_monthly_preparation_page.dart';
import '../../envelopes/presentation/envelope_dashboard_page.dart';
import '../../finance/presentation/accounts_page.dart';
import '../../finance/presentation/transactions_page.dart';
import '../../priorities/presentation/priorities_page.dart';
import '../../savings_goals/presentation/savings_goals_page.dart';
import '../application/dashboard_metrics.dart';
import '../application/providers/dashboard_history_provider.dart';
import '../application/providers/remote_financial_dashboard_provider.dart';
import 'dashboard_v2_panels.dart';
import '../../organization/application/organization_provider.dart';
import '../../organization/presentation/organization_page.dart';

class FinancialDashboardPage extends ConsumerWidget {
  const FinancialDashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(financialDashboardProvider);
    return SafeArea(
      child: dashboard.when(
        loading: () => const FpLoadingState(label: 'Chargement du pilotage…'),
        error: (_, _) => const FpErrorState(
          message:
              'Le tableau de bord ne peut pas être chargé. Vérifiez votre connexion.',
        ),
        data: (snapshot) => LayoutBuilder(
          builder: (context, constraints) {
            return ListView(
              key: const Key('financial-dashboard-page'),
              padding: AppLayout.pagePaddingFor(constraints.maxWidth),
              children: [
                const FpPageHeader(
                  title: 'Tableau de bord',
                  subtitle:
                      'Vue Foyer • comptes, enveloppes et projections restent distincts.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final period in DashboardPeriod.values)
                      ChoiceChip(
                        label: Text(period.label),
                        selected: ref.watch(dashboardPeriodProvider) == period,
                        onSelected: (_) =>
                            ref.read(dashboardPeriodProvider.notifier).state =
                                period,
                      ),
                  ],
                ),
                if (snapshot.isEmpty)
                  const Padding(
                    key: Key('dashboard-v2-empty'),
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SecondaryInfoText(
                      'Aucune donnée financière réelle pour ce foyer. Les graphiques apparaîtront après les premières opérations.',
                    ),
                  ),
                const SizedBox(height: 12),
                _OrganizationSummary(ref: ref),
                const SizedBox(height: 12),
                DashboardV2Panels(
                  snapshot: snapshot,
                  open: (destination) => _openDestination(context, destination),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OrganizationSummary extends StatelessWidget {
  const _OrganizationSummary({required this.ref});
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(householdTasksProvider).valueOrNull ?? const [];
    final alerts =
        ref.watch(organizationAlertsProvider).valueOrNull ?? const [];
    final due = tasks
        .where((task) => task.isActive && task.dueDate != null)
        .length;
    return Card(
      key: const Key('dashboard-organization-summary'),
      child: ListTile(
        leading: const Icon(Icons.event_note_outlined),
        title: Text(
          '${alerts.where((a) => !a.read).length} alerte(s) • $due tâche(s) à échéance',
        ),
        subtitle: const Text('Organisation, calendrier et alertes du foyer'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const OrganizationPage()),
          );
        },
      ),
    );
  }
}

void _openDestination(BuildContext context, DashboardDestination destination) {
  final (index, page) = switch (destination) {
    DashboardDestination.accounts => (
      FinanceShellNavigation.accountsIndex,
      const AccountsPage(),
    ),
    DashboardDestination.envelopes => (
      FinanceShellNavigation.envelopesIndex,
      const EnvelopeDashboardPage(),
    ),
    DashboardDestination.goals => (
      FinanceShellNavigation.savingsGoalsIndex,
      const SavingsGoalsPage(),
    ),
    DashboardDestination.priorities => (
      FinanceShellNavigation.prioritiesIndex,
      const PrioritiesPage(),
    ),
    DashboardDestination.budget => (null, const BudgetMonthlyPreparationPage()),
    DashboardDestination.debts => (null, const DebtsPage()),
    DashboardDestination.receivables => (null, const ReceivablesPage()),
  };
  final navigation = FinanceShellNavigation.maybeOf(context);
  if (index != null && navigation != null) {
    navigation.selectDestination(index);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
