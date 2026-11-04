import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/localization/wealth_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../../finance/application/providers/remote_debts_provider.dart';
import '../../finance/presentation/transactions_page.dart';
import '../../portability/application/portable_file_saver.dart';
import '../../portability/domain/portability_models.dart';
import '../../reporting/presentation/business_reporting_panel.dart';
import '../application/providers/wealth_provider.dart';
import '../domain/wealth_history.dart';
import '../domain/wealth_models.dart';
import 'financing_comparison_dialog.dart';
import 'home_auto_panels.dart';

class WealthPage extends ConsumerWidget {
  const WealthPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = WealthWords.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(w.text('title'))),
      body: ref
          .watch(wealthDataProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(w.text('load_error'))),
            data: (data) => DefaultTabController(
              length: 6,
              initialIndex: initialTab.clamp(0, 5),
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: w.text('wealth')),
                      Tab(text: w.text('investments')),
                      Tab(text: w.text('financings')),
                      Tab(text: w.text('home')),
                      Tab(text: w.text('vehicles')),
                      Tab(text: w.text('history_dues')),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _WealthOverview(data, ref),
                        _Investments(data, ref),
                        _Financings(data),
                        HomePanel(wealth: data),
                        VehiclePanel(wealth: data),
                        _HistoryReportingHub(data),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateMenu(context, ref),
        icon: const Icon(Icons.add),
        label: Text(w.text('add')),
      ),
    );
  }

  Future<void> _showCreateMenu(BuildContext context, WidgetRef ref) async {
    final w = WealthWords.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(w.text('asset')),
              leading: const Icon(Icons.home_work_outlined),
              onTap: () => Navigator.pop(context, 'asset'),
            ),
            ListTile(
              title: Text(w.text('investment')),
              leading: const Icon(Icons.trending_up),
              onTap: () => Navigator.pop(context, 'investment'),
            ),
            ListTile(
              title: Text(w.text('financing_debt')),
              leading: const Icon(Icons.request_quote_outlined),
              onTap: () => Navigator.pop(context, 'financing'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'asset') {
      await _createAsset(context, ref);
    }
    if (!context.mounted) return;
    if (choice == 'investment') {
      await _createInvestment(context, ref);
    }
    if (!context.mounted) return;
    if (choice == 'financing') {
      await _createFinancing(context, ref);
    }
  }

  Future<void> _createAsset(BuildContext context, WidgetRef ref) async {
    final w = WealthWords.of(context);
    final label = TextEditingController();
    final value = TextEditingController();
    var type = 'other';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(w.text('new_asset')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: InputDecoration(labelText: w.text('label')),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                items: [
                  DropdownMenuItem(
                    value: 'real_estate',
                    child: Text(w.text('real_estate')),
                  ),
                  DropdownMenuItem(
                    value: 'vehicle',
                    child: Text(w.text('vehicle')),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text(w.text('other')),
                  ),
                ],
                onChanged: (v) => setState(() => type = v!),
                decoration: InputDecoration(labelText: w.text('type')),
              ),
              TextField(
                controller: value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: w.text('acquisition_value'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(w.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(w.text('create')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || label.text.trim().isEmpty) return;
    await ref.read(wealthActionsProvider).createAsset({
      'label': label.text.trim(),
      'asset_type': type,
      'ownership_type': 'household',
      'acquisition_value': double.tryParse(value.text.replaceAll(',', '.')),
      'acquisition_date': DateTime.now().toIso8601String().split('T').first,
    });
  }

  Future<void> _createInvestment(BuildContext context, WidgetRef ref) async {
    final w = WealthWords.of(context);
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(w.text('new_investment')),
        content: TextField(
          controller: label,
          decoration: InputDecoration(labelText: w.text('label')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(w.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(w.text('create')),
          ),
        ],
      ),
    );
    if (ok != true || label.text.trim().isEmpty) return;
    await ref.read(wealthActionsProvider).createInvestment({
      'label': label.text.trim(),
      'product_type': 'other',
    });
  }

  Future<void> _createFinancing(BuildContext context, WidgetRef ref) async {
    final w = WealthWords.of(context);
    final debts = await ref.read(remoteDebtBalancesProvider.future);
    if (!context.mounted) return;
    if (debts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(w.text('create_debt_first'))));
      return;
    }
    final label = TextEditingController();
    final principal = TextEditingController();
    final duration = TextEditingController(text: '12');
    var debtId = debts.first.id;
    var structure = 'fixed_cost';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(w.text('new_financing')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: InputDecoration(labelText: w.text('label')),
                ),
                DropdownButtonFormField<String>(
                  initialValue: debtId,
                  items: debts
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.description),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => debtId = v!),
                  decoration: InputDecoration(
                    labelText: w.text('canonical_debt'),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: structure,
                  items: [
                    DropdownMenuItem(
                      value: 'interest_loan',
                      child: Text(w.text('interest_loan')),
                    ),
                    DropdownMenuItem(
                      value: 'murabaha',
                      child: Text(w.text('murabaha')),
                    ),
                    DropdownMenuItem(
                      value: 'fixed_cost',
                      child: Text(w.text('fixed_cost')),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(w.text('other')),
                    ),
                  ],
                  onChanged: (v) => setState(() => structure = v!),
                  decoration: InputDecoration(labelText: w.text('structure')),
                ),
                TextField(
                  controller: principal,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: w.text('principal')),
                ),
                TextField(
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: w.text('duration')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(w.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(w.text('create')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || label.text.trim().isEmpty) return;
    await ref.read(wealthActionsProvider).createFinancing({
      'label': label.text.trim(),
      'structure_type': structure,
      'obligation_id': debtId,
      'principal_initial':
          double.tryParse(principal.text.replaceAll(',', '.')) ??
          debts.first.initialAmount.dirhams,
      'start_date': DateTime.now().toIso8601String().split('T').first,
      'duration_months': int.tryParse(duration.text) ?? 12,
      'periodicity_months': 1,
      'annual_rate': structure == 'interest_loan' ? 0.0 : null,
    });
  }
}

