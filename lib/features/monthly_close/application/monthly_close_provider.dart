import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../domain/monthly_close.dart';

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class MonthlyCloseGateway {
  MonthlyCloseGateway(this.ref);
  final Ref ref;
  Future<MonthlyCloseSnapshot> fetch(DateTime value) async {
    final h = await ref.read(activeHouseholdProvider.future);
    final householdId = h.householdId;
    if (householdId == null) throw StateError('Aucun foyer actif.');
    final month = DateTime(value.year, value.month);
    final raw =
        await ref
                .read(supabaseClientProvider)
                .rpc(
                  'monthly_close_snapshot',
                  params: {
                    'p_household_id': householdId,
                    'p_month_start': month.toIso8601String().substring(0, 10),
                  },
                )
            as Map;
    final periods = await ref
        .read(supabaseClientProvider)
        .from('monthly_close_periods')
        .select('status')
        .eq('household_id', householdId)
        .eq('month_start', month.toIso8601String().substring(0, 10))
        .limit(1);
    final status = periods.isEmpty
        ? MonthlyCloseStatus.open
        : MonthlyCloseStatus.values.firstWhere(
            (e) => e.name == periods.first['status'],
            orElse: () => MonthlyCloseStatus.open,
          );
    return MonthlyCloseSnapshot(
      month: month,
      status: status,
      kpis: ReliabilityKpis(
        totalEntries: (raw['total_entries'] as num).toInt(),
        sameDay: (raw['j0'] as num).toInt(),
        withinOneDay: (raw['j1'] as num).toInt(),
        withinThreeDays: (raw['j3'] as num).toInt(),
        late: (raw['late_entries'] as num).toInt(),
        attribution: raw['attribution'].toString(),
      ),
      issues: [
        CloseIssue(
          code: 'reconciliations',
          label: 'Écarts de rapprochement ouverts',
          count: (raw['open_reconciliations'] as num).toInt(),
          severity: CloseIssueSeverity.blocker,
          destination: 'Comptes',
        ),
        CloseIssue(
          code: 'cash',
          label: 'Inventaires espèces manquants',
          count: (raw['missing_cash_inventories'] as num).toInt(),
          severity: CloseIssueSeverity.blocker,
          destination: 'Comptes',
        ),
        CloseIssue(
          code: 'receipts',
          label: 'Justificatifs manquants',
          count: (raw['missing_receipts'] as num).toInt(),
          severity: CloseIssueSeverity.warning,
          destination: 'Fondation',
        ),
        CloseIssue(
          code: 'compensations',
          label: 'Compensations ouvertes',
          count: (raw['open_compensations'] as num).toInt(),
          severity: CloseIssueSeverity.warning,
          destination: 'Fondation',
        ),
      ],
    );
  }

  Future<void> close(
    DateTime month, {
    required bool overrideWarnings,
    String? reason,
  }) async {
    final h = await ref.read(activeHouseholdProvider.future);
    await ref
        .read(supabaseClientProvider)
        .rpc(
          'close_monthly_period',
          params: {
            'p_household_id': h.householdId,
            'p_month_start': DateTime(
              month.year,
              month.month,
            ).toIso8601String().substring(0, 10),
            'p_override_warnings': overrideWarnings,
            'p_reason': reason,
            'p_idempotency_key': _uuid(),
          },
        );
  }

  Future<void> reopen(String periodId, String reason) => ref
      .read(supabaseClientProvider)
      .rpc(
        'reopen_monthly_period',
        params: {
          'p_period_id': periodId,
          'p_reason': reason,
          'p_idempotency_key': _uuid(),
        },
      );
}

final monthlyCloseGatewayProvider = Provider((ref) => MonthlyCloseGateway(ref));
final selectedCloseMonthProvider = StateProvider<DateTime>((ref) {
  final n = DateTime.now();
  return DateTime(n.year, n.month);
});
final monthlyCloseProvider = FutureProvider<MonthlyCloseSnapshot>(
  (ref) => ref
      .watch(monthlyCloseGatewayProvider)
      .fetch(ref.watch(selectedCloseMonthProvider)),
);
