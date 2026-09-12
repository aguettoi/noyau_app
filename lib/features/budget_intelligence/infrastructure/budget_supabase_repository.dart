import '../application/budget_contribution_calculator.dart';
import '../domain/budget_intelligence.dart';

abstract interface class BudgetSupabaseGateway {
  Future<List<Map<String, Object?>>> select(
    String table,
    Map<String, Object?> filters,
  );
  Future<Object?> insert(String table, Map<String, Object?> values);
  Future<Object?> upsert(String table, Map<String, Object?> values);
  Future<void> update(
    String table,
    Map<String, Object?> values,
    Map<String, Object?> filters,
  );
  Future<void> delete(String table, Map<String, Object?> filters);
  Future<Object?> rpc(String function, Map<String, Object?> parameters);
}

/// Boundary for all mutable Budget Intelligence operations.
///
/// Persisting a simulation is delegated to one server RPC so a run and its
/// snapshot lines are either both stored or neither is stored.
class BudgetSupabaseRepository {
  const BudgetSupabaseRepository({
    required this.gateway,
    required this.householdId,
    required this.userId,
  });

  final BudgetSupabaseGateway gateway;
  final String householdId;
  final String userId;

  Future<String> prepareMonthlyPeriod(DateTime month) async {
    final startsOn = DateTime(month.year, month.month);
    final startsOnIso = startsOn.toIso8601String().substring(0, 10);
    final existing = await gateway.select('budget_periods', {
      'household_id': householdId,
      'starts_on': startsOnIso,
    });
    if (existing.isNotEmpty) {
      return existing.first['id'] as String;
    }
    final endsOn = DateTime(
      month.year,
      month.month + 1,
    ).subtract(const Duration(days: 1));
    final created = await gateway.insert('budget_periods', {
      'household_id': householdId,
      'starts_on': startsOnIso,
      'ends_on': endsOn.toIso8601String().substring(0, 10),
      'status': 'draft',
      'created_by': userId,
    });
    return (created as Map)['id'] as String;
  }

  Future<String?> saveScenario(BudgetScenario scenario) async {
    final values = <String, Object?>{
      'household_id': householdId,
      'name': scenario.name.trim(),
      'description': scenario.description,
      'active': scenario.active,
      'priority': scenario.priority,
      'valid_from': scenario.validFrom?.toIso8601String().substring(0, 10),
      'valid_to': scenario.validTo?.toIso8601String().substring(0, 10),
      'notes': scenario.notes,
      'is_default': scenario.isDefault,
      'current_version_id': scenario.currentVersionId,
      'created_by': userId,
    };
    if (scenario.id.isEmpty) {
      final result = await gateway.insert('budget_scenarios', values);
      return result is Map ? result['id'] as String? : null;
    } else {
      await gateway.update('budget_scenarios', values, {
        'id': scenario.id,
        'household_id': householdId,
      });
      return scenario.id;
    }
  }

  Future<void> saveRule(BudgetScenarioRule rule) async {
    _validateRule(rule);
    final values = <String, Object?>{
      'household_id': householdId,
      'scenario_id': rule.scenarioId,
      'envelope_id': rule.envelopeId,
      'allocation_method': rule.method.name,
      'amount': _money(rule.amountCents),
      'percentage': rule.percentage,
      'minimum_amount': _money(rule.minimumCents),
      'maximum_amount': _money(rule.maximumCents),
      'priority': rule.priority,
      'rollover_policy': _rollover(rule.rolloverPolicy),
      'rollover_cap': _money(rule.rolloverCapCents),
      'funding_source_preference': rule.fundingSourcePreference,
      'contribution_rule': _contribution(rule.contributionRule),
      'funding_mode': _fundingMode(rule.fundingMode),
      'funding_member_user_id': rule.fundingMemberUserId,
      'funding_definition': rule.fundingDefinition,
      'notes': rule.notes,
      'active': rule.active,
    };
    if (rule.id.isEmpty) {
      await gateway.insert('budget_scenario_rules', values);
    } else {
      await gateway.update('budget_scenario_rules', values, {
        'id': rule.id,
        'household_id': householdId,
      });
    }
  }