class _HistoryAndDues extends StatelessWidget {
  const _HistoryAndDues(this.data);
  final WealthData data;

  @override
  Widget build(BuildContext context) {
    final w = WealthWords.of(context);
    final now = DateTime.now();
    final annual = compareAnnualWealth(data.history, now.year);
    return ListView(
      key: const Key('wealth-history-and-dues'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          w.text('wealth_evolution'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            title: Text(
              w.format('annual', {
                'previous': now.year - 1,
                'current': now.year,
              }),
            ),
            subtitle: Text(
              annual.change == null
                  ? w.text('annual_unavailable')
                  : w.format('annual_change', {
                      'amount': _money(annual.change!),
                    }),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('export-wealth-history'),
            onPressed: data.history.isEmpty
                ? null
                : () async {
                    final saved = await savePortableFile(
                      PortableFile(
                        'patrimoine_historique.csv',
                        'text/csv;charset=utf-8',
                        encodeWealthHistoryCsv(data.history),
                      ),
                    );
                    if (context.mounted && saved) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(w.text('history_exported'))),
                      );
                    }
                  },
            icon: const Icon(Icons.download_outlined),
            label: Text(w.text('export_history')),
          ),
        ),
        ...data.history.reversed.map(
          (point) => Card(
            child: ListTile(
              title: Text(point.date.toIso8601String().split('T').first),
              subtitle: Text(point.explanations.join('\n')),
              trailing: Text(
                point.netWorth == null
                    ? w.text('partial')
                    : _money(point.netWorth!),
                key: Key('wealth-history-${point.date.toIso8601String()}'),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          w.text('consolidated_dues'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(w.text('dues_explanation')),
        if (data.consolidatedDues.isEmpty)
          ListTile(title: Text(w.text('no_due')))
        else
          ...data.consolidatedDues.map(
            (due) => ListTile(
              leading: Icon(switch (due.kind) {
                ConsolidatedDueKind.obligation => Icons.receipt_long_outlined,
                ConsolidatedDueKind.financing => Icons.account_balance_outlined,
                ConsolidatedDueKind.expected => Icons.event_outlined,
              }),
              title: Text(due.label),
              subtitle: Text(
                w.format('due_detail', {
                  'date': due.date.toIso8601String().split('T').first,
                  'state': due.state.name,
                  'kind': due.kind.name,
                }),
              ),
              trailing: Text(_money(due.amount)),
            ),
          ),
      ],
    );
  }
}

class _HistoryReportingHub extends StatelessWidget {
  const _HistoryReportingHub(this.data);
  final WealthData data;

  @override
  Widget build(BuildContext context) {
    final w = WealthWords.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: w.text('history_view')),
              Tab(text: w.text('report_timeline')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_HistoryAndDues(data), const BusinessReportingPanel()],
            ),
          ),
        ],
      ),
    );
  }
}

