import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/finance_shell_navigation.dart';
import '../../../core/theme/app_design_system.dart';
import '../../budget_intelligence/presentation/budget_monthly_preparation_page.dart';
import '../../envelopes/presentation/envelope_dashboard_page.dart';
import '../../finance/presentation/accounts_page.dart';
import '../../finance/presentation/transactions_page.dart';
import '../../organization/domain/organization_models.dart';
import '../../organization/presentation/calendar_source_navigator.dart';
import '../../organization/presentation/organization_page.dart';
import '../../priorities/presentation/priorities_page.dart';
import '../../savings_goals/presentation/savings_goals_page.dart';
import '../application/dashboard_metrics.dart';
import '../application/providers/dashboard_home_provider.dart';
import 'dashboard_analytics_page.dart';
import 'dashboard_home_locale.dart';
import 'dashboard_home_sections.dart';

class FinancialDashboardPage extends ConsumerWidget {
  const FinancialDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = DashboardHomeWords.of(context);
    return SafeArea(
      child: ref
          .watch(dashboardHomeProvider)
          .when(
            loading: () => FpLoadingState(label: words.text('loading')),
            error: (_, _) => FpErrorState(message: words.text('error')),
            data: (home) => LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < AppLayout.mediumBreakpoint;
                final empty =
                    home.snapshot.isEmpty &&
                    !home.snapshot.budget.hasPreparedBudget &&
                    home.goals.isEmpty;
                final situation = DashboardSituationCard(
                  home: home,
                  onOpen: () =>
                      _openDestination(context, DashboardDestination.budget),
                );
                final actions = DashboardActionCenter(
                  actions: home.actions,
                  onOpen: (alert) => _openAlert(context, alert),
                );
                final today = DashboardTodayCard(
                  entries: home.today,
                  onOpen: (entry) => _openCalendarEntry(context, entry),
                  onOpenAll: () => _push(context, const OrganizationPage()),
                );
                final goals = DashboardGoalsCard(
                  goals: home.goals,
                  onOpen: () =>
                      _openDestination(context, DashboardDestination.goals),
                );
                return ListView(
                  key: const Key('financial-dashboard-page'),
                  padding: AppLayout.pagePaddingFor(constraints.maxWidth),
                  children: [
                    DashboardHomeHeader(name: home.memberName),
                    if (home.partial) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Material(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: AppRadius.card,
                        child: Padding(
                          padding: AppSpacing.card,
                          child: Text(words.text('partial')),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    if (empty)
                      DashboardNewHouseholdState(
                        onOperation: () =>
                            _push(context, const TransactionsPage()),
                        onBudget: () => _openDestination(
                          context,
                          DashboardDestination.budget,
                        ),
                      )
                    else if (compact) ...[
                      situation,
                      const SizedBox(height: AppSpacing.sm),
                      actions,
                      const SizedBox(height: AppSpacing.sm),
                      today,
                      const SizedBox(height: AppSpacing.sm),
                      goals,
                    ] else ...[
                      _DashboardRow(first: situation, second: actions),
                      const SizedBox(height: AppSpacing.md),
                      _DashboardRow(first: today, second: goals),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    DashboardSecondaryOverview(
                      snapshot: home.snapshot,
                      onCloseMonth: () => _openDestination(
                        context,
                        DashboardDestination.budget,
                      ),
                      onAnalytics: () async {
                        final destination = await Navigator.of(context)
                            .push<DashboardDestination>(
                              MaterialPageRoute(
                                builder: (_) => DashboardAnalyticsPage(
                                  snapshot: home.snapshot,
                                ),
                              ),
                            );
                        if (context.mounted && destination != null) {
                          _openDestination(context, destination);
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          ),
    );
  }
}

class _DashboardRow extends StatelessWidget {
  const _DashboardRow({required this.first, required this.second});
  final Widget first;
  final Widget second;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: first),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: second),
    ],
  );
}

void _openAlert(BuildContext context, AppAlert alert) {
  if (alert.key.startsWith('financial:')) {
    final parts = alert.key.split(':');
    final raw = parts.length > 1 ? parts[1] : null;
    final destination = DashboardDestination.values
        .where((item) => item.name == raw)
        .firstOrNull;
    if (destination != null) {
      _openDestination(context, destination);
      return;
    }
  }
  if (alert.source != null) {
    final page = const CalendarSourceNavigator().resolve(
      alert.source!,
      alert.sourceId,
    );
    if (page != null) {
      _push(context, page);
      return;
    }
  }
  _push(context, const OrganizationPage());
}

void _openCalendarEntry(BuildContext context, CalendarEntry entry) {
  final page = const CalendarSourceNavigator().resolve(
    entry.source,
    entry.sourceId,
  );
  _push(context, page ?? const OrganizationPage());
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
  } else {
    _push(context, page);
  }
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