  Future<void> saveMemberIncome(
    BudgetScenarioMemberIncome income,
    String scenarioId,
  ) async {
    await gateway.upsert('budget_scenario_member_incomes', {
      'household_id': householdId,
      'scenario_id': scenarioId,
      'member_user_id': income.memberUserId,
      'net_recurring_income': _money(income.netRecurringCents),
      'other_recurring_income': _money(income.otherRecurringCents),
      'exceptional_income': _money(income.exceptionalCents),
      'exceptional_treatment': _exceptionalTreatment(
        income.exceptionalTreatment,
      ),
      'notes': income.notes,
    });
  }

  Future<String?> saveSource(BudgetSource source) async {
    final values = <String, Object?>{
      'household_id': householdId,
      'scenario_version_id': source.scenarioVersionId,
      'source_type': _sourceType(source.type),
      'name': source.name.trim(),
      'expected_amount': _money(source.expectedCents),
      'member_user_id': source.memberUserId,
      'exceptional_treatment': _exceptionalTreatmentNullable(
        source.exceptionalTreatment,
      ),
      'active': source.active,
    };
    if (source.id.isEmpty) {
      final result = await gateway.insert('budget_scenario_sources', values);
      return result is Map ? result['id'] as String? : null;
    } else {
      await gateway.update('budget_scenario_sources', values, {
        'id': source.id,
        'household_id': householdId,
      });
      return source.id;
    }
  }

  /// Returns the invisible relational anchor required by the legacy non-null
  /// `source_id` column for shared steps. It is never an economic source: the
  /// programmable engine always derives shared funding from member resources.
  Future<String> ensureCommonCapacitySource(String scenarioVersionId) async {
    final existing = (await sourcesForVersion(scenarioVersionId))
        .where((source) => source.type == BudgetSourceType.commonCapacity)
        .firstOrNull;
    if (existing != null) return existing.id;

    final createdId = await saveSource(
      BudgetSource(
        id: '',
        scenarioVersionId: scenarioVersionId,
        type: BudgetSourceType.commonCapacity,
        name: 'Capacité commune technique',
        expectedCents: 0,
      ),
    );
    if (createdId == null || createdId.isEmpty) {
      throw StateError('La référence technique commune n’a pas pu être créée.');
    }
    return createdId;
  }

  Future<String?> saveScenarioVersion(BudgetScenarioVersion version) async {
    final values = <String, Object?>{
      'household_id': householdId,
      'scenario_id': version.scenarioId,
      'version': version.version,
      'notes': version.notes,
      'created_by': userId,
    };
    if (version.id.isEmpty) {
      final result = await gateway.insert('budget_scenario_versions', values);
      return result is Map ? result['id'] as String? : null;
    }
    await gateway.update('budget_scenario_versions', values, {
      'id': version.id,
      'household_id': householdId,
    });
    return version.id;
  }

  Future<void> setScenarioDefault({
    required String scenarioId,
    required bool isDefault,
  }) async {
    if (isDefault) {
      final scenarios = await gateway.select('budget_scenarios', {
        'household_id': householdId,
        'is_default': true,
      });
      for (final existing in scenarios) {
        final existingId = existing['id'] as String?;
        if (existingId != null && existingId != scenarioId) {
          await gateway.update(
            'budget_scenarios',
            {'is_default': false},
            {'id': existingId, 'household_id': householdId},
          );
        }
      }
    }
    await gateway.update(
      'budget_scenarios',
      {'is_default': isDefault},
      {'id': scenarioId, 'household_id': householdId},
    );
  }

  Future<List<BudgetSource>> sourcesForVersion(String versionId) async {
    final rows = await gateway.select('budget_scenario_sources', {
      'household_id': householdId,
      'scenario_version_id': versionId,
    });
    return List.unmodifiable(rows.map(_sourceFromRow));
  }

  Future<List<BudgetAllocationStep>> stepsForVersion(String versionId) async {
    final rows = await gateway.select('budget_scenario_steps', {
      'household_id': householdId,
      'scenario_version_id': versionId,
    });
    final steps = rows.map(_stepFromRow).toList()
      ..sort((left, right) => left.order.compareTo(right.order));
    // Les valeurs 0/10/20 historiques restent lisibles sans migration : la
    // position affichée et utilisée par l'UI est toujours continue, 1..N.
    return List.unmodifiable(normalizeStepOrders(steps));
  }

