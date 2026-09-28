import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/money/money.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../dashboard_metrics.dart';

final dashboardPeriodProvider = StateProvider<DashboardPeriod>(
  (ref) => DashboardPeriod.currentMonth,
);
final dashboardClockProvider = Provider<DateTime>((ref) => DateTime.now());
final dashboardThresholdsProvider = Provider<DashboardThresholds>(
  (ref) => const DashboardThresholds(),
);

class DashboardReconciliation {
  const DashboardReconciliation({
    required this.accountId,
    required this.status,
    required this.observedAt,
    required this.remaining,
  });
  final String accountId;
  final String status;
  final DateTime observedAt;
  final Money? remaining;
  bool get isOpen => const [
    'open',
    'partially_resolved',
    'explained_pending',
  ].contains(status);
  factory DashboardReconciliation.fromRow(Map<String, Object?> row) =>
      DashboardReconciliation(
        accountId: row['account_id'] as String,
        status: row['status'] as String,
        observedAt: DateTime.parse(row['observed_at'] as String),
        remaining: row['remaining_difference'] == null
            ? null
            : Money.fromDirhams(
                num.parse(row['remaining_difference'].toString()),
              ),
      );
}

/// This interface exposes SELECT-only operations, deliberately no generic RPC.
abstract interface class DashboardHistoryGateway {
  Future<List<Map<String, Object?>>> transactions(
    String householdId,
    DateTime start,
    DateTime end,
  );
  Future<List<DashboardReconciliation>> reconciliations(String householdId);
}

class SupabaseDashboardHistoryGateway implements DashboardHistoryGateway {
  SupabaseDashboardHistoryGateway(this.client);
  final SupabaseClient client;

  /// Stable pagination prevents silent PostgREST row-limit truncation.
  Future<List<Map<String, Object?>>> _pages(
    Future<List<Map<String, dynamic>>> Function(int, int) query,
  ) async {
    final result = <Map<String, Object?>>[];
    const size = 500;
    for (var offset = 0; ; offset += size) {
      final rows = await query(offset, offset + size - 1);
      result.addAll(rows.map((row) => Map<String, Object?>.from(row)));
      if (rows.length < size) return List.unmodifiable(result);
    }
  }

  @override
  Future<List<Map<String, Object?>>> transactions(
    String householdId,
    DateTime start,
    DateTime end,
  ) => _pages(
    (from, to) async => await client
        .from('financial_transactions')
        .select('id, type, amount, occurred_at')
        .eq('household_id', householdId)
        .isFilter('archived_at', null)
        .gte('occurred_at', start.toUtc().toIso8601String())
        .lt('occurred_at', end.toUtc().toIso8601String())
        .order('occurred_at', ascending: true)
        .order('id', ascending: true)
        .range(from, to),
  );

  @override
  Future<List<DashboardReconciliation>> reconciliations(
    String householdId,
  ) async {
    final rows = await _pages(
      (from, to) async => await client
          .from('account_reconciliation_cases')
          .select(
            'observation_id, account_id, observed_at, status, remaining_difference',
          )
          .eq('household_id', householdId)
          .order('observed_at', ascending: false)
          .order('observation_id', ascending: true)
          .range(from, to),
    );
    return rows.map(DashboardReconciliation.fromRow).toList(growable: false);
  }
}

final dashboardHistoryGatewayProvider = Provider<DashboardHistoryGateway>(
  (ref) => SupabaseDashboardHistoryGateway(ref.watch(supabaseClientProvider)),
);

final dashboardHistoryProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  if (!household.hasActiveHousehold || household.householdId == null) {
    throw StateError('Aucun foyer actif.');
  }
  final now = ref.watch(dashboardClockProvider);
  // One shared read covers every offered period and the six-month chart.
  final start = DateTime(now.year, now.month - 5).isBefore(DateTime(now.year))
      ? DateTime(now.year, now.month - 5)
      : DateTime(now.year);
  return ref
      .watch(dashboardHistoryGatewayProvider)
      .transactions(
        household.householdId!,
        start,
        DateTime(now.year, now.month + 1),
      );
});

final dashboardReconciliationsProvider =
    FutureProvider<List<DashboardReconciliation>>((ref) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      if (!household.hasActiveHousehold || household.householdId == null) {
        throw StateError('Aucun foyer actif.');
      }
      return ref
          .watch(dashboardHistoryGatewayProvider)
          .reconciliations(household.householdId!);
    });
