import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/money/money.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/remote_account_balances_provider.dart';
import '../../../finance/application/providers/remote_accounts_provider.dart';
import '../../../finance/application/providers/remote_debts_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../../../finance/domain/financial_account.dart';
import '../../../financial_availability/application/providers/financial_availability_provider.dart';
import '../../../financial_availability/domain/financial_availability.dart';
import '../../domain/wealth_models.dart';

class WealthData {
  const WealthData({
    required this.snapshot,
    required this.assets,
    required this.investments,
    required this.financings,
    required this.eventCandidates,
    required this.availability,
  });
  final WealthSnapshot snapshot;
  final List<WealthAsset> assets;
  final List<InvestmentPosition> investments;
  final List<FinancingProfile> financings;
  final List<WealthEventCandidate> eventCandidates;
  final FinancialAvailabilitySnapshot availability;
}

class WealthEventCandidate {
  const WealthEventCandidate({
    required this.id,
    required this.description,
    required this.occurredAt,
  });
  final String id;
  final String description;
  final DateTime occurredAt;
}

abstract interface class WealthGateway {
  Future<List<Map<String, Object?>>> fetchAssets(String householdId);
  Future<List<Map<String, Object?>>> fetchInvestments(String householdId);
  Future<List<Map<String, Object?>>> fetchFinancings(String householdId);
  Future<List<Map<String, Object?>>> fetchEventCandidates(String householdId);
  Future<void> createAsset(
    String householdId,
    String userId,
    Map<String, Object?> values,
  );
  Future<void> addAssetValuation(
    String householdId,
    String userId,
    String assetId,
    Money value,
    DateTime date,
  );
  Future<void> createInvestment(
    String householdId,
    String userId,
    Map<String, Object?> values,
  );
  Future<void> addInvestmentValuation(
    String householdId,
    String userId,
    String investmentId,
    Money value,
    DateTime date,
  );
  Future<void> linkInvestmentOperation(
    String householdId,
    String userId,
    Map<String, Object?> values,
  );
  Future<void> createFinancing(
    String householdId,
    String userId,
    Map<String, Object?> values,
  );
}

class SupabaseWealthGateway implements WealthGateway {
  SupabaseWealthGateway(this.client);
  final SupabaseClient client;

  @override
  Future<List<Map<String, Object?>>> fetchAssets(String householdId) => _rows(
    client
        .from('wealth_asset_current_values')
        .select()
        .eq('household_id', householdId)
        .order('created_at', ascending: true),
  );
  @override
  Future<List<Map<String, Object?>>> fetchInvestments(String householdId) =>
      _rows(
        client
            .from('investment_current_values')
            .select()
            .eq('household_id', householdId)
            .order('created_at', ascending: true),
      );
  @override
  Future<List<Map<String, Object?>>> fetchFinancings(String householdId) =>
      _rows(
        client
            .from('financing_overview')
            .select()
            .eq('household_id', householdId)
            .order('created_at', ascending: true),
      );
  @override
  Future<List<Map<String, Object?>>> fetchEventCandidates(String householdId) =>
      _rows(
        client
            .from('financial_events')
            .select('id,description,occurred_at')
            .eq('household_id', householdId)
            .order('occurred_at', ascending: false)
            .limit(50),
      );

  Future<List<Map<String, Object?>>> _rows(dynamic query) async =>
      List<Map<String, Object?>>.unmodifiable(
        (await query as List<dynamic>).map(
          (row) => Map<String, Object?>.from(row as Map),
        ),
      );

  @override
  Future<void> createAsset(
    String householdId,
    String userId,
    Map<String, Object?> values,
  ) async {
    await client.from('wealth_assets').insert({
      ...values,
      'household_id': householdId,
      'created_by': userId,
      'updated_by': userId,
    });
  }

  @override
  Future<void> addAssetValuation(
    String householdId,
    String userId,
    String assetId,
    Money value,
    DateTime date,
  ) async {
    await client.from('wealth_asset_valuations').insert({
      'household_id': householdId,
      'asset_id': assetId,
      'estimated_value': value.dirhams,
      'valued_on': _date(date),
      'created_by': userId,
    });
  }