  Future<String?> saveStep(BudgetAllocationStep step) async {
    final values = <String, Object?>{
      'household_id': householdId,
      'scenario_version_id': step.scenarioVersionId,
      'step_order': step.order,
      'group_name': step.groupName.trim(),
      'source_id': step.sourceId,
      'envelope_id': step.envelopeId,
      'allocation_method': step.method.name,
      'amount': _money(step.amountCents),
      'percentage': step.percentage,
      'contribution_key': _contributionKey(step.contributionKey),
      'member_user_id': step.memberUserId,
      'key_definition': step.keyDefinition,
      'insufficient_funds_policy': _insufficientFundsPolicy(
        step.insufficientFundsPolicy,
      ),
      'funding_source_preference': step.fundingSourcePreference,
      'active': step.active,
    };
    if (step.id.isEmpty) {
      final result = await gateway.insert('budget_scenario_steps', values);
      return result is Map ? result['id'] as String? : null;
    } else {
      // Existing historical steps may still have sparse persisted positions.
      // A normal edit must not overwrite that value before reorderSteps has
      // atomically normalized the full sequence.
      values.remove('step_order');
      await gateway.update('budget_scenario_steps', values, {
        'id': step.id,
        'household_id': householdId,
      });
      return step.id;
    }
  }

  Future<List<BudgetAllocationStep>> sourceReferences(
    String sourceId,
    String versionId,
  ) async => (await stepsForVersion(
    versionId,
  )).where((step) => step.sourceId == sourceId).toList(growable: false);

  Future<void> deleteSource(BudgetSource source) async {
    final references = await sourceReferences(
      source.id,
      source.scenarioVersionId,
    );
    if (references.isNotEmpty) {
      throw StateError(
        'Source utilisée par : ${references.map((step) => step.groupName).join(', ')}',
      );
    }
    await gateway.delete('budget_scenario_sources', {
      'id': source.id,
      'household_id': householdId,
    });
  }

  Future<void> deleteStep(String stepId) => gateway.delete(
    'budget_scenario_steps',
    {'id': stepId, 'household_id': householdId},
  );

  /// Copies a step and normalizes the complete order so the copy is placed
  /// immediately after its original, including after a repository reload.
  Future<String> duplicateStep({
    required BudgetAllocationStep step,
    required List<BudgetAllocationStep> orderedSteps,
  }) async {
    final ordered = [...orderedSteps]
      ..sort((left, right) => left.order.compareTo(right.order));
    final index = ordered.indexWhere((item) => item.id == step.id);
    if (index < 0) {
      throw StateError('Étape introuvable dans cette version.');
    }

    final temporaryOrder =
        (ordered
            .map((item) => item.order)
            .fold<int>(0, (max, order) => order > max ? order : max)) +
        1;
    final createdId = await saveStep(
      _copyStep(step, id: '', order: temporaryOrder),
    );
    if (createdId == null || createdId.isEmpty) {
      throw StateError('La copie de l’étape n’a pas pu être créée.');
    }

    ordered.insert(index + 1, _copyStep(step, id: createdId));
    final normalized = <BudgetAllocationStep>[
      for (var position = 0; position < ordered.length; position++)
        _copyStep(ordered[position], order: position + 1),
    ];
    await reorderSteps(normalized);
    return createdId;
  }

  /// Uses a harmless offset first so the unique (version, step_order)
  /// constraint is respected while all positions are normalized to 1..N.
  Future<void> reorderSteps(List<BudgetAllocationStep> steps) async {
    const offset = 1000000;
    final normalized = normalizeStepOrders(steps);
    for (final step in normalized) {
      await gateway.update(
        'budget_scenario_steps',
        {'step_order': step.order + offset},
        {'id': step.id, 'household_id': householdId},
      );
    }
    for (final step in normalized) {
      await gateway.update(
        'budget_scenario_steps',
        {'step_order': step.order},
        {'id': step.id, 'household_id': householdId},
      );
    }
  }

