import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../features/finance/application/providers/active_household_provider.dart';
import '../../../../features/finance/application/providers/supabase_client_provider.dart';
import '../../application/budget_reporting.dart';
import '../../domain/budget_intelligence.dart';
import '../../infrastructure/budget_supabase_repository.dart';

class SupabaseBudgetGateway implements BudgetSupabaseGateway {
  SupabaseBudgetGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<Object?> insert(String table, Map<String, Object?> values) =>
      _client.from(table).insert(values).select().single();

  @override
  Future<Object?> upsert(String table, Map<String, Object?> values) =>
      _client.from(table).upsert(values).select().single();

  @override
  Future<Object?> rpc(String function, Map<String, Object?> parameters) =>
      _client.rpc(function, params: parameters);

  @override
  Future<List<Map<String, Object?>>> select(
    String table,
    Map<String, Object?> filters,
  ) async {
    dynamic query = _client.from(table).select();
    for (final entry in filters.entries) {
      query = query.eq(entry.key, entry.value);
    }
    final rows = await query;
    return (rows as List<dynamic>)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  @override
  Future<void> update(
    String table,
    Map<String, Object?> values,
    Map<String, Object?> filters,
  ) async {
    dynamic query = _client.from(table).update(values);
    for (final entry in filters.entries) {
      query = query.eq(entry.key, entry.value);
    }
    await query;
  }

  @override
  Future<void> delete(String table, Map<String, Object?> filters) async {
    dynamic query = _client.from(table).delete();
    for (final entry in filters.entries) {
      query = query.eq(entry.key, entry.value);
    }
    await query;
  }
}

final budgetSupabaseGatewayProvider = Provider<BudgetSupabaseGateway>(
  (ref) => SupabaseBudgetGateway(ref.watch(supabaseClientProvider)),
);

final budgetSupabaseRepositoryProvider =
    FutureProvider<BudgetSupabaseRepository>((ref) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      final userId = ref.watch(currentUserIdProvider);
      if (!household.hasActiveHousehold ||
          householdId == null ||
          userId == null) {
        throw StateError(
          'An active household and authenticated user are required.',
        );
      }
      return BudgetSupabaseRepository(
        gateway: ref.watch(budgetSupabaseGatewayProvider),
        householdId: householdId,
        userId: userId,
      );
    });

class RemoteBudgetPeriod {
  const RemoteBudgetPeriod({
    required this.id,
    required this.householdId,
    required this.startsOn,
    required this.endsOn,
    required this.status,
    this.scenarioId,
  });
  final String id;
  final String householdId;
  final DateTime startsOn;
  final DateTime endsOn;
  final String status;
  final String? scenarioId;

  String get label =>
      '${startsOn.year}-${startsOn.month.toString().padLeft(2, '0')}';
}

class RemoteBudgetRun {
  const RemoteBudgetRun({
    required this.id,
    required this.scenarioId,
    required this.periodId,
    required this.status,
    required this.availableCents,
    required this.totalCents,
    required this.remainingCents,
    required this.createdAt,
    this.scenarioVersionId,
    this.summary = const {},
    this.approvedAt,
    this.appliedAt,
  });
  final String id;
  final String scenarioId;
  final String periodId;
  final String status;
  final int availableCents;
  final int totalCents;
  final int remainingCents;
  final DateTime createdAt;
  final String? scenarioVersionId;
  final Map<String, Object?> summary;
  final DateTime? approvedAt;
  final DateTime? appliedAt;
}

class RemoteBudgetRunLine {
  const RemoteBudgetRunLine({
    required this.id,
    required this.envelopeId,
    required this.previousBalanceCents,
    required this.rolloverCents,
    required this.plannedCents,
    required this.resultingCents,
    required this.priority,
    this.warning,
  });
  final String id;
  final String envelopeId;
  final int previousBalanceCents;
  final int rolloverCents;
  final int plannedCents;
  final int resultingCents;
  final int priority;
  final String? warning;
}

