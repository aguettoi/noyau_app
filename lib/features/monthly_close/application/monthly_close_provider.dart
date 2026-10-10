import 'dart:math';
import '../../../core/money/money.dart';
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
        .select('id,status')
        .eq('household_id', householdId)
        .eq('month_start', month.toIso8601String().substring(0, 10))
        .limit(1);
    final periodId = periods.isEmpty ? null : periods.first['id'].toString();
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final client = ref.read(supabaseClientProvider);
    final membership = userId == null
        ? const []
        : await client
              .from('household_members')
              .select('role')
              .eq('household_id', householdId)
              .eq('user_id', userId)
              .limit(1);
    final eventRows = periodId == null
        ? const []
        : await client
              .from('monthly_close_events')
              .select('event_kind,reason,created_at,created_by')
              .eq('period_id', periodId)
              .order('created_at', ascending: false);
    final actorIds = eventRows
        .map((row) => row['created_by']?.toString())
        .whereType<String>()
        .toSet();
    final profileRows = actorIds.isEmpty
        ? const []
        : await client
              .from('profiles')
              .select('id,display_name')
              .inFilter('id', actorIds.toList());
    final actorNames = {
      for (final row in profileRows)
        row['id'].toString(): (row['display_name'] ?? 'Membre').toString(),
    };
    final status = periods.isEmpty
        ? MonthlyCloseStatus.open
        : MonthlyCloseStatus.values.firstWhere(
            (e) => e.name == periods.first['status'],
            orElse: () => MonthlyCloseStatus.open,
          );
    return MonthlyCloseSnapshot(
      month: month,
      status: status,
      periodId: periodId,
      owner: membership.isNotEmpty && membership.first['role'] == 'owner',
      history: [
        for (final row in eventRows)
          MonthlyCloseAuditEntry(
            kind: row['event_kind'].toString(),
            actor: actorNames[row['created_by']?.toString()] ?? 'Membre',
            at: DateTime.parse(row['created_at'].toString()),
            reason: row['reason']?.toString(),
          ),
      ],
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

  Future<List<MonthlyEnvelopeAccountTarget>> fetchTargets(
    DateTime value,
  ) async {
    final household = await ref.read(activeHouseholdProvider.future);
    final householdId = household.householdId;
    if (householdId == null) throw StateError('Aucun foyer actif.');
    final month = DateTime(value.year, value.month);
    final rows = await ref
        .read(supabaseClientProvider)
        .from('monthly_envelope_account_targets')
        .select('id,envelope_id,account_id,target_amount,created_at')
        .eq('household_id', householdId)
        .eq('month_start', month.toIso8601String().substring(0, 10))
        .order('created_at', ascending: true);
    return List.unmodifiable([
      for (final row in rows)
        MonthlyEnvelopeAccountTarget(
          id: row['id'].toString(),
          envelopeId: row['envelope_id'].toString(),
          accountId: row['account_id'].toString(),
          amount: Money.fromDirhams(
            double.parse(row['target_amount'].toString()),
          ),
          createdAt: DateTime.parse(row['created_at'].toString()),
        ),
    ]);
  }

  Future<void> setTarget({
    required DateTime month,
    required String envelopeId,
    required String accountId,
    required Money amount,
  }) async {
    final household = await ref.read(activeHouseholdProvider.future);
    final householdId = household.householdId;
    if (householdId == null) throw StateError('Aucun foyer actif.');
    await ref
        .read(supabaseClientProvider)
        .rpc(
          'set_monthly_envelope_account_target',
          params: {
            'p_household_id': householdId,
            'p_month_start': DateTime(
              month.year,
              month.month,
            ).toIso8601String().substring(0, 10),
            'p_envelope_id': envelopeId,
            'p_account_id': accountId,
            'p_target_amount': amount.dirhams.toStringAsFixed(2),
            'p_idempotency_key': _uuid(),
          },
        );
  }
}

final monthlyCloseGatewayProvider = Provider((ref) => MonthlyCloseGateway(ref));
final reopenMonthlyCloseProvider =
    Provider<Future<void> Function(String periodId, String reason)>(
      (ref) =>
          (periodId, reason) =>
              ref.read(monthlyCloseGatewayProvider).reopen(periodId, reason),
    );
final setMonthlyCloseTargetProvider =
    Provider<
      Future<void> Function({
        required DateTime month,
        required String envelopeId,
        required String accountId,
        required Money amount,
      })
    >(
      (ref) =>
          ({
            required month,
            required envelopeId,
            required accountId,
            required amount,
          }) => ref
              .read(monthlyCloseGatewayProvider)
              .setTarget(
                month: month,
                envelopeId: envelopeId,
                accountId: accountId,
                amount: amount,
              ),
    );
final monthlyCloseMutationBusyProvider = StateProvider<bool>((ref) => false);
final selectedCloseMonthProvider = StateProvider<DateTime>((ref) {
  final n = DateTime.now();
  return DateTime(n.year, n.month);
});
final monthlyCloseProvider = FutureProvider<MonthlyCloseSnapshot>(
  (ref) => ref
      .watch(monthlyCloseGatewayProvider)
      .fetch(ref.watch(selectedCloseMonthProvider)),
);
final monthlyCloseTargetsProvider =
    FutureProvider<List<MonthlyEnvelopeAccountTarget>>(
      (ref) => ref
          .watch(monthlyCloseGatewayProvider)
          .fetchTargets(ref.watch(selectedCloseMonthProvider)),
    );