  @override
  Future<void> createInvestment(
    String householdId,
    String userId,
    Map<String, Object?> values,
  ) async {
    await client.from('investment_products').insert({
      ...values,
      'household_id': householdId,
      'created_by': userId,
    });
  }

  @override
  Future<void> addInvestmentValuation(
    String householdId,
    String userId,
    String investmentId,
    Money value,
    DateTime date,
  ) async {
    await client.from('investment_valuations').insert({
      'household_id': householdId,
      'investment_id': investmentId,
      'estimated_value': value.dirhams,
      'valued_on': _date(date),
      'created_by': userId,
    });
  }

  @override
  Future<void> linkInvestmentOperation(
    String householdId,
    String userId,
    Map<String, Object?> values,
  ) async {
    await client.from('investment_operations').insert({
      ...values,
      'household_id': householdId,
      'created_by': userId,
    });
  }

  @override
  Future<void> createFinancing(
    String householdId,
    String userId,
    Map<String, Object?> values,
  ) async {
    await client.from('financing_profiles').insert({
      ...values,
      'household_id': householdId,
      'created_by': userId,
    });
  }

  String _date(DateTime value) => value.toIso8601String().split('T').first;
}

final wealthGatewayProvider = Provider<WealthGateway>(
  (ref) => SupabaseWealthGateway(ref.watch(supabaseClientProvider)),
);

final wealthDataProvider = FutureProvider<WealthData>((ref) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif.');
  }
  final results = await Future.wait([
    ref.watch(remoteAccountsProvider.future),
    ref.watch(remoteAccountBalancesProvider.future),
    ref.watch(remoteDebtBalancesProvider.future),
    ref.watch(financialAvailabilityProvider.future),
    ref.watch(wealthGatewayProvider).fetchAssets(householdId),
    ref.watch(wealthGatewayProvider).fetchInvestments(householdId),
    ref.watch(wealthGatewayProvider).fetchFinancings(householdId),
    ref.watch(wealthGatewayProvider).fetchEventCandidates(householdId),
  ]);
  final accounts = results[0] as List<FinancialAccount>;
  final balances = results[1] as Map<String, Money>;
  final debts = results[2] as List<RemoteDebtBalance>;
  final availability = results[3] as FinancialAvailabilitySnapshot;
  final assets = (results[4] as List<Map<String, Object?>>)
      .map(_asset)
      .toList(growable: false);
  final investments = (results[5] as List<Map<String, Object?>>)
      .map(_investment)
      .toList(growable: false);
  final financings = (results[6] as List<Map<String, Object?>>)
      .map(_financing)
      .toList(growable: false);
  final eventCandidates = (results[7] as List<Map<String, Object?>>)
      .map(
        (row) => WealthEventCandidate(
          id: row['id'] as String,
          description: row['description'] as String,
          occurredAt: DateTime.parse(row['occurred_at'] as String),
        ),
      )
      .toList(growable: false);
  final liquidBalances = accounts
      .where(
        (a) =>
            !a.isArchived &&
            (a.type == FinancialAccountType.bank ||
                a.type == FinancialAccountType.cash),
      )
      .map((a) => balances[a.id] ?? const Money.fromMinorUnits(0));
  final syntheticSavings = accounts
      .where((a) => !a.isArchived && a.type == FinancialAccountType.savings)
      .map(
        (a) => InvestmentPosition(
          id: 'account:${a.id}',
          label: a.name,
          currentValue: balances[a.id] ?? const Money.fromMinorUnits(0),
          contributed: const Money.fromMinorUnits(0),
          withdrawn: const Money.fromMinorUnits(0),
          distributions: const Money.fromMinorUnits(0),
          taxes: const Money.fromMinorUnits(0),
        ),
      );
  final allInvestments = [...investments, ...syntheticSavings];
  return WealthData(
    snapshot: calculateWealthSnapshot(
      liquidAccountBalances: liquidBalances,
      assets: assets,
      investments: allInvestments,
      liabilities: debts.map((d) => d.remainingAmount),
    ),
    assets: assets,
    investments: List.unmodifiable(allInvestments),
    financings: List.unmodifiable(financings),
    eventCandidates: List.unmodifiable(eventCandidates),
    availability: availability,
  );
});

final wealthActionsProvider = Provider<WealthActions>(
  (ref) => WealthActions(ref),
);

