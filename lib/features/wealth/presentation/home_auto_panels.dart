import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/providers/home_auto_provider.dart';
import '../application/providers/wealth_provider.dart';
import '../domain/home_auto_models.dart';
import '../domain/wealth_models.dart';

class HomePanel extends ConsumerWidget {
  const HomePanel({required this.wealth, super.key});
  final WealthData wealth;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(homeAutoDataProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Logement indisponible : $error')),
        data: (data) {
          final homes = wealth.assets
              .where((a) => a.type == WealthAssetType.realEstate)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const ListTile(
                leading: Icon(Icons.home_work_outlined),
                title: Text('Logement'),
                subtitle: Text(
                  'Actif, financement canonique, aides et avantages — réalisé et projeté restent séparés.',
                ),
              ),
              if (homes.isEmpty)
                const ListTile(
                  title: Text('Aucun actif immobilier'),
                  subtitle: Text(
                    'Ajoutez d’abord un actif immobilier dans Patrimoine.',
                  ),
                ),
              ...homes.map((asset) => _homeCard(context, ref, data, asset)),
            ],
          );
        },
      );

  Widget _homeCard(
    BuildContext context,
    WidgetRef ref,
    HomeAutoData data,
    WealthAsset asset,
  ) {
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
          'Valeur ${_money(asset.currentValue)} · ${financing == null ? 'sans financement lié' : financing.structure.name}',
        ),
        children: [
          ResponsiveGrid(
            minItemWidth: 180,
            children: [
              _metric('Coût brut financement', summary.grossFinancingCost),
              _metric('Avantages constatés', summary.actualBenefits),
              _metric('Coût net constaté', summary.actualNetCost),
              _metric('Coût net projeté', summary.projectedNetCost),
            ],
          ),
          ListTile(
            title: const Text('Dépenses associées'),
            trailing: Text('$expenses'),
            subtitle: const Text(
              'Références analytiques : aucune dépense recréée.',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () =>
                    _addBenefit(context, ref, asset, projected: true),
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Simuler un avantage'),
              ),
              TextButton.icon(
                onPressed: () =>
                    _addBenefit(context, ref, asset, projected: false),
                icon: const Icon(Icons.link),
                label: const Text('Lier un avantage réel'),
              ),
              TextButton.icon(
                onPressed: () => _linkExpense(context, ref, asset),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Rattacher une dépense'),
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
    final amount = await _amount(
      context,
      projected
          ? 'Avantage fiscal/aide projeté'
          : 'Avantage réellement constaté',
    );
    if (amount == null || !context.mounted) return;
    String? eventId;
    if (!projected) {
      eventId = await _event(context, wealth.eventCandidates);
      if (eventId == null) return;
    }
    await ref.read(homeAutoActionsProvider).insert('home_benefits', {
      'asset_id': asset.id,
      'benefit_type': 'tax_saving',
      'recognition': projected ? 'projected' : 'cash_received',
      'amount': amount.dirhams,
      'financial_event_id': eventId,
      'effective_date': DateTime.now().toIso8601String().split('T').first,
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
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(homeAutoDataProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Véhicules indisponibles : $error')),
        data: (data) {
          final vehicles = wealth.assets
              .where((a) => a.type == WealthAssetType.vehicle)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const ListTile(
                leading: Icon(Icons.directions_car_outlined),
                title: Text('Véhicules'),
                subtitle: Text(
                  'Valeur patrimoniale, coûts analytiques, échéances et kilométrage.',
                ),
              ),
              if (vehicles.isEmpty)
                const ListTile(
                  title: Text('Aucun véhicule'),
                  subtitle: Text(
                    'Ajoutez d’abord un actif véhicule dans Patrimoine.',
                  ),
                ),
              ...vehicles.map(
                (asset) => _vehicleCard(context, ref, data, asset),
              ),
            ],
          );
        },
      );

  Widget _vehicleCard(
    BuildContext context,
    WidgetRef ref,
    HomeAutoData data,
    WealthAsset asset,
  ) {
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
          '${_money(asset.currentValue)} · ${mileage == null ? 'kilométrage non suivi' : '${mileage['odometer_km']} km'}',
        ),
        children: [
          ResponsiveGrid(
            minItemWidth: 180,
            children: [
              _metric('Coûts réels liés', summary.actualCosts),
              _metric('TCO disponible', summary.totalCostOfOwnership),
              _metric(
                'Prévisions',
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
                '${p.category.name} · ${p.dueDate.toIso8601String().split('T').first}',
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
                label: const Text('Rattacher un coût réel'),
              ),
              TextButton.icon(
                onPressed: () => _planCost(context, ref, asset),
                icon: const Icon(Icons.event_outlined),
                label: const Text('Prévoir un coût'),
              ),
              TextButton.icon(
                onPressed: () => _mileage(context, ref, asset),
                icon: const Icon(Icons.speed),
                label: const Text('Relever le kilométrage'),
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
    final amount = await _amount(context, 'Coût automobile projeté');
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
    final amount = await _amount(context, 'Kilométrage observé');
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

Future<Money?> _amount(BuildContext context, String title) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Montant'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Continuer'),
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
  if (events.isEmpty) return Future.value(null);
  var selected = events.first.id;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Événement financier existant'),
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
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, selected),
            child: const Text('Rattacher'),
          ),
        ],
      ),
    ),
  );
}
