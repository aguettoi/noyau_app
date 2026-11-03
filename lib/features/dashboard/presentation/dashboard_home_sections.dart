import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../organization/domain/organization_models.dart';
import '../../savings_goals/domain/savings_goal.dart';
import '../application/providers/dashboard_home_provider.dart';
import '../application/providers/remote_financial_dashboard_provider.dart';
import 'dashboard_home_locale.dart';

class DashboardHomeHeader extends StatelessWidget {
  const DashboardHomeHeader({super.key, this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final words = DashboardHomeWords.of(context);
    return FpPageHeader(
      title: name == null
          ? words.text('hello')
          : words.format('hello.name', {'name': name!}),
      subtitle: words.text('intro'),
    );
  }
}

class DashboardSituationCard extends StatelessWidget {
  const DashboardSituationCard({
    super.key,
    required this.home,
    required this.onOpen,
  });
  final DashboardHomeModel home;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final words = DashboardHomeWords.of(context);
    final budget = home.snapshot.budget;
    final end =
        budget.period?.endsOn ?? DateTime(home.now.year, home.now.month + 1, 0);
    final days = DateTime(end.year, end.month, end.day)
        .difference(DateTime(home.now.year, home.now.month, home.now.day))
        .inDays
        .clamp(0, 366);
    final rate = (budget.consumptionRate ?? 0).clamp(0, 1.0).toDouble();
    return _HomeCard(
      key: const Key('dashboard-situation'),
      title: words.text('month'),
      icon: Icons.account_balance_wallet_outlined,
      child: budget.hasPreparedBudget
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  words.text('available'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _money(context, budget.remaining),
                  key: const Key('dashboard-budget-available'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  label: words.format('used', {'value': (rate * 100).round()}),
                  child: LinearProgressIndicator(value: rate),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        words.format('used', {'value': (rate * 100).round()}),
                      ),
                    ),
                    Text(words.format('days', {'count': days})),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: onOpen,
                  child: Text(words.text('month.detail')),
                ),
              ],
            )
          : Column(
              key: const Key('dashboard-budget-empty'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(words.text('budget.empty')),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: onOpen,
                  child: Text(words.text('budget.setup')),
                ),
              ],
            ),
    );
  }
}

class DashboardActionCenter extends StatelessWidget {
  const DashboardActionCenter({
    super.key,
    required this.actions,
    required this.onOpen,
  });
  final List<AppAlert> actions;
  final ValueChanged<AppAlert> onOpen;

  @override
  Widget build(BuildContext context) {
    final words = DashboardHomeWords.of(context);
    return _HomeCard(
      key: const Key('dashboard-action-center'),
      title: words.text('attention'),
      icon: Icons.notifications_active_outlined,
      badge: actions.isEmpty ? null : '${actions.length}',
      child: actions.isEmpty
          ? _PositiveEmpty(
              icon: Icons.check_circle_outline,
              text: words.text('attention.empty'),
            )
          : Column(
              children: [
                for (final action in actions.take(4))
                  ListTile(
                    key: Key('dashboard-action-${action.key}'),
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: AppSpacing.xs,
                    leading: Icon(
                      _alertIcon(action.priority),
                      color: _alertColor(action.priority),
                    ),
                    title: Text(
                      action.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      action.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpen(action),
                  ),
              ],
            ),
    );
  }
}

class DashboardTodayCard extends StatelessWidget {
  const DashboardTodayCard({
    super.key,
    required this.entries,
    required this.onOpen,
    required this.onOpenAll,
  });
  final List<CalendarEntry> entries;
  final ValueChanged<CalendarEntry> onOpen;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final words = DashboardHomeWords.of(context);
    return _HomeCard(
      key: const Key('dashboard-today'),
      title: words.text('today'),
      icon: Icons.today_outlined,
      child: entries.isEmpty
          ? _PositiveEmpty(
              icon: Icons.event_available_outlined,
              text: words.text('today.empty'),
            )
          : Column(
              children: [
                for (final entry in entries.take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_calendarIcon(entry.source)),
                    title: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: entry.detail == null
                        ? null
                        : Text(
                            entry.detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpen(entry),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: onOpenAll,
                    child: Text(words.text('calendar')),
                  ),
                ),
              ],
            ),
    );
  }
}