class WealthActions {
  WealthActions(this.ref);
  final Ref ref;
  Future<(String, String)> _context() async {
    final household = await ref.read(activeHouseholdProvider.future);
    final id = household.householdId;
    final user = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (id == null || user == null) {
      throw StateError('Session ou foyer indisponible.');
    }
    return (id, user);
  }

  Future<void> createAsset(Map<String, Object?> values) async {
    final c = await _context();
    await ref.read(wealthGatewayProvider).createAsset(c.$1, c.$2, values);
    ref.invalidate(wealthDataProvider);
  }

  Future<void> valueAsset(String id, Money value, DateTime date) async {
    final c = await _context();
    await ref
        .read(wealthGatewayProvider)
        .addAssetValuation(c.$1, c.$2, id, value, date);
    ref.invalidate(wealthDataProvider);
  }

  Future<void> createInvestment(Map<String, Object?> values) async {
    final c = await _context();
    await ref.read(wealthGatewayProvider).createInvestment(c.$1, c.$2, values);
    ref.invalidate(wealthDataProvider);
  }

  Future<void> valueInvestment(String id, Money value, DateTime date) async {
    final c = await _context();
    await ref
        .read(wealthGatewayProvider)
        .addInvestmentValuation(c.$1, c.$2, id, value, date);
    ref.invalidate(wealthDataProvider);
  }

  Future<void> linkOperation(Map<String, Object?> values) async {
    final c = await _context();
    await ref
        .read(wealthGatewayProvider)
        .linkInvestmentOperation(c.$1, c.$2, values);
    ref.invalidate(wealthDataProvider);
  }

  Future<void> createFinancing(Map<String, Object?> values) async {
    final c = await _context();
    await ref.read(wealthGatewayProvider).createFinancing(c.$1, c.$2, values);
    ref.invalidate(wealthDataProvider);
  }
}

WealthAsset _asset(Map<String, Object?> row) => WealthAsset(
  id: row['id'] as String,
  label: row['label'] as String,
  type: switch (row['asset_type']) {
    'real_estate' => WealthAssetType.realEstate,
    'vehicle' => WealthAssetType.vehicle,
    _ => WealthAssetType.other,
  },
  ownershipType: switch (row['ownership_type']) {
    'individual' => WealthOwnershipType.individual,
    'shared' => WealthOwnershipType.shared,
    _ => WealthOwnershipType.household,
  },
  currentValue: _money(
    row['current_estimated_value'] ?? row['acquisition_value'],
  ),
  valuationDate: DateTime.tryParse(row['valuation_date']?.toString() ?? ''),
);
InvestmentPosition _investment(Map<String, Object?> row) => InvestmentPosition(
  id: row['id'] as String,
  label: row['label'] as String,
  backingAccountId: row['backing_account_id'] as String?,
  currentValue: _money(row['current_estimated_value']),
  contributed: _money(row['capital_contributed']),
  withdrawn: _money(row['capital_withdrawn']),
  distributions: _money(row['distributions']),
  taxes: _money(row['taxes']),
);
FinancingProfile _financing(Map<String, Object?> row) => FinancingProfile(
  id: row['id'] as String,
  label: row['label'] as String,
  structure: switch (row['structure_type']) {
    'interest_loan' => FinancingStructure.interestLoan,
    'murabaha' => FinancingStructure.murabaha,
    'fixed_cost' => FinancingStructure.fixedCost,
    _ => FinancingStructure.other,
  },
  obligationId: row['obligation_id'] as String,
  assetId: row['asset_id'] as String?,
  principalInitial: _money(row['principal_initial']),
  remainingLiability: _money(row['remaining_amount']),
  startDate: DateTime.parse(row['start_date'] as String),
  durationMonths: row['duration_months'] as int,
  periodicityMonths: row['periodicity_months'] as int,
  annualRate: (row['annual_rate'] as num?)?.toDouble(),
  fixedTotalCost: row['fixed_total_cost'] == null
      ? null
      : _money(row['fixed_total_cost']),
  scheduledPayment: row['scheduled_payment'] == null
      ? null
      : _money(row['scheduled_payment']),
);
Money _money(Object? value) =>
    Money.fromDirhams(num.tryParse(value?.toString() ?? '') ?? 0);
