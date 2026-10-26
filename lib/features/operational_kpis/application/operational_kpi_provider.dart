import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../dashboard/application/providers/dashboard_history_provider.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/application/providers/remote_transactions_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../finance/domain/financial_account.dart';
import '../../finance/domain/transaction_draft.dart';
import '../../finance/domain/transaction_history_item.dart';
import '../../recurring_finance/application/recurring_finance_provider.dart';
import '../../recurring_finance/domain/recurring_finance.dart';
import '../domain/operational_kpis.dart';

class OperationalKpiBundle {
  const OperationalKpiBundle({
    required this.global,
    required this.byMember,
    required this.cash,
    required this.memberNames,
  });

  final OperationalQualitySnapshot global;
  final Map<String, OperationalQualitySnapshot> byMember;
  final CashQualitySnapshot cash;
  final Map<String, String> memberNames;
}

abstract interface class CashQualityGateway {
  Future<List<CashInventoryDatum>> fetch({
    required String householdId,
    required Set<String> accountIds,
    required DateTime start,
    required DateTime endExclusive,
  });
}

class SupabaseCashQualityGateway implements CashQualityGateway {
  SupabaseCashQualityGateway(this.ref);
  final Ref ref;

  @override
  Future<List<CashInventoryDatum>> fetch({
    required String householdId,
    required Set<String> accountIds,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    if (accountIds.isEmpty) return const [];
    final client = ref.read(supabaseClientProvider);
    final rows = await client
        .from('account_balance_observations')
        .select(
          'id,account_id,actual_balance,observed_at,created_at,created_by,theoretical_balance_snapshot,difference_snapshot,input_mode,denomination_detail',
        )
        .eq('household_id', householdId)
        .inFilter('account_id', accountIds.toList())
        .gte('observed_at', start.toUtc().toIso8601String())
        .lt('observed_at', endExclusive.toUtc().toIso8601String())
        .order('observed_at', ascending: true);
    final ids = rows.map((row) => row['id'].toString()).toList(growable: false);
    final cases = ids.isEmpty
        ? const <dynamic>[]
        : await client
              .from('account_reconciliation_cases')
              .select('observation_id,status,remaining_difference,updated_at')
              .eq('household_id', householdId)
              .inFilter('observation_id', ids);
    final casesByObservation = {
      for (final row in cases) row['observation_id'].toString(): row,
    };
    return List.unmodifiable([
      for (final row in rows)
        _cashDatum(row, casesByObservation[row['id'].toString()]),
    ]);
  }

  CashInventoryDatum _cashDatum(dynamic raw, dynamic caseRaw) {
    final row = Map<String, dynamic>.from(raw as Map);
    final caseRow = caseRaw == null
        ? null
        : Map<String, dynamic>.from(caseRaw as Map);
    final detail = (row['denomination_detail'] as List? ?? const []);
    final denominationTotal = detail.fold<int>(0, (sum, item) {
      final value = Map<String, dynamic>.from(item as Map);
      return sum +
          ((value['value_minor'] as num?)?.toInt() ?? 0) *
              ((value['quantity'] as num?)?.toInt() ?? 0);
    });
    final observedMinor = _minor(row['actual_balance']);
    final status = caseRow?['status']?.toString();
    final resolved =
        status != null &&
        !const {
          'open',
          'partially_resolved',
          'explained_pending',
        }.contains(status);
    return CashInventoryDatum(
      id: row['id'].toString(),
      accountId: row['account_id'].toString(),
      observedAt: DateTime.parse(row['observed_at'].toString()).toLocal(),
      recordedAt: DateTime.parse(row['created_at'].toString()).toLocal(),
      actorUserId: row['created_by'].toString(),
      denominationConsistent:
          row['input_mode'] != 'denominations' ||
          denominationTotal == observedMinor,
      resolved: resolved,
      observed: row['actual_balance'] == null
          ? null
          : _money(row['actual_balance']),
      theoretical: row['theoretical_balance_snapshot'] == null
          ? null
          : _money(row['theoretical_balance_snapshot']),
      remainingDifference: caseRow?['remaining_difference'] == null
          ? row['difference_snapshot'] == null
                ? null
                : _money(row['difference_snapshot'])
          : _money(caseRow!['remaining_difference']),
      resolvedAt: resolved && caseRow?['updated_at'] != null
          ? DateTime.parse(caseRow!['updated_at'].toString()).toLocal()
          : null,
      // No current canonical field declares a cash custodian or economic
      // responsibility. They deliberately remain unknown instead of being
      // inferred from the recorder or account holder.
      declaredHolderId: null,
      explicitResponsibleId: null,
    );
  }

  int _minor(Object? value) =>
      ((num.tryParse(value?.toString() ?? '') ?? 0) * 100).round();
  Money _money(Object? value) => Money.fromMinorUnits(_minor(value));
}

final cashQualityGatewayProvider = Provider<CashQualityGateway>(
  SupabaseCashQualityGateway.new,
);

final operationalKpiProvider = FutureProvider<OperationalKpiBundle>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (householdId == null) throw StateError('Aucun foyer actif.');
  final now = ref.watch(dashboardClockProvider);
  final bounds = ref.watch(dashboardPeriodProvider).bounds(now);
  final values = await Future.wait([
    ref.watch(
      filteredTransactionsProvider(
        TransactionHistoryFilter(
          from: bounds.start,
          to: bounds.end.subtract(const Duration(microseconds: 1)),
          pageSize: 5000,
        ),
      ).future,
    ),
    ref.watch(dashboardReconciliationsProvider.future),
    ref.watch(expectedOccurrencesProvider.future),
    ref.watch(remoteHouseholdMembersProvider.future),
    ref.watch(remoteAccountsProvider.future),
  ]);
  final transactions = values[0] as List<TransactionHistoryItem>;
  final reconciliations = values[1] as List<DashboardReconciliation>;
  final occurrences = values[2] as List<ExpectedFinancialOccurrence>;
  final members = values[3] as List<dynamic>;
  final accounts = values[4] as List<FinancialAccount>;
  final entries = transactions.map(_entry).toList(growable: false);
  final reconciliationData = [
    for (var index = 0; index < reconciliations.length; index++)
      ReconciliationDatum(
        id: '${reconciliations[index].accountId}:$index',
        openedAt: reconciliations[index].observedAt,
        resolved: !reconciliations[index].isOpen,
      ),
  ];
  final openOccurrences = occurrences
      .where(
        (item) =>
            !item.expectedOn.isBefore(bounds.start) &&
            item.expectedOn.isBefore(bounds.end) &&
            item.status != ExpectedOccurrenceStatus.realized &&
            item.status != ExpectedOccurrenceStatus.ignored,
      )
      .toList(growable: false);
  OperationalQualitySnapshot quality(String? memberId) =>
      analyzeOperationalQuality(
        periodStart: bounds.start,
        periodEndExclusive: bounds.end,
        entries: entries,
        reconciliations: reconciliationData,
        expectedNotMaterialized: memberId == null
            ? openOccurrences.length
            : openOccurrences.where((item) => item.memberId == memberId).length,
        evaluatedAt: now,
        memberId: memberId,
      );
  final cash = await ref
      .watch(cashQualityGatewayProvider)
      .fetch(
        householdId: householdId,
        accountIds: {
          for (final account in accounts)
            if (account.type == FinancialAccountType.cash &&
                account.canReadBalance)
              account.id,
        },
        start: bounds.start,
        endExclusive: bounds.end,
      );
  return OperationalKpiBundle(
    global: quality(null),
    byMember: Map.unmodifiable({
      for (final member in members)
        member.id.toString(): quality(member.id.toString()),
    }),
    cash: analyzeCashQuality(
      periodStart: bounds.start,
      periodEndExclusive: bounds.end,
      inventories: cash,
    ),
    memberNames: Map.unmodifiable({
      for (final member in members)
        member.id.toString(): member.displayName.toString(),
    }),
  );
});

OperationalEntry _entry(TransactionHistoryItem item) {
  final expense = const {
    LedgerTransactionType.expense,
    LedgerTransactionType.debtExpense,
  }.contains(item.type);
  return OperationalEntry(
    id: item.id,
    economicDate: item.occurredAt.toLocal(),
    enteredAt: item.createdAt.toLocal(),
    actorUserId: item.actorId ?? 'unknown',
    responsibility: EconomicResponsibility.unassigned,
    economicMemberId: null,
    categorized: item.type != LedgerTransactionType.unknown,
    requiresEnvelope: expense,
    hasEnvelope: item.envelopes.isNotEmpty,
    requiresReceipt: expense,
    hasReceipt: item.attachments.isNotEmpty,
  );
}