class DashboardGoalsCard extends StatelessWidget {
  const DashboardGoalsCard({
    super.key,
    required this.goals,
    required this.onOpen,
  });
  final List<SavingsGoalProgress> goals;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final words = DashboardHomeWords.of(context);
    return _HomeCard(
      key: const Key('dashboard-goals'),
      title: words.text('goals'),
      icon: Icons.flag_outlined,
      child: goals.isEmpty
          ? _PositiveEmpty(
              icon: Icons.flag_outlined,
              text: words.text('goals.empty'),
            )
          : Column(
              children: [
                for (final goal in goals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                goal.goal.name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            Text(
                              '${(goal.progressForIndicator * 100).round()} %',
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        LinearProgressIndicator(
                          value: goal.progressForIndicator,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${_money(context, goal.accumulated)} / ${_money(context, goal.goal.targetAmount)}',
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: onOpen,
                    child: Text(words.text('goals.all')),
                  ),
                ),
              ],
            ),
    );
  }
}

class DashboardSecondaryOverview extends StatelessWidget {
  const DashboardSecondaryOverview({
    super.key,
    required this.snapshot,
    required this.onCloseMonth,
    required this.onAnalytics,
  });
  final FinancialDashboardSnapshot snapshot;
  final VoidCallback onCloseMonth;
  final VoidCallback onAnalytics;

  @override
  Widget build(BuildContext context) {
    final words = DashboardHomeWords.of(context);
    return Card(
      key: const Key('dashboard-secondary-overview'),
      child: Padding(
        padding: AppSpacing.card,
        child: Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              words.text('secondary'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _Metric(
              label: words.text('income'),
              value: _money(context, snapshot.monthlyFlow.income),
              color: AppColors.income,
            ),
            _Metric(
              label: words.text('expenses'),
              value: _money(context, snapshot.monthlyFlow.expense),
              color: AppColors.expense,
            ),
            OutlinedButton.icon(
              onPressed: onCloseMonth,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(words.text('month.end')),
            ),
            FilledButton.tonalIcon(
              onPressed: onAnalytics,
              icon: const Icon(Icons.insights_outlined),
              label: Text(words.text('analytics')),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardNewHouseholdState extends StatelessWidget {
  const DashboardNewHouseholdState({
    super.key,
    required this.onOperation,
    required this.onBudget,
  });
  final VoidCallback onOperation;
  final VoidCallback onBudget;
  @override
  Widget build(BuildContext context) {
    final words = DashboardHomeWords.of(context);
    return FpEmptyState(
      key: const Key('dashboard-v2-empty'),
      icon: Icons.home_outlined,
      title: words.text('empty.title'),
      message: words.text('empty.body'),
      action: Wrap(
        spacing: AppSpacing.sm,
        children: [
          FilledButton(
            onPressed: onOperation,
            child: Text(words.text('empty.operation')),
          ),
          OutlinedButton(
            onPressed: onBudget,
            child: Text(words.text('budget.setup')),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.badge,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final String? badge;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (badge != null) Badge(label: Text(badge!)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, $value',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text('$label  ', style: Theme.of(context).textTheme.labelMedium),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}

class _PositiveEmpty extends StatelessWidget {
  const _PositiveEmpty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Icon(icon, color: AppColors.success),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

String _money(BuildContext context, Money value) => NumberFormat.currency(
  locale: Localizations.localeOf(context).toLanguageTag(),
  symbol: 'MAD',
  decimalDigits: value.minorUnits % 100 == 0 ? 0 : 2,
).format(value.dirhams);

IconData _alertIcon(HouseholdTaskPriority priority) => switch (priority) {
  HouseholdTaskPriority.urgent => Icons.error_outline,
  HouseholdTaskPriority.high => Icons.warning_amber_rounded,
  HouseholdTaskPriority.normal => Icons.info_outline,
  HouseholdTaskPriority.low => Icons.info_outline,
};

Color _alertColor(HouseholdTaskPriority priority) => switch (priority) {
  HouseholdTaskPriority.urgent => AppColors.danger,
  HouseholdTaskPriority.high => AppColors.warning,
  HouseholdTaskPriority.normal => AppColors.info,
  HouseholdTaskPriority.low => AppColors.textSecondary,
};

IconData _calendarIcon(CalendarSource source) => switch (source) {
  CalendarSource.task => Icons.task_alt,
  CalendarSource.shopping => Icons.shopping_cart_outlined,
  CalendarSource.homeAuto => Icons.home_repair_service_outlined,
  CalendarSource.obligation => Icons.event_busy_outlined,
  _ => Icons.event_outlined,
};