/// One reporting row is a flow aggregation for one envelope and one horizon.
class RemoteBudgetReportRow {
  const RemoteBudgetReportRow({
    required this.envelopeId,
    required this.plannedCents,
    required this.actualCents,
    required this.inflowsCents,
    required this.outflowsCents,
    required this.balanceCents,
  });
  final String envelopeId;
  final int plannedCents;
  final int actualCents;
  final int inflowsCents;
  final int outflowsCents;
  final int balanceCents;
  int get varianceCents => plannedCents - actualCents;
  double? get consumptionRate =>
      plannedCents <= 0 ? null : actualCents / plannedCents;
}

final remoteBudgetPeriodsProvider = FutureProvider<List<RemoteBudgetPeriod>>((
  ref,
) async {
  final repository = await ref.watch(budgetSupabaseRepositoryProvider.future);
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('budget_periods')
      .select('id, household_id, starts_on, ends_on, status, scenario_id')
      .eq('household_id', repository.householdId)
      .order('starts_on', ascending: false);
  return List.unmodifiable(
    (rows as List<dynamic>).map((raw) {
      final row = Map<String, Object?>.from(raw as Map);
      return RemoteBudgetPeriod(
        id: row['id'] as String,
        householdId: row['household_id'] as String,
        startsOn: DateTime.parse(row['starts_on'] as String),
        endsOn: DateTime.parse(row['ends_on'] as String),
        status: row['status'] as String,
        scenarioId: row['scenario_id'] as String?,
      );
    }),
  );
});

final selectedBudgetPeriodIdProvider = StateProvider<String?>((_) => null);
final selectedBudgetScenarioIdProvider = StateProvider<String?>((_) => null);

/// The versioned programmable model is intentionally isolated from the
/// legacy scenario query: 080006 is not deployed everywhere yet.
final budgetScenarioVersionsProvider =
    FutureProvider.family<List<BudgetScenarioVersion>, String>((
      ref,
      scenarioId,
    ) async {
      final repository = await ref.watch(
        budgetSupabaseRepositoryProvider.future,
      );
      final rows = await ref.watch(budgetSupabaseGatewayProvider).select(
        'budget_scenario_versions',
        {'household_id': repository.householdId, 'scenario_id': scenarioId},
      );
      final versions =
          rows
              .map(
                (row) => BudgetScenarioVersion(
                  id: row['id'] as String,
                  scenarioId: row['scenario_id'] as String,
                  version: row['version'] as int? ?? 1,
                  createdAt: DateTime.parse(row['created_at'] as String),
                  notes: row['notes'] as String?,
                ),
              )
              .toList()
            ..sort((left, right) => right.version.compareTo(left.version));
      return List.unmodifiable(versions);
    });

final budgetScenarioSourcesProvider =
    FutureProvider.family<List<BudgetSource>, String>((ref, versionId) async {
      final repository = await ref.watch(
        budgetSupabaseRepositoryProvider.future,
      );
      return repository.sourcesForVersion(versionId);
    });

final budgetScenarioStepsProvider =
    FutureProvider.family<List<BudgetAllocationStep>, String>((
      ref,
      versionId,
    ) async {
      final repository = await ref.watch(
        budgetSupabaseRepositoryProvider.future,
      );
      return repository.stepsForVersion(versionId);
    });