  Future<void> persistRun(BudgetAllocationRun run) async {
    if (run.status != BudgetAllocationRunStatus.simulated) {
      throw StateError('Only a simulation can be saved.');
    }
    await gateway.rpc('save_budget_allocation_run_with_contributions', {
      'p_household_id': householdId,
      'p_run_id': run.id,
      'p_budget_period_id': run.periodId,
      'p_scenario_id': run.scenarioId,
      'p_available_resources': _money(run.availableResourcesCents),
      'p_calculated_total': _money(run.calculatedTotalCents),
      'p_remaining_unallocated': _money(run.remainingUnallocatedCents),
      'p_summary': {
        'member_contributions': run.memberContributions
            .map(
              (member) => {
                'member_user_id': member.memberUserId,
                'eligible_income': _money(member.eligibleIncomeCents),
                'direct_charges': _money(member.directChargesCents),
                'raw_capacity': _money(member.rawCapacityCents),
                'contribution_capacity': _money(
                  member.contributionCapacityCents,
                ),
                'auto_share': member.autoShare,
              },
            )
            .toList(growable: false),
        'warnings': run.warnings,
      },
      'p_lines': run.lines
          .map(
            (line) => <String, Object?>{
              'envelope_id': line.envelopeId,
              'previous_balance': _money(line.previousBalanceCents),
              'rollover_amount': _money(line.rolloverCents),
              'planned_allocation': _money(line.plannedAllocationCents),
              'resulting_available': _money(line.resultingAvailableCents),
              'priority': line.priority,
              'warning': line.warning,
              'contribution': line.contributions.map(
                (memberId, cents) => MapEntry(memberId, _money(cents)),
              ),
              'funding_source': line.fundingSourcePreference == null
                  ? null
                  : {'preference': line.fundingSourcePreference},
            },
          )
          .toList(growable: false),
    });
  }

  /// Persists the monthly programmable snapshot through the single 080006 RPC.
  /// It deliberately does not create FinancialEvents or envelope movements.
  Future<void> persistProgrammableRun({
    required BudgetAllocationRun run,
    required String scenarioVersionId,
    required Map<String, Object?> snapshot,
  }) async {
    if (run.status != BudgetAllocationRunStatus.simulated) {
      throw StateError('Only a simulation can be saved.');
    }
    await gateway.rpc('save_programmable_budget_run', {
      'p_household_id': householdId,
      'p_run_id': run.id,
      'p_budget_period_id': run.periodId,
      'p_scenario_id': run.scenarioId,
      'p_scenario_version_id': scenarioVersionId,
      'p_available_resources': _money(run.availableResourcesCents),
      'p_calculated_total': _money(run.calculatedTotalCents),
      'p_remaining_unallocated': _money(run.remainingUnallocatedCents),
      'p_summary': snapshot,
      'p_lines': run.lines
          .map(
            (line) => <String, Object?>{
              'envelope_id': line.envelopeId,
              'previous_balance': _money(line.previousBalanceCents),
              'rollover_amount': _money(line.rolloverCents),
              'planned_allocation': _money(line.plannedAllocationCents),
              'resulting_available': _money(line.resultingAvailableCents),
              'priority': line.priority,
              'warning': line.warning,
              'contribution': line.contributions.map(
                (memberId, cents) => MapEntry(memberId, _money(cents)),
              ),
              'funding_source': line.fundingSourcePreference == null
                  ? null
                  : {'preference': line.fundingSourcePreference},
            },
          )
          .toList(growable: false),
    });
  }

  Future<void> approveRun(String runId) => gateway.rpc(
    'approve_budget_allocation_run',
    {'p_household_id': householdId, 'p_run_id': runId},
  );

  Future<String> applyRun({
    required String runId,
    required String sourceAccountId,
    required String idempotencyKey,
  }) async {
    final result = await gateway.rpc('apply_budget_allocation_run', {
      'p_household_id': householdId,
      'p_run_id': runId,
      'p_source_account_id': sourceAccountId,
      'p_idempotency_key': idempotencyKey,
    });
    if (result is! String || result.isEmpty) {
      throw StateError('The budget application returned no identifier.');
    }
    return result;
  }

