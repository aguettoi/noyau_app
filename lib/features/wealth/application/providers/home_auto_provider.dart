import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/money/money.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../../domain/home_auto_models.dart';

class HomeAutoData {
  const HomeAutoData({
    required this.homeProfiles,
    required this.vehicleProfiles,
    required this.benefits,
    required this.expenses,
    required this.costPlans,
    required this.mileage,
  });
  final List<Map<String, Object?>> homeProfiles;
  final List<Map<String, Object?>> vehicleProfiles;
  final List<HomeBenefit> benefits;
  final List<AssetExpenseLink> expenses;
  final List<VehicleCostPlan> costPlans;
  final List<Map<String, Object?>> mileage;
}

abstract interface class HomeAutoGateway {
  Future<HomeAutoData> fetch(String householdId);
  Future<void> insert(String table, Map<String, Object?> values);
}

class SupabaseHomeAutoGateway implements HomeAutoGateway {
  SupabaseHomeAutoGateway(this.client);
  final SupabaseClient client;

  @override
  Future<HomeAutoData> fetch(String householdId) async {
    Future<List<Map<String, Object?>>> rows(dynamic query) async =>
        (await query as List<dynamic>)
            .map((row) => Map<String, Object?>.from(row as Map))
            .toList(growable: false);
    final values = await Future.wait([
      rows(
        client.from('home_profiles').select().eq('household_id', householdId),
      ),
      rows(
        client
            .from('vehicle_profiles')
            .select()
            .eq('household_id', householdId),
      ),
      rows(
        client
            .from('home_benefits')
            .select()
            .eq('household_id', householdId)
            .order('created_at', ascending: true),
      ),
      rows(
        client
            .from('asset_expense_overview')
            .select()
            .eq('household_id', householdId)
            .order('occurred_at', ascending: false),
      ),
      rows(
        client
            .from('vehicle_cost_plans')
            .select()
            .eq('household_id', householdId)
            .order('due_date', ascending: true),
      ),
      rows(
        client
            .from('vehicle_mileage_readings')
            .select()
            .eq('household_id', householdId)
            .order('reading_date', ascending: false),
      ),
    ]);
    return HomeAutoData(
      homeProfiles: values[0],
      vehicleProfiles: values[1],
      benefits: values[2].map(_benefit).toList(growable: false),
      expenses: values[3].map(_expense).toList(growable: false),
      costPlans: values[4].map(_plan).toList(growable: false),
      mileage: values[5],
    );
  }

  @override
  Future<void> insert(String table, Map<String, Object?> values) async {
    await client.from(table).insert(values);
  }
}

final homeAutoGatewayProvider = Provider<HomeAutoGateway>(
  (ref) => SupabaseHomeAutoGateway(ref.watch(supabaseClientProvider)),
);

final homeAutoDataProvider = FutureProvider<HomeAutoData>((ref) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final id = household.householdId;
  if (id == null) throw StateError('Aucun foyer actif.');
  return ref.watch(homeAutoGatewayProvider).fetch(id);
});

final homeAutoActionsProvider = Provider<HomeAutoActions>(HomeAutoActions.new);

class HomeAutoActions {
  HomeAutoActions(this.ref);
  final Ref ref;

  Future<void> insert(String table, Map<String, Object?> values) async {
    final household = await ref.read(activeHouseholdProvider.future);
    final householdId = household.householdId;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (householdId == null || userId == null) {
      throw StateError('Session ou foyer indisponible.');
    }
    await ref.read(homeAutoGatewayProvider).insert(table, {
      ...values,
      'household_id': householdId,
      'created_by': userId,
    });
    ref.invalidate(homeAutoDataProvider);
  }
}

HomeBenefit _benefit(Map<String, Object?> row) => HomeBenefit(
  id: row['id'] as String,
  assetId: row['asset_id'] as String,
  type: switch (row['benefit_type']) {
    'acquisition_aid' => BenefitType.acquisitionAid,
    'tax_saving' => BenefitType.taxSaving,
    'employer_contribution' => BenefitType.employerContribution,
    _ => BenefitType.other,
  },
  recognition: switch (row['recognition']) {
    'cash_received' => BenefitRecognition.cashReceived,
    'liability_reduction' => BenefitRecognition.liabilityReduction,
    _ => BenefitRecognition.projected,
  },
  amount: _money(row['amount']),
  financialEventId: row['financial_event_id'] as String?,
);

AssetExpenseLink _expense(Map<String, Object?> row) => AssetExpenseLink(
  id: row['id'] as String,
  assetId: row['asset_id'] as String,
  financialEventId: row['financial_event_id'] as String,
  category: row['analytic_category'] as String,
  amount: _money(row['event_amount']),
  occurredAt: DateTime.parse(row['occurred_at'] as String),
);

VehicleCostPlan _plan(Map<String, Object?> row) => VehicleCostPlan(
  id: row['id'] as String,
  assetId: row['asset_id'] as String,
  category: switch (row['category']) {
    'financing' => VehicleCostCategory.financing,
    'insurance' => VehicleCostCategory.insurance,
    'tax' => VehicleCostCategory.tax,
    'maintenance' => VehicleCostCategory.maintenance,
    'oil_change' => VehicleCostCategory.oilChange,
    'repair' => VehicleCostCategory.repair,
    'fuel' => VehicleCostCategory.fuel,
    'toll' => VehicleCostCategory.toll,
    'parking' => VehicleCostCategory.parking,
    _ => VehicleCostCategory.other,
  },
  label: row['label'] as String,
  amount: _money(row['expected_amount']),
  dueDate: DateTime.parse(row['due_date'] as String),
);

Money _money(Object? value) =>
    Money.fromDirhams(num.tryParse(value?.toString() ?? '') ?? 0);