final remoteBudgetScenariosProvider = FutureProvider<List<BudgetScenario>>((
  ref,
) async {
  final repository = await ref.watch(budgetSupabaseRepositoryProvider.future);
  final client = ref.watch(supabaseClientProvider);
  dynamic rows;
  try {
    rows = await client
        .from('budget_scenarios')
        .select(
          'id, name, description, active, priority, valid_from, valid_to, notes, is_default, current_version_id',
        )
        .eq('household_id', repository.householdId)
        .order('priority');
  } on PostgrestException catch (error) {
    // 080006 is intentionally not deployed to every environment yet.
    if (!const {'42703', 'PGRST204'}.contains(error.code)) rethrow;
    rows = await client
        .from('budget_scenarios')
        .select(
          'id, name, description, active, priority, valid_from, valid_to, notes',
        )
        .eq('household_id', repository.householdId)
        .order('priority');
  }
  return List.unmodifiable(
    (rows as List<dynamic>).map((raw) {
      final row = Map<String, Object?>.from(raw as Map);
      return BudgetScenario(
        id: row['id'] as String,
        householdId: repository.householdId,
        name: row['name'] as String,
        description: row['description'] as String?,
        active: row['active'] == true,
        priority: row['priority'] as int? ?? 0,
        validFrom: _date(row['valid_from']),
        validTo: _date(row['valid_to']),
        notes: row['notes'] as String?,
        isDefault: row['is_default'] == true,
        currentVersionId: row['current_version_id'] as String?,
      );
    }),
  );
});

final budgetScenarioMemberIncomesProvider =
    FutureProvider.family<List<BudgetScenarioMemberIncome>, String>((
      ref,
      scenarioId,
    ) async {
      try {
        final repository = await ref.watch(
          budgetSupabaseRepositoryProvider.future,
        );
        final rows = await ref
            .watch(supabaseClientProvider)
            .from('budget_scenario_member_incomes')
            .select(
              'member_user_id, net_recurring_income, other_recurring_income, exceptional_income, exceptional_treatment, notes',
            )
            .eq('household_id', repository.householdId)
            .eq('scenario_id', scenarioId);
        return List.unmodifiable(
          (rows as List<dynamic>).map((raw) {
            final row = Map<String, Object?>.from(raw as Map);
            return BudgetScenarioMemberIncome(
              memberUserId: row['member_user_id'] as String,
              netRecurringCents: _cents(row['net_recurring_income']) ?? 0,
              otherRecurringCents: _cents(row['other_recurring_income']) ?? 0,
              exceptionalCents: _cents(row['exceptional_income']) ?? 0,
              exceptionalTreatment: _exceptionalTreatmentFromSql(
                row['exceptional_treatment'] as String? ?? 'excluded',
              ),
              notes: row['notes'] as String?,
            );
          }),
        );
      } on PostgrestException catch (error, stackTrace) {
        _throwContributionSchemaError(error, stackTrace);
      }
    });

final budgetScenarioRulesProvider =
    FutureProvider.family<List<BudgetScenarioRule>, String>((
      ref,
      scenarioId,
    ) async {
      final repository = await ref.watch(
        budgetSupabaseRepositoryProvider.future,
      );
      final client = ref.watch(supabaseClientProvider);
      try {
        final rows = await client
            .from('budget_scenario_rules')
            .select(
              'id, envelope_id, allocation_method, amount, percentage, minimum_amount, maximum_amount, priority, rollover_policy, rollover_cap, notes, active, funding_mode, funding_member_user_id, funding_definition',
            )
            .eq('household_id', repository.householdId)
            .eq('scenario_id', scenarioId)
            .order('priority');
        return List.unmodifiable(
          (rows as List<dynamic>).map((raw) {
            final row = Map<String, Object?>.from(raw as Map);
            return BudgetScenarioRule(
              id: row['id'] as String,
              scenarioId: scenarioId,
              envelopeId: row['envelope_id'] as String,
              method: BudgetAllocationMethod.values.byName(
                row['allocation_method'] as String,
              ),
              priority: row['priority'] as int? ?? 0,
              rolloverPolicy: _rolloverFromSql(
                row['rollover_policy'] as String,
              ),
              amountCents: _cents(row['amount']),
              percentage: double.tryParse(row['percentage']?.toString() ?? ''),
              minimumCents: _cents(row['minimum_amount']),
              maximumCents: _cents(row['maximum_amount']),
              rolloverCapCents: _cents(row['rollover_cap']),
              notes: row['notes'] as String?,
              active: budgetRuleActiveFromData(row['active']),
              fundingMode: _fundingModeFromSql(
                row['funding_mode'] as String? ?? 'shared_auto',
              ),
              fundingMemberUserId: row['funding_member_user_id'] as String?,
              fundingDefinition: row['funding_definition'] is Map
                  ? Map<String, Object?>.from(row['funding_definition'] as Map)
                  : const {},
            );
          }),
        );
      } on PostgrestException catch (error, stackTrace) {
        _throwContributionSchemaError(error, stackTrace);
      }
    });