  /// Applies one immutable budget run through its canonical multi-account RPC.
  /// No Flutter-side financial writes are permitted here.
  Future<String> applyRunWithFunding({
    required String runId,
    required List<BudgetRunFunding> funding,
    required String idempotencyKey,
  }) async {
    if (funding.isEmpty || funding.any((line) => line.amountCents <= 0)) {
      throw StateError('Funding requires strictly positive amounts.');
    }
    final result = await gateway.rpc(
      'apply_budget_allocation_run_with_funding',
      {
        'p_household_id': householdId,
        'p_run_id': runId,
        'p_funding_lines': funding
            .map(
              (line) => <String, Object?>{
                'run_line_id': line.runLineId,
                'source_account_id': line.sourceAccountId,
                'envelope_id': line.envelopeId,
                'amount': _money(line.amountCents),
              },
            )
            .toList(growable: false),
        'p_idempotency_key': idempotencyKey,
      },
    );
    if (result is! String || result.isEmpty) {
      throw StateError('The budget application returned no identifier.');
    }
    return result;
  }

  static void _validateRule(BudgetScenarioRule rule) {
    if (rule.envelopeId.trim().isEmpty) {
      throw StateError('Choose an ordinary envelope.');
    }
    if ((rule.amountCents ?? 0) < 0 ||
        (rule.minimumCents ?? 0) < 0 ||
        (rule.maximumCents ?? 0) < 0) {
      throw StateError('Amounts cannot be negative.');
    }
    if (rule.method == BudgetAllocationMethod.fixed &&
        (rule.amountCents ?? 0) <= 0) {
      throw StateError('A fixed amount must be strictly positive.');
    }
    if (rule.method == BudgetAllocationMethod.percentage &&
        (rule.percentage == null ||
            rule.percentage! <= 0 ||
            rule.percentage! > 100)) {
      throw StateError('The percentage must be between 0 and 100.');
    }
    if (rule.minimumCents != null &&
        rule.maximumCents != null &&
        rule.minimumCents! > rule.maximumCents!) {
      throw StateError('The minimum cannot exceed the maximum.');
    }
    if ((rule.fundingMode == BudgetFundingMode.personalMember ||
            rule.fundingMode == BudgetFundingMode.exceptionalIncome) &&
        (rule.fundingMemberUserId == null ||
            rule.fundingMemberUserId!.trim().isEmpty)) {
      throw StateError('A personal charge requires a household member.');
    }
    if (rule.fundingMode == BudgetFundingMode.sharedCustom) {
      BudgetContributionCalculator.validateCustomPercentages(
        rule.fundingDefinition.map(
          (memberId, value) => MapEntry(memberId, (value as num).toDouble()),
        ),
      );
    }
    if (rule.fundingMode == BudgetFundingMode.fixedByMember) {
      if (rule.method != BudgetAllocationMethod.fixed ||
          rule.amountCents == null) {
        throw StateError('Fixed member contributions require a fixed rule.');
      }
      BudgetContributionCalculator.validateFixedContributions(
        rule.fundingDefinition.map(
          (memberId, value) => MapEntry(memberId, (value as num).toInt()),
        ),
        rule.amountCents!,
      );
    }
  }

  static String? _money(int? cents) =>
      cents == null ? null : (cents / 100).toStringAsFixed(2);

  static String _rollover(RolloverPolicy value) => switch (value) {
    RolloverPolicy.reportTotal => 'report_total',
    RolloverPolicy.reportDeficitOnly => 'report_deficit_only',
    RolloverPolicy.reset => 'reset',
    RolloverPolicy.capRollover => 'cap_rollover',
  };

  static String _contribution(ContributionRule value) => switch (value) {
    ContributionRule.proportionalIncome => 'proportional_income',
    ContributionRule.fixedPercentage => 'fixed_percentage',
    ContributionRule.memberOnly => 'custom',
    ContributionRule.custom => 'custom',
  };

  static String _fundingMode(BudgetFundingMode value) => switch (value) {
    BudgetFundingMode.personalMember => 'personal_member',
    BudgetFundingMode.sharedAuto => 'shared_auto',
    BudgetFundingMode.sharedCustom => 'shared_custom',
    BudgetFundingMode.fixedByMember => 'fixed_by_member',
    BudgetFundingMode.exceptionalIncome => 'exceptional_income',
  };