class _WealthOverview extends StatelessWidget {
  const _WealthOverview(this.data, this.ref);
  final WealthData data;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
    final w = WealthWords.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          w.text('net_worth'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          _money(data.snapshot.netWorth),
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            _metric(
              w.text('liquidity'),
              data.snapshot.liquidity,
              Icons.account_balance_wallet_outlined,
            ),
            _metric(
              w.text('investments'),
              data.snapshot.investments,
              Icons.trending_up,
            ),
            _metric(
              w.text('tracked_assets'),
              data.snapshot.assets,
              Icons.home_work_outlined,
            ),
            _metric(
              w.text('liabilities'),
              data.snapshot.liabilities,
              Icons.request_quote_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          w.text('valued_assets'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (data.assets.isEmpty)
          ListTile(
            title: Text(w.text('no_asset')),
            subtitle: Text(w.text('ledger_accounts')),
          )
        else
          ...data.assets.map(
            (a) => ListTile(
              title: Text(a.label),
              subtitle: Text(
                w.format('asset_detail', {
                  'type': a.type.name,
                  'date':
                      a.valuationDate?.toIso8601String().split('T').first ??
                      w.text('undated'),
                }),
              ),
              trailing: Text(_money(a.currentValue)),
              onTap: () => _newValuation(context, a),
            ),
          ),
      ],
    );
  }

  Widget _metric(String title, Money value, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        _money(value),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );

  Future<void> _newValuation(BuildContext context, WealthAsset asset) async {
    final value = await _askAmount(
      context,
      WealthWords.of(context).format('new_valuation', {'label': asset.label}),
    );
    if (value == null) return;
    await ref
        .read(wealthActionsProvider)
        .valueAsset(asset.id, value, DateTime.now());
  }
}

