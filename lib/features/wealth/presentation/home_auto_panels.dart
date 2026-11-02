import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/localization/home_auto_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/providers/home_auto_provider.dart';
import '../application/providers/wealth_provider.dart';
import '../domain/home_auto_models.dart';
import '../domain/wealth_models.dart';

class HomePanel extends ConsumerWidget {
  const HomePanel({required this.wealth, super.key});
  final WealthData wealth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = HomeAutoWords.of(context);
    return ref
        .watch(homeAutoDataProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(w.text('home_error'))),
          data: (data) {
            final homes = wealth.assets
                .where((a) => a.type == WealthAssetType.realEstate)
                .toList();
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                ListTile(
                  leading: Icon(Icons.home_work_outlined),
                  title: Text(w.text('home')),
                  subtitle: Text(w.text('home_intro')),
                ),
                if (homes.isEmpty)
                  ListTile(
                    title: Text(w.text('no_home')),
                    subtitle: Text(w.text('no_home_detail')),
                  ),
                ...homes.map((asset) => _homeCard(context, ref, data, asset)),
              ],
            );
          },
        );
  }

  Widget _homeCard(
    BuildContext context,
    WidgetRef ref,
    HomeAutoData data,
    WealthAsset asset,
  ) {
    final w = HomeAutoWords.of(context);
    final benefits = data.benefits.where((b) => b.assetId == asset.id);
    final financing = wealth.financings
        .where((f) => f.assetId == asset.id)
        .firstOrNull;
    final grossCost =
        financing?.fixedTotalCost ?? const Money.fromMinorUnits(0);
    final summary = calculateHomeCost(
      grossFinancingCost: grossCost,
      benefits: benefits,
    );
    final expenses = data.expenses.where((e) => e.assetId == asset.id).length;
    return Card(
      child: ExpansionTile(
        title: Text(asset.label),
        subtitle: Text(
          w.format('home_summary', {
            'value': _money(asset.currentValue),
            'financing': financing == null
                ? w.text('no_financing')
                : financing.structure.name,
          }),
        ),
        children: [
          ResponsiveGrid(
            minItemWidth: 180,
            children: [
              _metric(w.text('gross_cost'), summary.grossFinancingCost),
              _metric(w.text('actual_benefits'), summary.actualBenefits),
              _metric(w.text('actual_net'), summary.actualNetCost),
              _metric(w.text('projected_net'), summary.projectedNetCost),
            ],
          ),
          ListTile(
            title: Text(w.text('linked_expenses')),
            trailing: Text(expenses.toString()),
            subtitle: Text(w.text('expense_notice')),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () =>
                    _addBenefit(context, ref, asset, projected: true),
                icon: const Icon(Icons.calculate_outlined),
                label: Text(w.text('simulate_benefit')),
              ),
              TextButton.icon(
                onPressed: () =>
                    _addBenefit(context, ref, asset, projected: false),
                icon: const Icon(Icons.link),
                label: Text(w.text('link_benefit')),
              ),
              TextButton.icon(
                onPressed: () => _linkExpense(context, ref, asset),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(w.text('link_expense')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addBenefit(
    BuildContext context,
    WidgetRef ref,
    WealthAsset asset, {
    required bool projected,
  }) async {
    final input = projected
        ? await _projectedBenefit(context)
        : await _actualBenefit(context);
    if (input == null || !context.mounted) return;
    String? eventId;
    if (!projected) {
      eventId = await _event(context, wealth.eventCandidates);
      if (eventId == null) return;
    }
    await ref.read(homeAutoActionsProvider).insert('home_benefits', {
      'asset_id': asset.id,
      'benefit_type': input.type,
      'recognition': projected ? 'projected' : 'cash_received',
      'amount': input.amount.dirhams,
      'financial_event_id': eventId,
      'effective_date': _date(input.effectiveDate),
      'period_start': input.periodStart == null
          ? null
          : _date(input.periodStart!),
      'period_end': input.periodEnd == null ? null : _date(input.periodEnd!),
      'rate': input.rate,
      'eligible_base': input.eligibleBase?.dirhams,
      'ceiling_amount': input.ceiling?.dirhams,
    });
  }

  Future<void> _linkExpense(
    BuildContext context,
    WidgetRef ref,
    WealthAsset asset,
  ) async {
    final eventId = await _event(context, wealth.eventCandidates);
    if (eventId == null) return;
    await ref.read(homeAutoActionsProvider).insert('asset_expense_links', {
      'asset_id': asset.id,
      'financial_event_id': eventId,
      'analytic_category': 'housing_cost',
    });
  }
}

class VehiclePanel extends ConsumerWidget {
  const VehiclePanel({required this.wealth, super.key});
  final WealthData wealth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = HomeAutoWords.of(context);
    return ref
        .watch(homeAutoDataProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(w.text('vehicle_error'))),
          data: (data) {
            final vehicles = wealth.assets
                .where((a) => a.type == WealthAssetType.vehicle)
                .toList();
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                ListTile(
                  leading: Icon(Icons.directions_car_outlined),
                  title: Text(w.text('vehicles')),
                  subtitle: Text(w.text('vehicle_intro')),
                ),
                if (vehicles.isEmpty)
                  ListTile(
                    title: Text(w.text('no_vehicle')),
                    subtitle: Text(w.text('no_vehicle_detail')),
                  ),
                ...vehicles.map(
                  (asset) => _vehicleCard(context, ref, data, asset),
                ),
              ],
            );
          },
        );
  }

  Widget _vehicleCard(
    BuildContext context,
    WidgetRef ref,
    HomeAutoData data,
    WealthAsset asset,
  ) {
    final w = HomeAutoWords.of(context);
    final actual = data.expenses.where((e) => e.assetId == asset.id).toList();
    final plans = data.costPlans.where((e) => e.assetId == asset.id).toList();
    final summary = calculateVehicleCost(
      acquisition: asset.acquisitionValue,
      currentValue: asset.currentValue,
      actualCosts: actual,
      observedMonths: 1,
    );
    final mileage = data.mileage
        .where((e) => e['asset_id'] == asset.id)
        .firstOrNull;
    return Card(
      child: ExpansionTile(
        title: Text(asset.label),
        subtitle: Text(
          w.format('vehicle_summary', {
            'value': _money(asset.currentValue),
            'mileage': mileage == null
                ? w.text('mileage_unknown')
                : w.format('mileage', {'value': mileage['odometer_km'] ?? '—'}),
          }),
        ),
        children: [
          ResponsiveGrid(
            minItemWidth: 180,
            children: [
              _metric(w.text('actual_costs'), summary.actualCosts),
              _metric(w.text('tco'), summary.totalCostOfOwnership),
              _metric(
                w.text('forecasts'),
                Money.fromMinorUnits(
                  plans.fold(0, (s, p) => s + p.amount.minorUnits),
                ),
              ),
            ],
          ),
          ...plans.map(
            (p) => ListTile(
              dense: true,
              title: Text(p.label),
              subtitle: Text(
                w.format('plan_detail', {
                  'category': w.text('category.${p.category.name}'),
                  'date': p.dueDate.toIso8601String().split('T').first,
                }),
              ),
              trailing: Text(_money(p.amount)),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _linkCost(context, ref, asset),
                icon: const Icon(Icons.receipt_outlined),
                label: Text(w.text('link_actual_cost')),
              ),
              TextButton.icon(
                onPressed: () => _planCost(context, ref, asset),
                icon: const Icon(Icons.event_outlined),
                label: Text(w.text('plan_cost')),
              ),
              TextButton.icon(
                onPressed: () => _mileage(context, ref, asset),
                icon: const Icon(Icons.speed),
                label: Text(w.text('record_mileage')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _linkCost(
    BuildContext context,
    WidgetRef ref,
    WealthAsset asset,
  ) async {
    final eventId = await _event(context, wealth.eventCandidates);
    if (eventId == null) return;
    await ref.read(homeAutoActionsProvider).insert('asset_expense_links', {
      'asset_id': asset.id,
      'financial_event_id': eventId,
      'analytic_category': 'fuel',
    });
  }

  Future<void> _planCost(
    BuildContext context,
    WidgetRef ref,
    WealthAsset asset,
  ) async {
    final amount = await _amount(
      context,
      HomeAutoWords.of(context).text('planned_auto_cost'),
    );
    if (amount == null) return;
    await ref.read(homeAutoActionsProvider).insert('vehicle_cost_plans', {
      'asset_id': asset.id,
      'category': 'other',
      'label': 'Coût prévu',
      'expected_amount': amount.dirhams,
      'due_date': DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String()
          .split('T')
          .first,
    });
  }

  Future<void> _mileage(
    BuildContext context,
    WidgetRef ref,
    WealthAsset asset,
  ) async {
    final amount = await _amount(
      context,
      HomeAutoWords.of(context).text('observed_mileage'),
    );
    if (amount == null) return;
    await ref.read(homeAutoActionsProvider).insert('vehicle_mileage_readings', {
      'asset_id': asset.id,
      'reading_date': DateTime.now().toIso8601String().split('T').first,
      'odometer_km': amount.dirhams.round(),
    });
  }
}

Widget _metric(String label, Money value) => Card(
  child: ListTile(title: Text(label), subtitle: Text(_money(value))),
);
String _money(Money value) => '${value.dirhams.toStringAsFixed(2)} MAD';
String _date(DateTime value) => value.toIso8601String().split('T').first;

class _BenefitInput {
  const _BenefitInput({
    required this.type,
    required this.amount,
    required this.effectiveDate,
    this.periodStart,
    this.periodEnd,
    this.rate,
    this.eligibleBase,
    this.ceiling,
  });

  final String type;
  final Money amount;
  final DateTime effectiveDate;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final double? rate;
  final Money? eligibleBase;
  final Money? ceiling;
}

Future<_BenefitInput?> _actualBenefit(BuildContext context) async {
  final amount = await _amount(
    context,
    HomeAutoWords.of(context).text('actual_benefit'),
  );
  if (amount == null) return null;
  return _BenefitInput(
    type: 'tax_saving',
    amount: amount,
    effectiveDate: DateTime.now(),
  );
}

Future<_BenefitInput?> _projectedBenefit(BuildContext context) async {
  final w = HomeAutoWords.of(context);
  final base = TextEditingController();
  final rate = TextEditingController();
  final ceiling = TextEditingController();
  var type = 'tax_saving';
  final now = DateTime.now();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(w.text('simulate_home_benefit')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                items: [
                  DropdownMenuItem(
                    value: 'acquisition_aid',
                    child: Text(w.text('aid')),
                  ),
                  DropdownMenuItem(
                    value: 'tax_saving',
                    child: Text(w.text('tax_saving')),
                  ),
                  DropdownMenuItem(
                    value: 'employer_contribution',
                    child: Text(w.text('employer')),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text(w.text('other')),
                  ),
                ],
                onChanged: (value) => setState(() => type = value!),
                decoration: InputDecoration(labelText: w.text('type')),
              ),
              TextField(
                controller: base,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: w.text('eligible_base')),
              ),
              TextField(
                controller: rate,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: w.text('rate'),
                  helperText: w.text('rate_help'),
                ),
              ),
              TextField(
                controller: ceiling,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: w.text('optional_ceiling'),
                ),
              ),
              const SizedBox(height: 8),
              Text(w.format('period_notice', {'year': now.year})),
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
            child: Text(w.text('add_projection')),
          ),
        ],
      ),
    ),
  );
  final baseValue = double.tryParse(base.text.replaceAll(',', '.'));
  final percent = double.tryParse(rate.text.replaceAll(',', '.'));
  final ceilingValue = ceiling.text.trim().isEmpty
      ? null
      : double.tryParse(ceiling.text.replaceAll(',', '.'));
  if (accepted != true ||
      baseValue == null ||
      baseValue < 0 ||
      percent == null ||
      percent < 0 ||
      ceilingValue != null && ceilingValue < 0) {
    return null;
  }
  final eligibleBase = Money.fromDirhams(baseValue);
  final ceilingMoney = ceilingValue == null
      ? null
      : Money.fromDirhams(ceilingValue);
  return _BenefitInput(
    type: type,
    amount: calculateProjectedHomeBenefit(
      eligibleBase: eligibleBase,
      rate: percent / 100,
      ceiling: ceilingMoney,
    ),
    effectiveDate: now,
    periodStart: DateTime(now.year),
    periodEnd: DateTime(now.year, 12, 31),
    rate: percent / 100,
    eligibleBase: eligibleBase,
    ceiling: ceilingMoney,
  );
}

Future<Money?> _amount(BuildContext context, String title) async {
  final w = HomeAutoWords.of(context);
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: w.text('amount')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(w.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(w.text('continue')),
        ),
      ],
    ),
  );
  final value = double.tryParse(controller.text.replaceAll(',', '.'));
  return ok == true && value != null && value >= 0
      ? Money.fromDirhams(value)
      : null;
}

Future<String?> _event(
  BuildContext context,
  List<WealthEventCandidate> events,
) {
  final w = HomeAutoWords.of(context);
  if (events.isEmpty) return Future.value(null);
  var selected = events.first.id;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(w.text('existing_event')),
        content: DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          items: events
              .map(
                (e) => DropdownMenuItem(
                  value: e.id,
                  child: Text(e.description, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => selected = v!),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(w.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, selected),
            child: Text(w.text('attach')),
          ),
        ],
      ),
    ),
  );
}