class BudgetContributionSchemaUnavailableException implements Exception {
  const BudgetContributionSchemaUnavailableException();
}

Never _throwContributionSchemaError(
  PostgrestException error,
  StackTrace stackTrace,
) {
  const schemaCodes = <String>{'42P01', '42703', 'PGRST204'};
  if (schemaCodes.contains(error.code)) {
    Error.throwWithStackTrace(
      const BudgetContributionSchemaUnavailableException(),
      stackTrace,
    );
  }
  Error.throwWithStackTrace(error, stackTrace);
}

String budgetContributionLoadMessage(
  Object error, {
  required String productionFallback,
}) {
  if (error is BudgetContributionSchemaUnavailableException && kDebugMode) {
    return 'Le modèle Contributions du foyer doit être installé dans cet environnement de développement.';
  }
  return productionFallback;
}

final remoteBudgetRunsProvider = FutureProvider<List<RemoteBudgetRun>>((
  ref,
) async {
  final repository = await ref.watch(budgetSupabaseRepositoryProvider.future);
  final client = ref.watch(supabaseClientProvider);
  dynamic rows;
  try {
    rows = await client
        .from('budget_allocation_runs')
        .select(
          'id, scenario_id, scenario_version_id, budget_period_id, status, available_resources, calculated_total, remaining_unallocated, summary, created_at, approved_at, applied_at',
        )
        .eq('household_id', repository.householdId)
        .order('created_at', ascending: false);
  } on PostgrestException catch (error) {
    if (!const {'42703', 'PGRST204'}.contains(error.code)) rethrow;
    rows = await client
        .from('budget_allocation_runs')
        .select(
          'id, scenario_id, budget_period_id, status, available_resources, calculated_total, remaining_unallocated, summary, created_at, approved_at, applied_at',
        )
        .eq('household_id', repository.householdId)
        .order('created_at', ascending: false);
  }
  return List.unmodifiable(
    (rows as List<dynamic>).map((raw) {
      final row = Map<String, Object?>.from(raw as Map);
      return RemoteBudgetRun(
        id: row['id'] as String,
        scenarioId: row['scenario_id'] as String,
        periodId: row['budget_period_id'] as String,
        status: row['status'] as String,
        availableCents: _cents(row['available_resources']) ?? 0,
        totalCents: _cents(row['calculated_total']) ?? 0,
        remainingCents: _cents(row['remaining_unallocated']) ?? 0,
        createdAt: DateTime.parse(row['created_at'] as String),
        scenarioVersionId: row['scenario_version_id'] as String?,
        summary: row['summary'] is Map
            ? Map<String, Object?>.from(row['summary'] as Map)
            : const {},
        approvedAt: _date(row['approved_at']),
        appliedAt: _date(row['applied_at']),
      );
    }),
  );
});

/// Run detail is intentionally derived from the run history provider so a
/// successful mutation refreshes list and detail from the same source.
final remoteBudgetRunProvider = FutureProvider.family<RemoteBudgetRun?, String>(
  (ref, runId) async {
    final runs = await ref.watch(remoteBudgetRunsProvider.future);
    for (final run in runs) {
      if (run.id == runId) return run;
    }
    return null;
  },
);

