import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/finance_shell_navigation.dart';
import '../../../core/localization/finance_locale.dart';
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
import '../../monthly_close/presentation/monthly_close_page.dart';
import '../../operational_kpis/presentation/operational_kpi_panel.dart';

class FinancialDashboardPage extends ConsumerWidget {
  const FinancialDashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(financialDashboardProvider);
    return SafeArea(
      child: dashboard.when(
        loading: () => FpLoadingState(
          label: FinanceWords.of(context).text('dashboard.loading'),
        ),
        error: (_, _) => FpErrorState(
          message: FinanceWords.of(context).text('dashboard.unavailable'),
        ),
        data: (snapshot) => LayoutBuilder(
          builder: (context, constraints) {
            return ListView(
              key: const Key('financial-dashboard-page'),
              padding: AppLayout.pagePaddingFor(constraints.maxWidth),
              children: [
                FpPageHeader(
                  title: FinanceWords.of(context).text('dashboard.title'),
                  subtitle: FinanceWords.of(context).text('dashboard.subtitle'),
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
                  Padding(
                    key: const Key('dashboard-v2-empty'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SecondaryInfoText(
                      FinanceWords.of(context).text('dashboard.empty'),
                    ),
                  ),
                const SizedBox(height: 12),
                _OrganizationSummary(ref: ref),
                const SizedBox(height: 12),
                Card(
                  key: const Key('dashboard-monthly-close'),
                  child: ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(
                      FinanceWords.of(context).text('dashboard.month_end'),
                    ),
                    subtitle: Text(
                      FinanceWords.of(
                        context,
                      ).text('dashboard.month_end_subtitle'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MonthlyClosePage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DashboardV2Panels(
                  snapshot: snapshot,
                  open: (destination) => _openDestination(context, destination),
                ),
                const SizedBox(height: 12),
                const OperationalKpiPanel(),
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
          FinanceWords.of(context).format('dashboard.organization_summary', {
            'alerts': alerts.where((a) => !a.read).length,
            'tasks': due,
          }),
        ),
        subtitle: Text(
          FinanceWords.of(context).text('dashboard.household_organization'),
        ),
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