class _Investments extends StatelessWidget {
  const _Investments(this.data, this.ref);
  final WealthData data;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
    final w = WealthWords.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(w.text('real_projected')),
            subtitle: Text(w.text('real_projected_detail')),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _simulate(context),
            icon: const Icon(Icons.calculate_outlined),
            label: Text(w.text('simulate_investment')),
          ),
        ),
        if (data.investments.isEmpty)
          ListTile(title: Text(w.text('no_investment')))
        else
          ...data.investments.map(
            (i) => Card(
              child: ExpansionTile(
                title: Text(i.label),
                subtitle: Text(
                  w.format('investment_summary', {
                    'capital': _money(i.netCapital),
                    'gain': _money(i.netGain),
                    'account': i.backingAccountId == null
                        ? ''
                        : w.text('linked_account'),
                  }),
                ),
                trailing: Text(_money(i.currentValue)),
                children: [
                  ListTile(
                    leading: const Icon(Icons.price_change_outlined),
                    title: Text(w.text('add_valuation')),
                    subtitle: Text(w.text('valuation_history')),
                    onTap: () => _value(context, i),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(w.text('link_real')),
                    subtitle: Text(w.text('link_real_detail')),
                    onTap: () => _linkOperation(context, i),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _simulate(BuildContext context) async {
    final w = WealthWords.of(context);
    final result = projectInvestment(
      const InvestmentProjectionInput(
        initialCapital: Money.fromMinorUnits(100000),
        periodicContribution: Money.fromMinorUnits(10000),
        annualRate: .04,
        taxRate: .15,
        months: 12,
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(w.text('illustrative_projection')),
        content: Text(
          w.format('projection_detail', {
            'capital': _money(result.capitalPaid),
            'gain': _money(result.grossGain),
            'tax': _money(result.tax),
            'value': _money(result.projectedValue),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(w.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _value(
    BuildContext context,
    InvestmentPosition investment,
  ) async {
    final value = await _askAmount(
      context,
      WealthWords.of(
        context,
      ).format('current_value', {'label': investment.label}),
    );
    if (value == null) return;
    await ref
        .read(wealthActionsProvider)
        .valueInvestment(investment.id, value, DateTime.now());
  }

  Future<void> _linkOperation(
    BuildContext context,
    InvestmentPosition investment,
  ) async {
    final w = WealthWords.of(context);
    if (data.eventCandidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(w.text('no_event'))));
      return;
    }
    var eventId = data.eventCandidates.first.id;
    var type = 'contribution';
    final amount = TextEditingController();
    final tax = TextEditingController(text: '0');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(w.text('link_event')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: eventId,
                  items: data.eventCandidates
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            e.description,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => eventId = v!),
                  decoration: InputDecoration(
                    labelText: w.text('financial_event'),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: [
                    DropdownMenuItem(
                      value: 'contribution',
                      child: Text(w.text('contribution')),
                    ),
                    DropdownMenuItem(
                      value: 'withdrawal',
                      child: Text(w.text('withdrawal')),
                    ),
                    DropdownMenuItem(
                      value: 'distribution',
                      child: Text(w.text('distribution')),
                    ),
                    DropdownMenuItem(
                      value: 'tax_withholding',
                      child: Text(w.text('withholding')),
                    ),
                  ],
                  onChanged: (v) => setState(() => type = v!),
                  decoration: InputDecoration(labelText: w.text('nature')),
                ),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: w.text('gross_amount'),
                  ),
                ),
                TextField(
                  controller: tax,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: w.text('included_tax'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(w.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(w.text('link')),
            ),
          ],
        ),
      ),
    );
    final gross = double.tryParse(amount.text.replaceAll(',', '.'));
    final withholding = double.tryParse(tax.text.replaceAll(',', '.')) ?? 0;
    if (accepted != true ||
        gross == null ||
        gross <= 0 ||
        withholding < 0 ||
        withholding > gross) {
      return;
    }
    await ref.read(wealthActionsProvider).linkOperation({
      'investment_id': investment.id,
      'operation_type': type,
      'gross_amount': gross,
      'tax_amount': withholding,
      'occurred_on': DateTime.now().toIso8601String().split('T').first,
      'financial_event_id': eventId,
      'idempotency_key': eventId,
    });
  }
}

class _Financings extends StatelessWidget {
  const _Financings(this.data);
  final WealthData data;
  @override
  Widget build(BuildContext context) {
    final w = WealthWords.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(w.text('canonical_capacity')),
            subtitle: Text(
              data.availability.isComplete
                  ? w.format('capacity_complete', {
                      'amount': _money(data.availability.realLiquidity),
                    })
                  : w.format('capacity_partial', {
                      'amount': _money(data.availability.realLiquidity),
                    }),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('open-financing-comparison'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  FinancingComparisonDialog(availability: data.availability),
            ),
            icon: const Icon(Icons.compare_arrows),
            label: Text(w.text('compare')),
          ),
        ),
        if (data.financings.isEmpty)
          ListTile(
            title: Text(w.text('no_financing')),
            subtitle: Text(w.text('financing_detail')),
          )
        else
          ...data.financings.map(
            (f) => Card(
              child: ExpansionTile(
                title: Text(f.label),
                subtitle: Text(
                  w.format('remaining', {
                    'amount': _money(f.remainingLiability),
                    'structure': f.structure.name,
                  }),
                ),
                children: [
                  ...buildFinancingSchedule(f)
                      .take(12)
                      .map(
                        (line) => ListTile(
                          dense: true,
                          title: Text(
                            w.format('installment', {
                              'number': line.number,
                              'date': line.date
                                  .toIso8601String()
                                  .split('T')
                                  .first,
                            }),
                          ),
                          subtitle: Text(
                            w.format('principal_cost', {
                              'principal': _money(line.principal),
                              'cost': _money(line.cost),
                            }),
                          ),
                          trailing: Text(_money(line.payment)),
                        ),
                      ),
                  ListTile(
                    title: Text(w.text('early')),
                    subtitle: Text(w.text('early_detail')),
                    trailing: const Icon(Icons.calculate_outlined),
                    onTap: () => _early(context, f),
                  ),
                  ListTile(
                    title: Text(w.text('real_payment')),
                    subtitle: Text(w.text('real_payment_detail')),
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
          ),
      ],
    );
  }

  Future<void> _early(BuildContext context, FinancingProfile f) async {
    final w = WealthWords.of(context);
    if (f.remainingLiability.minorUnits <= 0) return;
    final amount = Money.fromMinorUnits(
      (f.remainingLiability.minorUnits / 10).round(),
    );
    final duration = projectEarlyRepayment(
      f,
      amount,
      EarlyRepaymentStrategy.reduceDuration,
    );
    final payment = projectEarlyRepayment(
      f,
      amount,
      EarlyRepaymentStrategy.reducePayment,
    );
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(w.text('early_title')),
        content: Text(
          w.format('early_result', {
            'amount': _money(amount),
            'months': duration.remainingMonths,
            'savingDuration': _money(duration.estimatedCostSaving),
            'payment': _money(payment.newPayment),
            'savingPayment': _money(payment.estimatedCostSaving),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(w.text('close')),
          ),
        ],
      ),
    );
  }
}

String _money(Money value) => '${value.dirhams.toStringAsFixed(2)} MAD';

Future<Money?> _askAmount(BuildContext context, String title) async {
  final w = WealthWords.of(context);
  final controller = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: w.text('amount')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(w.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(w.text('save')),
        ),
      ],
    ),
  );
  final value = double.tryParse(controller.text.replaceAll(',', '.'));
  return accepted == true && value != null && value >= 0
      ? Money.fromDirhams(value)
      : null;
}
