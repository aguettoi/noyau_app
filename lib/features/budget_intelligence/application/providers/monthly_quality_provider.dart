import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dashboard/application/providers/dashboard_history_provider.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../../../financial_availability/application/providers/financial_availability_provider.dart';
import '../../../recurring_finance/application/recurring_finance_provider.dart';
import '../budget_reporting.dart';
import '../monthly_quality_analysis.dart';
import 'remote_budget_provider.dart';

typedef MonthlyQualityQuery = ({
  BudgetHorizon horizon,
  RemoteBudgetPeriod period,
});

final monthlyQualityProvider =
    FutureProvider.family<MonthlyQualityAnalysis, MonthlyQualityQuery>((
      ref,
      query,
    ) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (householdId == null) throw StateError('Aucun foyer actif.');
      final start = switch (query.horizon) {
        BudgetHorizon.monthly => query.period.startsOn,
        BudgetHorizon.ytd => DateTime(query.period.startsOn.year),
        BudgetHorizon.ltd => DateTime(1970),
      };
      final end = query.period.endsOn;
      final budget = await ref.watch(
        remoteBudgetReportingProvider((
          horizon: query.horizon,
          period: query.period,
        )).future,
      );
      final occurrences = await ref.watch(expectedOccurrencesProvider.future);
      final reconciliations = await ref.watch(
        dashboardReconciliationsProvider.future,
      );
      final availability = await ref.watch(
        financialAvailabilityProvider.future,
      );
      final client = ref.watch(supabaseClientProvider);
      final eventRows = await client
          .from('financial_events')
          .select('id,event_type,created_by')
          .eq('household_id', householdId)
          .gte('occurred_at', start.toUtc().toIso8601String())
          .lt(
            'occurred_at',
            DateTime(
              end.year,
              end.month,
              end.day + 1,
            ).toUtc().toIso8601String(),
          );
      final eventIds = [for (final row in eventRows) row['id'].toString()];
      final attachmentRows = eventIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : await client
                .from('financial_event_attachments')
                .select('financial_event_id')
                .eq('household_id', householdId)
                .isFilter('deleted_at', null)
                .inFilter('financial_event_id', eventIds);
      final attachedIds = {
        for (final row in attachmentRows) row['financial_event_id'].toString(),
      };
      return analyzeMonthlyQuality(
        periodStart: start,
        periodEnd: end,
        budget: budget,
        occurrences: occurrences,
        events: [
          for (final row in eventRows)
            MonthlyQualityEvent(
              id: row['id'].toString(),
              requiresReceipt: const {
                'cash_expense',
                'debt_expense',
              }.contains(row['event_type']),
              hasReceipt: attachedIds.contains(row['id'].toString()),
              // created_by is the audit actor, not an economic assignee.
              // Without a distinct proven assignee the safe product meaning is
              // household responsibility, never an inferred individual one.
              responsibility: MonthlyResponsibility.household,
            ),
        ],
        reconciliations: [
          for (final item in reconciliations)
            if (!item.observedAt.isBefore(start) &&
                !item.observedAt.isAfter(end))
              MonthlyQualityReconciliation(
                open: item.isOpen,
                observedAt: item.observedAt,
              ),
        ],
        availabilityComplete: availability.isComplete,
      );
    });
