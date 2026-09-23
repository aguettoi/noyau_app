import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../budget_intelligence/presentation/budget_monthly_preparation_page.dart';
import '../../envelopes/presentation/envelope_dashboard_page.dart';
import '../../finance/presentation/accounts_page.dart';
import '../../finance/presentation/transactions_page.dart';
import '../../priorities/presentation/priorities_page.dart';
import '../../savings_goals/presentation/savings_goals_page.dart';
import '../application/dashboard_metrics.dart';
import '../application/providers/remote_financial_dashboard_provider.dart';

/// Home screen for the household: a composition of read-only canonical ledgers.
class FinancialDashboardPage extends ConsumerWidget {
  const FinancialDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(financialDashboardProvider);
    return SafeArea(
      child: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text('Impossible de lire le tableau de bord : $error'),
          ),
        ),
        data: (snapshot) => _DashboardContent(snapshot: snapshot),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.snapshot});

  final FinancialDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DesktopPageContainer(
    child: ListView(
      key: const Key('financial-dashboard-page'),
      children: [
        Text(
          'Tableau de bord',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xxs),
        const Text(
          'Vue de pilotage : les comptes, enveloppes et projections restent distincts.',
        ),
        const SizedBox(height: AppSpacing.lg),
        _TreasurySection(snapshot: snapshot),
        const SizedBox(height: AppSpacing.md),
        _MonthlySection(snapshot: snapshot),
        const SizedBox(height: AppSpacing.md),
        ResponsiveGrid(
          minItemWidth: 410,
          children: [
            _EnvelopesSection(snapshot: snapshot),
            _CommitmentsSection(snapshot: snapshot),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ResponsiveGrid(
          minItemWidth: 410,
          children: [
            _GoalsAndPrioritiesSection(snapshot: snapshot),
            _AlertsSection(snapshot: snapshot),
          ],
        ),
      ],
    ),
  );
}

class _TreasurySection extends StatelessWidget {
  const _TreasurySection({required this.snapshot});
  final FinancialDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DesktopSection(
    title: 'Trésorerie réelle',
    subtitle: 'Solde théorique issu du Grand Livre des comptes uniquement.',
    action: TextButton.icon(
      key: const Key('dashboard-open-accounts'),
      onPressed: () => _open(context, const AccountsPage()),
      icon: const Icon(Icons.arrow_forward_outlined),
      label: const Text('Comptes'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            _MetricCard(
              key: const Key('dashboard-treasury-total'),
              label: 'Trésorerie totale',
              value: _money(snapshot.cashTotal),
              icon: Icons.account_balance_outlined,
            ),
            _MetricCard(
              key: const Key('dashboard-cash-on-hand'),
              label: 'Espèces',
              value: _money(snapshot.cashOnHand),
              icon: Icons.payments_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (snapshot.accounts.isEmpty)
          const _EmptyMessage('Aucun compte actif pour le moment.')
        else
          ...snapshot.accounts.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: CompactListRow(
                title: item.account.name,
                subtitle: item.reconciliationDifference == null
                    ? 'Aucun rapprochement récent.'
                    : 'Écart de rapprochement : ${_money(item.reconciliationDifference!)}',
                leading: Icon(
                  item.account.type.name == 'cash'
                      ? Icons.payments_outlined
                      : Icons.account_balance_outlined,
                ),
                trailing: Text(_money(item.balance)),
              ),
            ),
          ),
      ],
    ),
  );
}

class _MonthlySection extends StatelessWidget {
  const _MonthlySection({required this.snapshot});
  final FinancialDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DesktopSection(
    title: 'Mois en cours',
    subtitle:
        'Le budget mensuel est un plan ; il ne s’ajoute jamais à la trésorerie.',
    action: TextButton.icon(
      key: const Key('dashboard-open-month-preparation'),
      onPressed: () => _open(context, const BudgetMonthlyPreparationPage()),
      icon: const Icon(Icons.calendar_month_outlined),
      label: const Text('Préparer le mois'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            _MetricCard(
              label: 'Revenus reconnus',
              value: _money(snapshot.monthlyFlow.income),
              icon: Icons.south_west_outlined,
            ),
            _MetricCard(
              label: 'Dépenses reconnues',
              value: _money(snapshot.monthlyFlow.expense),
              icon: Icons.north_east_outlined,
            ),
            _MetricCard(
              label: 'Reste à vivre',
              value: _money(snapshot.monthlyFlow.remainder),
              icon: Icons.today_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!snapshot.budget.hasPreparedBudget)
          const _EmptyMessage(
            'Aucun budget préparé pour ce mois. Préparez le mois sans confondre ce plan avec l’argent disponible.',
            key: Key('dashboard-budget-empty'),
          )
        else
          ResponsiveGrid(
            minItemWidth: 200,
            children: [
              _MetricCard(
                label: 'Budget prévu',
                value: _money(snapshot.budget.planned),
              ),
              _MetricCard(
                label: 'Consommé',
                value: _money(snapshot.budget.consumed),
              ),
              _MetricCard(
                label: 'Budget restant',
                value: _money(snapshot.budget.remaining),
              ),
              _MetricCard(
                label: 'Consommation',
                value:
                    '${((snapshot.budget.consumptionRate ?? 0) * 100).toStringAsFixed(0)} %',
              ),
            ],
          ),
      ],
    ),
  );
}

