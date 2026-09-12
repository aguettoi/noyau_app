import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/programmable_budget_engine.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';
import 'package:noyau_app/features/budget_intelligence/infrastructure/budget_supabase_repository.dart';

void main() {
  BudgetSupabaseRepository repository(_Gateway gateway) =>
      BudgetSupabaseRepository(
        gateway: gateway,
        householdId: 'home',
        userId: 'member',
      );
  const rule = BudgetScenarioRule(
    id: '',
    scenarioId: 'scenario',
    envelopeId: 'envelope',
    method: BudgetAllocationMethod.fixed,
    priority: 1,
    rolloverPolicy: RolloverPolicy.reportTotal,
    amountCents: 250000,
  );

  test(
    'persists a scenario and a fixed rule without financial writes',
    () async {
      final gateway = _Gateway();
      await repository(gateway).saveScenario(
        const BudgetScenario(id: '', householdId: 'home', name: 'Normal month'),
      );
      await repository(gateway).saveRule(rule);
      expect(gateway.inserts.map((item) => item.$1), [
        'budget_scenarios',
        'budget_scenario_rules',
      ]);
      expect(gateway.rpcs, isEmpty);
    },
  );

  test('refuses invalid business rules', () async {
    await expectLater(
      repository(_Gateway()).saveRule(
        const BudgetScenarioRule(
          id: '',
          scenarioId: 'scenario',
          envelopeId: 'envelope',
          method: BudgetAllocationMethod.percentage,
          priority: 1,
          rolloverPolicy: RolloverPolicy.reset,
          percentage: 101,
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'prépare une période mensuelle avec les bornes calendaires correctes',
    () async {
      final gateway = _Gateway();
      await repository(gateway).prepareMonthlyPeriod(DateTime(2028, 2, 17));
      expect(gateway.inserts.single.$1, 'budget_periods');
      expect(gateway.inserts.single.$2, containsPair('household_id', 'home'));
      expect(
        gateway.inserts.single.$2,
        containsPair('starts_on', '2028-02-01'),
      );
      expect(gateway.inserts.single.$2, containsPair('ends_on', '2028-02-29'));
      expect(gateway.rpcs, isEmpty);
    },
  );

  test('retrouve une période existante sans écriture financière', () async {
    final gateway = _Gateway()
      ..selectedRows = [
        {'id': 'period-existing'},
      ];
    final id = await repository(
      gateway,
    ).prepareMonthlyPeriod(DateTime(2026, 4));
    expect(id, 'period-existing');
    expect(gateway.inserts, isEmpty);
    expect(gateway.rpcs, isEmpty);
  });

  test(
    'calcule les fins de mois et reste idempotent sans écritures financières',
    () async {
      for (final sample in <(DateTime, String, String)>[
        (DateTime(2026, 1), '2026-01-01', '2026-01-31'),
        (DateTime(2026, 4), '2026-04-01', '2026-04-30'),
        (DateTime(2027, 2), '2027-02-01', '2027-02-28'),
        (DateTime(2028, 2), '2028-02-01', '2028-02-29'),
      ]) {
        final gateway = _Gateway();
        await repository(gateway).prepareMonthlyPeriod(sample.$1);
        final values = gateway.inserts.single.$2;
        expect(values['household_id'], 'home');
        expect(values['starts_on'], sample.$2);
        expect(values['ends_on'], sample.$3);
        expect(
          gateway.rpcs.where((item) => item.$1.contains('financial_event')),
          isEmpty,
        );
        expect(
          gateway.inserts.map((item) => item.$1),
          isNot(contains('financial_transactions')),
        );
        expect(
          gateway.inserts.map((item) => item.$1),
          isNot(contains('envelope_movements')),
        );
      }
    },
  );

  test(
    'persists a simulation snapshot atomically without a FinancialEvent',
    () async {
      final gateway = _Gateway();
      await repository(gateway).persistRun(
        const BudgetAllocationRun(
          id: 'run',
          householdId: 'home',
          periodId: 'period',
          scenarioId: 'scenario',
          availableResourcesCents: 100000,
          status: BudgetAllocationRunStatus.simulated,
          lines: [
            BudgetAllocationRunLine(
              envelopeId: 'envelope',
              previousBalanceCents: 0,
              rolloverCents: 0,
              plannedAllocationCents: 100000,
              resultingAvailableCents: 100000,
              priority: 1,
              state: BudgetEnvelopeState.available,
            ),
          ],
        ),
      );
      expect(gateway.inserts, isEmpty);
      expect(
        gateway.rpcs.single.$1,
        'save_budget_allocation_run_with_contributions',
      );
      final values = gateway.rpcs.single.$2;
      expect(values['p_lines'], hasLength(1));
      expect(values['p_calculated_total'], '1000.00');
      expect(values.values.join(), isNot(contains('allocate_budget_event')));
    },
  );

  test(
    'a persisted snapshot does not depend on later rule mutations',
    () async {
      final gateway = _Gateway();
      const run = BudgetAllocationRun(
        id: 'run',
        householdId: 'home',
        periodId: 'period',
        scenarioId: 'scenario',
        availableResourcesCents: 10000,
        status: BudgetAllocationRunStatus.simulated,
        lines: [
          BudgetAllocationRunLine(
            envelopeId: 'envelope',
            previousBalanceCents: -40000,
            rolloverCents: -40000,
            plannedAllocationCents: 250000,
            resultingAvailableCents: 210000,
            priority: 1,
            state: BudgetEnvelopeState.available,
          ),
        ],
      );
      await repository(gateway).persistRun(run);
      await repository(gateway).saveRule(rule);
      final snapshot = gateway.rpcs.first.$2['p_lines'] as List<Object?>;
      expect(
        (snapshot.single as Map<String, Object?>)['planned_allocation'],
        '2500.00',
      );
    },
  );

  test('approval and application use only the atomic RPCs', () async {
    final gateway = _Gateway();
    await repository(gateway).approveRun('run');
    await repository(
      gateway,
    ).applyRun(runId: 'run', sourceAccountId: 'account', idempotencyKey: 'key');
    expect(gateway.rpcs.map((item) => item.$1), [
      'approve_budget_allocation_run',
      'apply_budget_allocation_run',
    ]);
  });

  test(
    'multi-account application sends only the canonical atomic RPC',
    () async {
      final gateway = _Gateway();
      await repository(gateway).applyRunWithFunding(
        runId: 'run',
        idempotencyKey: 'key',
        funding: const [
          BudgetRunFunding(
            runLineId: 'line-food',
            sourceAccountId: 'account-current',
            envelopeId: 'food',
            amountCents: 200000,
          ),
          BudgetRunFunding(
            runLineId: 'line-savings',
            sourceAccountId: 'account-savings',
            envelopeId: 'savings',
            amountCents: 800000,
          ),
        ],
      );
      expect(
        gateway.rpcs.single.$1,
        'apply_budget_allocation_run_with_funding',
      );
      final values = gateway.rpcs.single.$2;
      expect(values['p_funding_lines'], hasLength(2));
      expect(values.values.join(), isNot(contains('financial_transactions')));
    },
  );

  test(
    'persists a programmable source and step without financial writes',
    () async {
      final gateway = _Gateway();
      final value = repository(gateway);
      await value.saveSource(
        const BudgetSource(
          id: '',
          scenarioVersionId: 'version',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'Revenu',
          expectedCents: 100000,
          memberUserId: 'member',
        ),
      );
      await value.saveStep(
        const BudgetAllocationStep(
          id: '',
          scenarioVersionId: 'version',
          order: 10,
          groupName: 'Charges fixes',
          sourceId: 'source',
          envelopeId: 'envelope',
          method: BudgetAllocationMethod.fixed,
          amountCents: 10000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      );
      expect(gateway.inserts.map((item) => item.$1), [
        'budget_scenario_sources',
        'budget_scenario_steps',
      ]);
      expect(gateway.rpcs, isEmpty);
    },
  );

  test(
    'creates the common-capacity anchor internally only when absent',
    () async {
      final gateway = _Gateway();
      gateway.insertResult = const {'id': 'common-internal'};
      final value = repository(gateway);

      final created = await value.ensureCommonCapacitySource('version');

      expect(created, 'common-internal');
      expect(gateway.inserts.single.$1, 'budget_scenario_sources');
      expect(gateway.inserts.single.$2['source_type'], 'common_capacity');
      expect(gateway.inserts.single.$2['expected_amount'], '0.00');
      expect(gateway.rpcs, isEmpty);

      gateway.selectedRows = const [
        {
          'id': 'existing-common',
          'scenario_version_id': 'version',
          'source_type': 'common_capacity',
          'name': 'Capacité commune technique',
          'expected_amount': '0.00',
          'active': true,
        },
      ];
      final existing = await value.ensureCommonCapacitySource('version');
      expect(existing, 'existing-common');
      expect(gateway.inserts, hasLength(1));
    },
  );

  test(
    'normalizes legacy text percentages when reloading a custom key',
    () async {
      final gateway = _Gateway()
        ..selectedRows = const [
          {
            'id': 'legacy-common',
            'scenario_version_id': 'version',
            'step_order': 40,
            'group_name': 'Charges communes',
            'source_id': 'common-anchor',
            'envelope_id': 'traite-maison',
            'allocation_method': 'fixed',
            'amount': '4000.00',
            'contribution_key': 'custom_percentage',
            'key_definition': {'member-alpha': '40', 'member-beta': '60'},
            'insufficient_funds_policy': 'strict',
            'active': true,
          },
        ];

      final step = (await repository(
        gateway,
      ).stepsForVersion('version')).single;

      expect(step.amountCents, 400000);
      expect(step.keyDefinition, {'member-alpha': 40, 'member-beta': 60});
    },
  );

  test(
    'persists, reloads and simulates shared custom funding from all members',
    () async {
      final gateway = _Gateway();
      final value = repository(gateway);
      gateway.selectedRows = const [
        {
          'id': 'salary-alpha',
          'scenario_version_id': 'version',
          'source_type': 'member_recurring_income',
          'name': 'Salaire Member Alpha',
          'expected_amount': '12800.00',
          'member_user_id': 'member-alpha',
          'active': true,
        },
        {
          'id': 'salary-beta',
          'scenario_version_id': 'version',
          'source_type': 'member_recurring_income',
          'name': 'Salaire Member Beta',
          'expected_amount': '15000.00',
          'member_user_id': 'member-beta',
          'active': true,
        },
      ];
      gateway.insertResult = const {'id': 'common-capacity'};
      final commonSourceId = await value.ensureCommonCapacitySource('version');

      const personalSteps = [
        BudgetAllocationStep(
          id: '',
          scenarioVersionId: 'version',
          order: 10,
          groupName: 'Personnel Alpha',
          sourceId: 'salary-alpha',
          envelopeId: 'a-1',
          method: BudgetAllocationMethod.fixed,
          amountCents: 50000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member-alpha',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: '',
          scenarioVersionId: 'version',
          order: 20,
          groupName: 'Personnel Alpha',
          sourceId: 'salary-alpha',
          envelopeId: 'a-2',
          method: BudgetAllocationMethod.fixed,
          amountCents: 100000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member-alpha',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: '',
          scenarioVersionId: 'version',
          order: 30,
          groupName: 'Personnel Beta',
          sourceId: 'salary-beta',
          envelopeId: 'b-1',
          method: BudgetAllocationMethod.fixed,
          amountCents: 70000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member-beta',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: '',
          scenarioVersionId: 'version',
          order: 35,
          groupName: 'Personnel Beta',
          sourceId: 'salary-beta',
          envelopeId: 'b-2',
          method: BudgetAllocationMethod.fixed,
          amountCents: 80000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member-beta',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ];
      for (final step in personalSteps) {
        gateway.insertResult = {'id': 'step-${step.order}'};
        await value.saveStep(step);
      }
      gateway.insertResult = const {'id': 'step-40'};
      await value.saveStep(
        BudgetAllocationStep(
          id: '',
          scenarioVersionId: 'version',
          order: 40,
          groupName: 'Charges communes',
          sourceId: commonSourceId,
          envelopeId: 'traite-maison',
          method: BudgetAllocationMethod.fixed,
          amountCents: 400000,
          contributionKey: ContributionKeyStrategy.customPercentage,
          keyDefinition: const {'member-alpha': 40.0, 'member-beta': 60.0},
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      );

      final persistedCommon = gateway.inserts.last.$2;
      expect(persistedCommon['scenario_version_id'], 'version');
      expect(persistedCommon['step_order'], 40);
      expect(persistedCommon['source_id'], 'common-capacity');
      expect(persistedCommon['envelope_id'], 'traite-maison');
      expect(persistedCommon['allocation_method'], 'fixed');
      expect(persistedCommon['amount'], '4000.00');
      expect(persistedCommon['contribution_key'], 'custom_percentage');
      expect(persistedCommon['key_definition'], {
        'member-alpha': 40.0,
        'member-beta': 60.0,
      });
      expect(persistedCommon['insufficient_funds_policy'], 'strict');
      expect(persistedCommon['active'], isTrue);

      final insertedSources = gateway.inserts
          .where((entry) => entry.$1 == 'budget_scenario_sources')
          .map(
            (entry) => <String, Object?>{...entry.$2, 'id': 'common-capacity'},
          )
          .toList();
      gateway.selectedRows = [
        const {
          'id': 'salary-alpha',
          'scenario_version_id': 'version',
          'source_type': 'member_recurring_income',
          'name': 'Salaire Member Alpha',
          'expected_amount': '12800.00',
          'member_user_id': 'member-alpha',
          'active': true,
        },
        const {
          'id': 'salary-beta',
          'scenario_version_id': 'version',
          'source_type': 'member_recurring_income',
          'name': 'Salaire Member Beta',
          'expected_amount': '15000.00',
          'member_user_id': 'member-beta',
          'active': true,
        },
        ...insertedSources,
      ];
      final reloadedSources = await value.sourcesForVersion('version');
      gateway.selectedRows = gateway.inserts
          .where((entry) => entry.$1 == 'budget_scenario_steps')
          .map(
            (entry) => <String, Object?>{
              ...entry.$2,
              'id': entry.$2['step_order'] == 40
                  ? 'step-40'
                  : 'step-${entry.$2['step_order']}',
            },
          )
          .toList();
      final reloadedSteps = await value.stepsForVersion('version');
      final commonStep = reloadedSteps.singleWhere(
        (step) => step.groupName == 'Charges communes',
      );

      expect(commonStep.sourceId, 'common-capacity');
      expect(commonStep.amountCents, 400000);
      expect(commonStep.keyDefinition, {
        'member-alpha': 40.0,
        'member-beta': 60.0,
      });

      final result = const ProgrammableBudgetEngine().simulate(
        sources: reloadedSources,
        steps: reloadedSteps,
        memberIds: const ['member-alpha', 'member-beta'],
      );
      final simulatedCommon = result.stepResults.singleWhere(
        (step) => step.step.groupName == 'Charges communes',
      );
      expect(result.isSimulable, isTrue);
      expect(simulatedCommon.requestedCents, 400000);
      expect(simulatedCommon.allocatedCents, 400000);
      expect(simulatedCommon.memberContributions, {
        'member-alpha': 160000,
        'member-beta': 240000,
      });
      expect(result.memberRemainingCents, {
        'member-alpha': 970000,
        'member-beta': 1110000,
      });
      expect(result.remainingCents, 2080000);
      expect(gateway.rpcs, isEmpty);
    },
  );

  test(
    'persists the monthly programmable snapshot through one RPC only',
    () async {
      final gateway = _Gateway();
      await repository(gateway).persistProgrammableRun(
        scenarioVersionId: 'version',
        snapshot: const {'monthly_snapshot': true, 'warnings': []},
        run: const BudgetAllocationRun(
          id: 'run',
          householdId: 'home',
          periodId: 'period',
          scenarioId: 'scenario',
          availableResourcesCents: 10000,
          status: BudgetAllocationRunStatus.simulated,
          lines: [
            BudgetAllocationRunLine(
              envelopeId: 'envelope',
              previousBalanceCents: 0,
              rolloverCents: 0,
              plannedAllocationCents: 10000,
              resultingAvailableCents: 10000,
              priority: 1,
              state: BudgetEnvelopeState.available,
            ),
          ],
        ),
      );
      expect(gateway.rpcs.single.$1, 'save_programmable_budget_run');
      expect(gateway.rpcs.single.$2['p_scenario_version_id'], 'version');
      expect(gateway.inserts, isEmpty);
    },
  );

  test(
    'reorders steps through non-conflicting intermediate positions',
    () async {
      final gateway = _Gateway();
      await repository(gateway).reorderSteps(const [
        BudgetAllocationStep(
          id: 'a',
          scenarioVersionId: 'version',
          order: 20,
          groupName: 'A',
          sourceId: 'source',
          envelopeId: 'envelope',
          method: BudgetAllocationMethod.fixed,
          amountCents: 100,
          contributionKey: ContributionKeyStrategy.equal,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: 'b',
          scenarioVersionId: 'version',
          order: 10,
          groupName: 'B',
          sourceId: 'source',
          envelopeId: 'envelope',
          method: BudgetAllocationMethod.fixed,
          amountCents: 100,
          contributionKey: ContributionKeyStrategy.equal,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ]);
      expect(gateway.updates.map((value) => value.$2['step_order']), [
        1000001,
        1000002,
        1,
        2,
      ]);
    },
  );

  test('normalizes legacy sparse orders without changing their sequence', () {
    final normalized = normalizeStepOrders(const [
      BudgetAllocationStep(
        id: 'legacy-first',
        scenarioVersionId: 'version',
        order: 0,
        groupName: 'Première',
        sourceId: 'source',
        envelopeId: 'envelope',
        method: BudgetAllocationMethod.fixed,
        amountCents: 100,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
      BudgetAllocationStep(
        id: 'legacy-second',
        scenarioVersionId: 'version',
        order: 10,
        groupName: 'Deuxième',
        sourceId: 'source',
        envelopeId: 'envelope',
        method: BudgetAllocationMethod.fixed,
        amountCents: 100,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
      BudgetAllocationStep(
        id: 'legacy-third',
        scenarioVersionId: 'version',
        order: 20,
        groupName: 'Troisième',
        sourceId: 'source',
        envelopeId: 'envelope',
        method: BudgetAllocationMethod.fixed,
        amountCents: 100,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
    ]);

    expect(normalized.map((step) => step.id), [
      'legacy-first',
      'legacy-second',
      'legacy-third',
    ]);
    expect(normalized.map((step) => step.order), [1, 2, 3]);
  });

  test('moves first, last and direct positions without duplicated orders', () {
    final source = List.generate(
      5,
      (index) => BudgetAllocationStep(
        id: 'step-${index + 1}',
        scenarioVersionId: 'version',
        order: index + 1,
        groupName: 'Étape ${index + 1}',
        sourceId: 'source',
        envelopeId: 'envelope',
        method: BudgetAllocationMethod.fixed,
        amountCents: 100,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
    );

    final lastToSecond = moveStepToPosition(source, fromIndex: 4, toIndex: 1);
    expect(lastToSecond.map((step) => step.id), [
      'step-1',
      'step-5',
      'step-2',
      'step-3',
      'step-4',
    ]);
    expect(lastToSecond.map((step) => step.order), [1, 2, 3, 4, 5]);

    final firstToLast = moveStepToPosition(source, fromIndex: 0, toIndex: 4);
    expect(firstToLast.map((step) => step.id), [
      'step-2',
      'step-3',
      'step-4',
      'step-5',
      'step-1',
    ]);
    expect(firstToLast.map((step) => step.order), [1, 2, 3, 4, 5]);
  });

  test('replaces the default scenario before enabling the next one', () async {
    final gateway = _Gateway()
      ..selectedRows = [
        {'id': 'previous-default'},
      ];
    await repository(
      gateway,
    ).setScenarioDefault(scenarioId: 'next-default', isDefault: true);
    expect(gateway.updates.map((value) => value.$2['is_default']), [
      false,
      true,
    ]);
  });

  test('supprime une source qui ne référence aucune étape', () async {
    final gateway = _Gateway();
    const source = BudgetSource(
      id: 'source-free',
      scenarioVersionId: 'version',
      type: BudgetSourceType.other,
      name: 'Source libre',
      expectedCents: 0,
    );

    await repository(gateway).deleteSource(source);

    expect(gateway.updates.single.$1, 'budget_scenario_sources');
    expect(gateway.updates.single.$2, const {'deleted': true});
    expect(gateway.updates.single.$3, {
      'id': 'source-free',
      'household_id': 'home',
    });
  });

  test(
    'refuse la suppression d’une source utilisée et identifie les étapes',
    () async {
      final gateway = _Gateway()
        ..selectedRows = [
          {
            'id': 'step-1',
            'scenario_version_id': 'version',
            'step_order': 10,
            'group_name': 'Charges communes',
            'source_id': 'source-used',
            'envelope_id': 'envelope',
            'allocation_method': 'fixed',
            'contribution_key': 'equal',
            'insufficient_funds_policy': 'strict',
            'amount': '100.00',
            'active': true,
          },
        ];
      const source = BudgetSource(
        id: 'source-used',
        scenarioVersionId: 'version',
        type: BudgetSourceType.other,
        name: 'Salaire',
        expectedCents: 0,
      );

      await expectLater(
        repository(gateway).deleteSource(source),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Charges communes'),
          ),
        ),
      );
      expect(gateway.updates, isEmpty);
    },
  );

  test('supprime une étape sans écriture financière', () async {
    final gateway = _Gateway();

    await repository(gateway).deleteStep('step-delete');

    expect(gateway.updates.single.$1, 'budget_scenario_steps');
    expect(gateway.updates.single.$2, const {'deleted': true});
    expect(gateway.rpcs, isEmpty);
  });

  test(
    'duplique une étape juste après l’original et persiste son ordre',
    () async {
      final gateway = _Gateway()..insertResult = const {'id': 'step-copy'};
      const before = BudgetAllocationStep(
        id: 'before',
        scenarioVersionId: 'version',
        order: 10,
        groupName: 'Revenus',
        sourceId: 'source-a',
        envelopeId: 'envelope-a',
        method: BudgetAllocationMethod.fixed,
        amountCents: 50000,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member-a',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      );
      const original = BudgetAllocationStep(
        id: 'original',
        scenarioVersionId: 'version',
        order: 20,
        groupName: 'Charges fixes',
        sourceId: 'source-a',
        envelopeId: 'envelope-b',
        method: BudgetAllocationMethod.percentage,
        percentage: 25,
        contributionKey: ContributionKeyStrategy.customPercentage,
        keyDefinition: {'member-a': 0.6, 'member-b': 0.4},
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.cap,
        fundingSourcePreference: 'cash',
      );
      const after = BudgetAllocationStep(
        id: 'after',
        scenarioVersionId: 'version',
        order: 30,
        groupName: 'Épargne',
        sourceId: 'source-a',
        envelopeId: 'envelope-c',
        method: BudgetAllocationMethod.residual,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.skip,
      );

      final createdId = await repository(gateway).duplicateStep(
        step: original,
        orderedSteps: const [before, original, after],
      );

      expect(createdId, 'step-copy');
      final copyValues = gateway.inserts.single.$2;
      expect(copyValues['group_name'], 'Charges fixes');
      expect(copyValues['source_id'], 'source-a');
      expect(copyValues['envelope_id'], 'envelope-b');
      expect(copyValues['allocation_method'], 'percentage');
      expect(copyValues['percentage'], 25.0);
      expect(copyValues['contribution_key'], 'custom_percentage');
      expect(copyValues['active'], true);

      final finalOrders = gateway.updates
          .skip(4)
          .map((update) => '${update.$3['id']}:${update.$2['step_order']}');
      expect(finalOrders, ['before:1', 'original:2', 'step-copy:3', 'after:4']);
      expect(gateway.rpcs, isEmpty);
    },
  );
}

class _Gateway implements BudgetSupabaseGateway {
  final inserts = <(String, Map<String, Object?>)>[];
  final rpcs = <(String, Map<String, Object?>)>[];
  final updates = <(String, Map<String, Object?>, Map<String, Object?>)>[];
  List<Map<String, Object?>> selectedRows = const [];
  Object? insertResult = const {'id': 'period-created'};

  @override
  Future<Object?> insert(String table, Map<String, Object?> values) async {
    inserts.add((table, values));
    return insertResult;
  }

  @override
  Future<Object?> upsert(String table, Map<String, Object?> values) async {
    inserts.add((table, values));
    return values;
  }

  @override
  Future<void> update(
    String table,
    Map<String, Object?> values,
    Map<String, Object?> filters,
  ) async {
    updates.add((table, values, filters));
  }

  @override
  Future<void> delete(String table, Map<String, Object?> filters) async {
    updates.add((table, const {'deleted': true}, filters));
  }

  @override
  Future<Object?> rpc(String function, Map<String, Object?> parameters) async {
    rpcs.add((function, parameters));
    return 'run';
  }

  @override
  Future<List<Map<String, Object?>>> select(
    String table,
    Map<String, Object?> filters,
  ) async => selectedRows;
}