  static String _exceptionalTreatment(ExceptionalIncomeTreatment value) =>
      switch (value) {
        ExceptionalIncomeTreatment.excluded => 'excluded',
        ExceptionalIncomeTreatment.includedInSharedCapacity =>
          'included_in_shared_capacity',
        ExceptionalIncomeTreatment.directAllocation => 'direct_allocation',
      };

  static String? _exceptionalTreatmentNullable(
    ExceptionalIncomeTreatment? value,
  ) => value == null ? null : _exceptionalTreatment(value);

  static String _sourceType(BudgetSourceType value) => switch (value) {
    BudgetSourceType.memberRecurringIncome => 'member_recurring_income',
    BudgetSourceType.memberOtherRecurringIncome =>
      'member_other_recurring_income',
    BudgetSourceType.exceptionalIncome => 'exceptional_income',
    BudgetSourceType.commonCapacity => 'common_capacity',
    BudgetSourceType.availableSavings => 'available_savings',
    BudgetSourceType.other => 'other',
  };

  static String _contributionKey(ContributionKeyStrategy value) =>
      switch (value) {
        ContributionKeyStrategy.automaticRemainingCapacity =>
          'automatic_remaining_capacity',
        ContributionKeyStrategy.customPercentage => 'custom_percentage',
        ContributionKeyStrategy.fixedByMember => 'fixed_by_member',
        ContributionKeyStrategy.singleMember => 'single_member',
        ContributionKeyStrategy.equal => 'equal',
      };

  static String _insufficientFundsPolicy(BudgetInsufficientFundsPolicy value) =>
      switch (value) {
        BudgetInsufficientFundsPolicy.strict => 'strict',
        BudgetInsufficientFundsPolicy.cap => 'cap',
        BudgetInsufficientFundsPolicy.skip => 'skip',
        BudgetInsufficientFundsPolicy.proportional => 'proportional',
      };

  static BudgetSource _sourceFromRow(Map<String, Object?> row) => BudgetSource(
    id: row['id'] as String,
    scenarioVersionId: row['scenario_version_id'] as String,
    type: _sourceTypeFromSql(row['source_type'] as String),
    name: row['name'] as String,
    expectedCents: _cents(row['expected_amount']),
    memberUserId: row['member_user_id'] as String?,
    exceptionalTreatment: _exceptionalTreatmentFromSql(
      row['exceptional_treatment'] as String?,
    ),
    active: row['active'] is bool ? row['active'] as bool : true,
  );

  static BudgetAllocationStep _stepFromRow(Map<String, Object?> row) {
    final keyDefinition = _keyDefinitionFromRow(row['key_definition']);
    return BudgetAllocationStep(
      id: row['id'] as String,
      scenarioVersionId: row['scenario_version_id'] as String,
      order: row['step_order'] as int? ?? 0,
      groupName: row['group_name'] as String? ?? 'Sans groupe',
      sourceId: row['source_id'] as String,
      envelopeId: row['envelope_id'] as String,
      method: BudgetAllocationMethod.values.byName(
        row['allocation_method'] as String,
      ),
      contributionKey: _contributionKeyFromSql(
        row['contribution_key'] as String,
      ),
      insufficientFundsPolicy: _insufficientFundsPolicyFromSql(
        row['insufficient_funds_policy'] as String,
      ),
      amountCents: _centsNullable(row['amount']),
      percentage: double.tryParse(row['percentage']?.toString() ?? ''),
      memberUserId: row['member_user_id'] as String?,
      keyDefinition: keyDefinition,
      fundingSourcePreference: row['funding_source_preference'] as String?,
      active: row['active'] is bool ? row['active'] as bool : true,
    );
  }