class _EnvelopesSection extends StatelessWidget {
  const _EnvelopesSection({required this.snapshot});
  final FinancialDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DesktopSection(
    title: 'Enveloppes',
    subtitle: 'Affectation de l’argent, distincte des soldes de comptes.',
    action: TextButton.icon(
      key: const Key('dashboard-open-envelopes'),
      onPressed: () => _open(context, const EnvelopeDashboardPage()),
      icon: const Icon(Icons.arrow_forward_outlined),
      label: const Text('Enveloppes'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricCard(
          label: 'Total des enveloppes',
          value: _money(snapshot.ordinaryEnvelopeTotal),
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: AppSpacing.sm),
        _MetricCard(
          key: const Key('dashboard-to-allocate'),
          label: 'À répartir',
          value: _money(
            snapshot.toAllocate?.balance ?? const Money.fromMinorUnits(0),
          ),
          icon: Icons.call_split_outlined,
          highlight: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (snapshot.ordinaryEnvelopes.isEmpty)
          const _EmptyMessage('Aucune enveloppe ordinaire active.')
        else
          ...snapshot.ordinaryEnvelopes
              .take(4)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: CompactListRow(
                    title: item.name,
                    subtitle: item.balance.minorUnits < 0
                        ? 'Solde négatif à suivre'
                        : null,
                    trailing: Text(_money(item.balance)),
                  ),
                ),
              ),
      ],
    ),
  );
}

class _CommitmentsSection extends StatelessWidget {
  const _CommitmentsSection({required this.snapshot});
  final FinancialDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DesktopSection(
    title: 'Engagements',
    subtitle:
        'Obligations ouvertes : elles ne sont pas additionnées à la trésorerie.',
    action: TextButton.icon(
      key: const Key('dashboard-open-obligations'),
      onPressed: () => _open(context, const DebtsPage()),
      icon: const Icon(Icons.arrow_forward_outlined),
      label: const Text('Dettes'),
    ),
    child: ResponsiveGrid(
      minItemWidth: 190,
      children: [
        _MetricCard(
          label: 'Dettes à payer',
          value: _money(snapshot.debtRemaining),
        ),
        _MetricCard(
          label: 'Créances Income',
          value: _money(snapshot.incomeReceivableRemaining),
        ),
        _MetricCard(
          label: 'Recovery à recevoir',
          value: _money(snapshot.recoveryRemaining),
        ),
      ],
    ),
  );
}

class _GoalsAndPrioritiesSection extends StatelessWidget {
  const _GoalsAndPrioritiesSection({required this.snapshot});
  final FinancialDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DesktopSection(
    title: 'Objectifs & priorités',
    subtitle:
        'Les objectifs lisent leurs enveloppes ; les priorités restent une projection.',
    action: Wrap(
      spacing: AppSpacing.xs,
      children: [
        TextButton(
          key: const Key('dashboard-open-goals'),
          onPressed: () => _open(context, const SavingsGoalsPage()),
          child: const Text('Objectifs'),
        ),
        TextButton(
          key: const Key('dashboard-open-priorities'),
          onPressed: () => _open(context, const PrioritiesPage()),
          child: const Text('Priorités'),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (snapshot.activeGoals.isEmpty)
          const _EmptyMessage('Aucun objectif actif pour le moment.')
        else
          ...snapshot.activeGoals
              .take(3)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: CompactListRow(
                    title: item.goal.name,
                    subtitle:
                        '${_money(item.accumulated)} sur ${_money(item.goal.targetAmount)} • reste ${_money(item.remaining)}',
                    trailing: Text(
                      '${(item.progressForIndicator * 100).toStringAsFixed(0)} %',
                    ),
                  ),
                ),
              ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Prochaine priorité',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        if (snapshot.nextPriority == null)
          const _EmptyMessage('Aucune priorité active planifiée.')
        else
          Text(
            '${snapshot.nextPriority!.item.rank}. ${snapshot.nextPriority!.source.label}',
          ),
      ],
    ),
  );
}

class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.snapshot});
  final FinancialDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DesktopSection(
    title: 'Points d’attention',
    subtitle: 'Signaux de suivi uniquement : aucune correction automatique.',
    child: snapshot.alerts.isEmpty
        ? const _EmptyMessage('Aucun point d’attention détecté.')
        : Column(
            children: [
              for (final alert in snapshot.alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: CompactListRow(
                    title: alert.title,
                    subtitle: alert.detail,
                    leading: Icon(
                      alert.severity == DashboardAlertSeverity.warning
                          ? Icons.warning_amber_outlined
                          : Icons.info_outline,
                      color: alert.severity == DashboardAlertSeverity.warning
                          ? AppColors.warning
                          : AppColors.info,
                    ),
                  ),
                ),
            ],
          ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Card(
    color: highlight ? AppColors.accentContainer : null,
    child: Padding(
      padding: AppSpacing.card,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: highlight
                  ? AppColors.accentContainerText
                  : AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) =>
      Text(message, style: Theme.of(context).textTheme.bodyMedium);
}

String _money(Money amount) =>
    '${amount.dirhams.toStringAsFixed(2).replaceAll('.', ',')} MAD';

void _open(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