final remoteBudgetRunLinesProvider =
    FutureProvider.family<List<RemoteBudgetRunLine>, String>((
      ref,
      runId,
    ) async {
      final repository = await ref.watch(
        budgetSupabaseRepositoryProvider.future,
      );
      final client = ref.watch(supabaseClientProvider);
      final rows = await client
          .from('budget_allocation_run_lines')
          .select(
            'id, envelope_id, previous_balance, rollover_amount, planned_allocation, resulting_available, priority, warning',
          )
          .eq('household_id', repository.householdId)
          .eq('run_id', runId)
          .order('priority');
      return List.unmodifiable(
        (rows as List<dynamic>).map((raw) {
          final row = Map<String, Object?>.from(raw as Map);
          return RemoteBudgetRunLine(
            id: row['id'] as String,
            envelopeId: row['envelope_id'] as String,
            previousBalanceCents: _cents(row['previous_balance']) ?? 0,
            rolloverCents: _cents(row['rollover_amount']) ?? 0,
            plannedCents: _cents(row['planned_allocation']) ?? 0,
            resultingCents: _cents(row['resulting_available']) ?? 0,
            priority: row['priority'] as int? ?? 0,
            warning: row['warning'] as String?,
          );
        }),
      );
    });

final remoteBudgetReportingProvider =
    FutureProvider.family<
      List<RemoteBudgetReportRow>,
      ({BudgetHorizon horizon, RemoteBudgetPeriod period})
    >((ref, query) async {
      final repository = await ref.watch(
        budgetSupabaseRepositoryProvider.future,
      );
      final client = ref.watch(supabaseClientProvider);
      final start = switch (query.horizon) {
        BudgetHorizon.monthly => query.period.startsOn,
        BudgetHorizon.ytd => DateTime(query.period.startsOn.year),
        BudgetHorizon.ltd => DateTime(1970),
      };
      final reportRows = await client
          .from('budget_envelope_reporting')
          .select(
            'envelope_id, period_start, allocations, inflows, outflows, consumption',
          )
          .eq('household_id', repository.householdId)
          .gte('period_start', _isoDate(start))
          .lte('period_start', _isoDate(query.period.endsOn));
      final planned = await _officialPlanByEnvelope(
        client: client,
        householdId: repository.householdId,
        start: start,
        end: query.period.endsOn,
      );
      final aggregate = <String, _ReportAccumulator>{};
      for (final raw in reportRows as List<dynamic>) {
        final row = Map<String, Object?>.from(raw as Map);
        final value = aggregate.putIfAbsent(
          row['envelope_id'] as String,
          _ReportAccumulator.new,
        );
        value.inflows += _cents(row['inflows']) ?? 0;
        value.outflows += _cents(row['outflows']) ?? 0;
        value.consumption += _cents(row['consumption']) ?? 0;
      }
      for (final entry in planned.entries) {
        aggregate.putIfAbsent(entry.key, _ReportAccumulator.new).planned +=
            entry.value;
      }
      return List.unmodifiable(
        aggregate.entries
            .map(
              (entry) => RemoteBudgetReportRow(
                envelopeId: entry.key,
                plannedCents: entry.value.planned,
                actualCents: entry.value.consumption,
                inflowsCents: entry.value.inflows,
                outflowsCents: entry.value.outflows,
                balanceCents: entry.value.inflows - entry.value.outflows,
              ),
            )
            .toList(growable: false),
      );
    });

class BudgetSimulationState {
  const BudgetSimulationState({this.run, this.error, this.saving = false});
  final BudgetAllocationRun? run;
  final String? error;
  final bool saving;

  BudgetSimulationState copyWith({
    BudgetAllocationRun? run,
    String? error,
    bool? saving,
    bool clearError = false,
  }) => BudgetSimulationState(
    run: run ?? this.run,
    error: clearError ? null : (error ?? this.error),
    saving: saving ?? this.saving,
  );
}