  /// PostgREST normally gives JSON numbers as [num], but older stored steps
  /// can contain JSON strings. Canonicalise them at the persistence boundary
  /// so the domain always receives numeric contribution values.
  static Map<String, Object?> _keyDefinitionFromRow(Object? value) {
    if (value is! Map) return const {};
    return Map.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): switch (entry.value) {
          num numeric => numeric,
          String text
              when num.tryParse(text.trim().replaceAll(',', '.')) != null =>
            num.parse(text.trim().replaceAll(',', '.')),
          _ => entry.value,
        },
    });
  }

  static int _cents(Object? value) =>
      ((num.tryParse(value?.toString() ?? '0') ?? 0) * 100).round();
  static int? _centsNullable(Object? value) =>
      value == null ? null : _cents(value);
  static BudgetSourceType _sourceTypeFromSql(String value) => switch (value) {
    'member_recurring_income' => BudgetSourceType.memberRecurringIncome,
    'member_other_recurring_income' =>
      BudgetSourceType.memberOtherRecurringIncome,
    'exceptional_income' => BudgetSourceType.exceptionalIncome,
    'common_capacity' => BudgetSourceType.commonCapacity,
    'available_savings' => BudgetSourceType.availableSavings,
    _ => BudgetSourceType.other,
  };
  static ContributionKeyStrategy _contributionKeyFromSql(String value) =>
      switch (value) {
        'custom_percentage' => ContributionKeyStrategy.customPercentage,
        'fixed_by_member' => ContributionKeyStrategy.fixedByMember,
        'single_member' => ContributionKeyStrategy.singleMember,
        'equal' => ContributionKeyStrategy.equal,
        _ => ContributionKeyStrategy.automaticRemainingCapacity,
      };
  static BudgetInsufficientFundsPolicy _insufficientFundsPolicyFromSql(
    String value,
  ) => switch (value) {
    'cap' => BudgetInsufficientFundsPolicy.cap,
    'skip' => BudgetInsufficientFundsPolicy.skip,
    'proportional' => BudgetInsufficientFundsPolicy.proportional,
    _ => BudgetInsufficientFundsPolicy.strict,
  };
  static ExceptionalIncomeTreatment? _exceptionalTreatmentFromSql(
    String? value,
  ) => switch (value) {
    'included_in_shared_capacity' =>
      ExceptionalIncomeTreatment.includedInSharedCapacity,
    'direct_allocation' => ExceptionalIncomeTreatment.directAllocation,
    'excluded' => ExceptionalIncomeTreatment.excluded,
    _ => null,
  };
}

BudgetAllocationStep _copyStep(
  BudgetAllocationStep step, {
  String? id,
  int? order,
}) => BudgetAllocationStep(
  id: id ?? step.id,
  scenarioVersionId: step.scenarioVersionId,
  order: order ?? step.order,
  groupName: step.groupName,
  sourceId: step.sourceId,
  envelopeId: step.envelopeId,
  method: step.method,
  contributionKey: step.contributionKey,
  insufficientFundsPolicy: step.insufficientFundsPolicy,
  amountCents: step.amountCents,
  percentage: step.percentage,
  memberUserId: step.memberUserId,
  keyDefinition: step.keyDefinition,
  fundingSourcePreference: step.fundingSourcePreference,
  active: step.active,
);

/// Keeps the supplied sequence while assigning the only valid persisted
/// positions: 1, 2, ... N. Historical sparse orders are therefore compatible
/// without leaking their technical numbering into the interface.
List<BudgetAllocationStep> normalizeStepOrders(
  List<BudgetAllocationStep> orderedSteps,
) => List.unmodifiable([
  for (var index = 0; index < orderedSteps.length; index++)
    _copyStep(orderedSteps[index], order: index + 1),
]);

/// Moves one item in an already ordered programme and immediately restores the
/// canonical 1..N sequence. This stays at the repository boundary so every UI
/// control (arrows, drag-and-drop, and direct position) follows one rule.
List<BudgetAllocationStep> moveStepToPosition(
  List<BudgetAllocationStep> orderedSteps, {
  required int fromIndex,
  required int toIndex,
}) {
  if (fromIndex < 0 ||
      fromIndex >= orderedSteps.length ||
      toIndex < 0 ||
      toIndex >= orderedSteps.length) {
    throw RangeError('La position demandée est hors du programme.');
  }
  final moved = [...orderedSteps];
  final step = moved.removeAt(fromIndex);
  moved.insert(toIndex, step);
  return normalizeStepOrders(moved);
}
