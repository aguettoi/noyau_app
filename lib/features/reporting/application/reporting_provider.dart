import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/remote_transactions_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../finance/domain/transaction_history_item.dart';
import '../../monthly_close/application/monthly_close_provider.dart';
import '../../monthly_close/domain/monthly_close.dart';
import '../../wealth/application/providers/wealth_provider.dart';
import '../domain/business_reporting.dart';

class ReportingData {
  const ReportingData({required this.report, required this.timeline});
  final BusinessPeriodReport report;
  final List<TimelineFact> timeline;
}

final selectedReportingMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final reportingDataProvider = FutureProvider<ReportingData>((ref) async {
  final month = ref.watch(selectedReportingMonthProvider);
  final period = ReportingPeriod.month(month);
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (householdId == null) throw StateError('Aucun foyer actif.');
  final client = ref.watch(supabaseClientProvider);
  final values = await Future.wait([
    ref
        .watch(transactionsSupabaseRepositoryProvider)
        .all(
          filter: TransactionHistoryFilter(
            from: period.start,
            to: period.endExclusive.subtract(const Duration(microseconds: 1)),
            pageSize: 500,
          ),
        ),
    ref.watch(monthlyCloseGatewayProvider).fetch(month),
    ref.watch(wealthDataProvider.future),
    client
        .from('historical_analytic_line_status')
        .select(
          'id,occurred_on,detail,current_analytical_amount,decision,current_classification',
        )
        .eq('household_id', householdId)
        .gte('occurred_on', _day(period.start))
        .lt('occurred_on', _day(period.endExclusive))
        .not('decision', 'is', null)
        .order('occurred_on')
        .limit(500),
    client
        .from('timeline_significance_marks')
        .select('source_kind,source_id')
        .eq('household_id', householdId),
  ]);
  final transactions = values[0] as List<TransactionHistoryItem>;
  final close = values[1] as MonthlyCloseSnapshot;
  final wealth = values[2] as WealthData;
  final importedRows = values[3] as List<dynamic>;
  final markRows = values[4] as List<dynamic>;
  final marks = {
    for (final raw in markRows)
      '${(raw as Map)['source_kind']}:${raw['source_id']}',
  };
  final imported = <TimelineFact>[
    for (final raw in importedRows)
      TimelineFact(
        identity: 'historical_analytic_line:${(raw as Map)['id']}',
        title: raw['detail'].toString(),
        date: DateTime.parse(raw['occurred_on'].toString()),
        amount: _money(raw['current_analytical_amount']),
        status: ReportFactStatus.imported,
        source: ReportFactSource.importedHistory,
        reason: 'Décision analytique importée : ${raw['decision']}',
        manuallyMarked: marks.contains('historical_analytic_line:${raw['id']}'),
        canToggleMark: true,
      ),
  ];
  return ReportingData(
    report: buildBusinessPeriodReport(
      period: period,
      transactions: transactions,
      close: close,
      importedFacts: imported,
    ),
    timeline: buildSignificantTimeline(
      period: period,
      nativeEvents: transactions,
      importedFacts: imported,
      closeDecisions: close.history,
      dues: wealth.consolidatedDues,
      manualMarks: marks,
    ),
  );
});

final timelineMarkActionProvider = Provider<TimelineMarkActions>(
  TimelineMarkActions.new,
);

class TimelineMarkActions {
  TimelineMarkActions(this.ref);
  final Ref ref;

  Future<void> setMarked(TimelineFact fact, bool marked) async {
    if (!fact.canToggleMark) return;
    final parts = fact.identity.split(':');
    if (parts.length != 2) throw StateError('Source de timeline invalide.');
    final household = await ref.read(activeHouseholdProvider.future);
    final householdId = household.householdId;
    final client = ref.read(supabaseClientProvider);
    final userId = client.auth.currentUser?.id;
    if (householdId == null || userId == null) {
      throw StateError('Session ou foyer indisponible.');
    }
    if (marked) {
      await client
          .from('timeline_significance_marks')
          .upsert(
            {
              'household_id': householdId,
              'user_id': userId,
              'source_kind': parts.first,
              'source_id': parts.last,
              'created_by': userId,
            },
            onConflict: 'household_id,user_id,source_kind,source_id',
            ignoreDuplicates: true,
          );
    } else {
      await client
          .from('timeline_significance_marks')
          .delete()
          .eq('household_id', householdId)
          .eq('user_id', userId)
          .eq('source_kind', parts.first)
          .eq('source_id', parts.last);
    }
    ref.invalidate(reportingDataProvider);
  }
}

String _day(DateTime value) => value.toIso8601String().split('T').first;

Money? _money(Object? value) => value == null
    ? null
    : Money.fromDirhams(num.tryParse(value.toString()) ?? 0);