final budgetSimulationStateProvider = StateProvider<BudgetSimulationState>(
  (_) => const BudgetSimulationState(),
);

final budgetMutationInFlightProvider = StateProvider<bool>((_) => false);

class _ReportAccumulator {
  int planned = 0;
  int inflows = 0;
  int outflows = 0;
  int consumption = 0;
}

Future<Map<String, int>> _officialPlanByEnvelope({
  required SupabaseClient client,
  required String householdId,
  required DateTime start,
  required DateTime end,
}) async {
  // Applied wins for a period. If none is applied, the latest approved run is
  // the official plan. This prevents double counting planned allocations.
  final runs = await client
      .from('budget_allocation_runs')
      .select(
        'id, budget_period_id, status, created_at, budget_periods!inner(starts_on, ends_on)',
      )
      .eq('household_id', householdId)
      .inFilter('status', const ['approved', 'applied']);
  final selectedByPeriod = <String, Map<String, Object?>>{};
  for (final raw in runs as List<dynamic>) {
    final row = Map<String, Object?>.from(raw as Map);
    final period = Map<String, Object?>.from(row['budget_periods'] as Map);
    final startsOn = DateTime.parse(period['starts_on'] as String);
    final endsOn = DateTime.parse(period['ends_on'] as String);
    if (startsOn.isBefore(start) || endsOn.isAfter(end)) {
      continue;
    }
    final key = row['budget_period_id'] as String;
    final existing = selectedByPeriod[key];
    if (existing == null ||
        (row['status'] == 'applied' && existing['status'] != 'applied') ||
        (row['status'] == existing['status'] &&
            (row['created_at'] as String).compareTo(
                  existing['created_at'] as String,
                ) >
                0)) {
      selectedByPeriod[key] = row;
    }
  }
  if (selectedByPeriod.isEmpty) return const {};
  final lineRows = await client
      .from('budget_allocation_run_lines')
      .select('run_id, envelope_id, planned_allocation')
      .eq('household_id', householdId)
      .inFilter(
        'run_id',
        selectedByPeriod.values.map((run) => run['id']).toList(),
      );
  final totals = <String, int>{};
  for (final raw in lineRows as List<dynamic>) {
    final row = Map<String, Object?>.from(raw as Map);
    final envelopeId = row['envelope_id'] as String;
    totals[envelopeId] =
        (totals[envelopeId] ?? 0) + (_cents(row['planned_allocation']) ?? 0);
  }
  return totals;
}

int? _cents(Object? value) {
  if (value == null) return null;
  final number = num.tryParse(value.toString());
  return number == null ? null : (number * 100).round();
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

/// Rules are active by default in the SQL and domain contracts. A legacy row
/// with a missing value therefore preserves the default instead of becoming
/// silently disabled in the editor.
bool budgetRuleActiveFromData(Object? value) => value is bool ? value : true;

RolloverPolicy _rolloverFromSql(String value) => switch (value) {
  'report_deficit_only' => RolloverPolicy.reportDeficitOnly,
  'reset' => RolloverPolicy.reset,
  'cap_rollover' => RolloverPolicy.capRollover,
  _ => RolloverPolicy.reportTotal,
};

BudgetFundingMode _fundingModeFromSql(String value) => switch (value) {
  'personal_member' => BudgetFundingMode.personalMember,
  'shared_custom' => BudgetFundingMode.sharedCustom,
  'fixed_by_member' => BudgetFundingMode.fixedByMember,
  'exceptional_income' => BudgetFundingMode.exceptionalIncome,
  _ => BudgetFundingMode.sharedAuto,
};

ExceptionalIncomeTreatment _exceptionalTreatmentFromSql(String value) =>
    switch (value) {
      'included_in_shared_capacity' =>
        ExceptionalIncomeTreatment.includedInSharedCapacity,
      'direct_allocation' => ExceptionalIncomeTreatment.directAllocation,
      _ => ExceptionalIncomeTreatment.excluded,
    };
