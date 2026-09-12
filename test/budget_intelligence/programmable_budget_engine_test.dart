import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/programmable_budget_engine.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';

void main() {
  const engine = ProgrammableBudgetEngine();

  test('orders programmable steps and keeps residual last', () {
    final result = engine.simulate(
      sources: const [
        BudgetSource(
          id: 'salary-a',
          scenarioVersionId: 'v1',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'Revenu membre',
          expectedCents: 100000,
          memberUserId: 'member-a',
        ),
      ],
      steps: const [
        BudgetAllocationStep(
          id: 'saving',
          scenarioVersionId: 'v1',
          order: 90,
          groupName: 'Épargne',
          sourceId: 'salary-a',
          envelopeId: 'saving-envelope',
          method: BudgetAllocationMethod.residual,
          contributionKey: ContributionKeyStrategy.automaticRemainingCapacity,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: 'direct',
          scenarioVersionId: 'v1',
          order: 10,
          groupName: 'Obligations',
          sourceId: 'salary-a',
          envelopeId: 'rent-envelope',
          method: BudgetAllocationMethod.fixed,
          amountCents: 40000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member-a',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ],
    );
    expect(result.allocations.map((item) => item.stepId), ['direct', 'saving']);
    expect(result.allocations.last.allocatedCents, 60000);
    expect(result.remainingCents, 0);
  });

  test('caps an insufficient allocation without a financial write', () {
    final result = engine.simulate(
      sources: const [
        BudgetSource(
          id: 'source',
          scenarioVersionId: 'v',
          type: BudgetSourceType.other,
          name: 'Source',
          expectedCents: 10000,
        ),
      ],
      steps: const [
        BudgetAllocationStep(
          id: 'step',
          scenarioVersionId: 'v',
          order: 1,
          groupName: 'Test',
          sourceId: 'source',
          envelopeId: 'envelope',
          method: BudgetAllocationMethod.fixed,
          amountCents: 20000,
          contributionKey: ContributionKeyStrategy.equal,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.cap,
        ),
      ],
    );
    expect(result.allocations.single.allocatedCents, 10000);
    expect(result.warnings, isNotEmpty);
  });

  test('supports percentage and every insufficient-funds policy', () {
    const source = BudgetSource(
      id: 'source',
      scenarioVersionId: 'v',
      type: BudgetSourceType.other,
      name: 'Source',
      expectedCents: 10000,
    );
    BudgetAllocationStep step(BudgetInsufficientFundsPolicy policy) =>
        BudgetAllocationStep(
          id: policy.name,
          scenarioVersionId: 'v',
          order: 1,
          groupName: 'Test',
          sourceId: 'source',
          envelopeId: 'envelope',
          method: BudgetAllocationMethod.percentage,
          percentage: 150,
          contributionKey: ContributionKeyStrategy.equal,
          insufficientFundsPolicy: policy,
        );
    expect(
      engine
          .simulate(
            sources: const [source],
            steps: [step(BudgetInsufficientFundsPolicy.strict)],
          )
          .allocations
          .single
          .allocatedCents,
      0,
    );
    expect(
      engine
          .simulate(
            sources: const [source],
            steps: [step(BudgetInsufficientFundsPolicy.cap)],
          )
          .allocations
          .single
          .allocatedCents,
      10000,
    );
    expect(
      engine
          .simulate(
            sources: const [source],
            steps: [step(BudgetInsufficientFundsPolicy.skip)],
          )
          .allocations
          .single
          .allocatedCents,
      0,
    );
    expect(
      engine
          .simulate(
            sources: const [source],
            steps: [step(BudgetInsufficientFundsPolicy.proportional)],
          )
          .allocations
          .single
          .allocatedCents,
      10000,
    );
  });

  test('simulates independent source overrides without persistence', () {
    const sources = [
      BudgetSource(
        id: 'a',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire A',
        expectedCents: 10000,
        memberUserId: 'member-a',
      ),
      BudgetSource(
        id: 'b',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire B',
        expectedCents: 20000,
        memberUserId: 'member-b',
      ),
    ];
    final overridden = [
      const BudgetSource(
        id: 'a',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire A',
        expectedCents: 15000,
        memberUserId: 'member-a',
      ),
      sources[1],
    ];
    final result = engine.simulate(sources: overridden, steps: const []);
    expect(result.remainingCents, 35000);
    expect(sources[0].expectedCents, 10000);
    expect(sources[1].expectedCents, 20000);
  });

  test('explains three-member capacities and allocates an automatic key', () {
    final result = engine.simulate(
      sources: const [
        BudgetSource(
          id: 'income-a',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'A',
          expectedCents: 600000,
          memberUserId: 'a',
        ),
        BudgetSource(
          id: 'income-b',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'B',
          expectedCents: 300000,
          memberUserId: 'b',
        ),
        BudgetSource(
          id: 'income-c',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'C',
          expectedCents: 200000,
          memberUserId: 'c',
        ),
      ],
      memberIds: const ['a', 'b', 'c'],
      steps: const [
        BudgetAllocationStep(
          id: 'personal-a',
          scenarioVersionId: 'v',
          order: 10,
          groupName: 'Personnel',
          sourceId: 'income-a',
          envelopeId: 'rent',
          method: BudgetAllocationMethod.fixed,
          amountCents: 100000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'a',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: 'common',
          scenarioVersionId: 'v',
          order: 20,
          groupName: 'Commun',
          sourceId: 'income-a',
          envelopeId: 'food',
          method: BudgetAllocationMethod.fixed,
          amountCents: 200000,
          contributionKey: ContributionKeyStrategy.automaticRemainingCapacity,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ],
    );

    expect(result.householdContributionCapacityCents, 1000000);
    expect(result.memberCapacities.map((item) => item.rawCapacityCents), [
      500000,
      300000,
      200000,
    ]);
    expect(result.memberCapacities.map((item) => item.autoShare), [
      0.5,
      0.3,
      0.2,
    ]);
    expect(result.allocations.last.memberContributions, {
      'a': 100000,
      'b': 60000,
      'c': 40000,
    });
  });

  test(
    'excludes negative capacities and avoids an automatic-key division by zero',
    () {
      final onePositive = engine.simulate(
        sources: const [
          BudgetSource(
            id: 'income-a',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'A',
            expectedCents: 500000,
            memberUserId: 'a',
          ),
          BudgetSource(
            id: 'income-b',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'B',
            expectedCents: 1000000,
            memberUserId: 'b',
          ),
        ],
        steps: const [
          BudgetAllocationStep(
            id: 'personal-a',
            scenarioVersionId: 'v',
            order: 10,
            groupName: 'Personnel',
            sourceId: 'income-a',
            envelopeId: 'a',
            method: BudgetAllocationMethod.fixed,
            amountCents: 600000,
            contributionKey: ContributionKeyStrategy.singleMember,
            memberUserId: 'a',
            insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
          ),
          BudgetAllocationStep(
            id: 'personal-b',
            scenarioVersionId: 'v',
            order: 20,
            groupName: 'Personnel',
            sourceId: 'income-b',
            envelopeId: 'b',
            method: BudgetAllocationMethod.fixed,
            amountCents: 400000,
            contributionKey: ContributionKeyStrategy.singleMember,
            memberUserId: 'b',
            insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
          ),
          BudgetAllocationStep(
            id: 'common',
            scenarioVersionId: 'v',
            order: 30,
            groupName: 'Commun',
            sourceId: 'income-b',
            envelopeId: 'common',
            method: BudgetAllocationMethod.fixed,
            amountCents: 200000,
            contributionKey: ContributionKeyStrategy.automaticRemainingCapacity,
            insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
          ),
        ],
      );
      expect(onePositive.memberCapacities[0].rawCapacityCents, -100000);
      expect(onePositive.memberCapacities[0].contributionCapacityCents, 0);
      expect(onePositive.memberCapacities[0].autoShare, 0);
      expect(onePositive.memberCapacities[1].autoShare, 1);
      expect(onePositive.allocations.last.memberContributions, {'b': 200000});

      final noCapacity = engine.simulate(
        sources: const [
          BudgetSource(
            id: 'a',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'A',
            expectedCents: 10000,
            memberUserId: 'a',
          ),
          BudgetSource(
            id: 'b',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'B',
            expectedCents: 10000,
            memberUserId: 'b',
          ),
        ],
        steps: const [
          BudgetAllocationStep(
            id: 'a-charge',
            scenarioVersionId: 'v',
            order: 1,
            groupName: 'Personnel',
            sourceId: 'a',
            envelopeId: 'a',
            method: BudgetAllocationMethod.fixed,
            amountCents: 10000,
            contributionKey: ContributionKeyStrategy.singleMember,
            memberUserId: 'a',
            insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
          ),
          BudgetAllocationStep(
            id: 'b-charge',
            scenarioVersionId: 'v',
            order: 2,
            groupName: 'Personnel',
            sourceId: 'b',
            envelopeId: 'b',
            method: BudgetAllocationMethod.fixed,
            amountCents: 10000,
            contributionKey: ContributionKeyStrategy.singleMember,
            memberUserId: 'b',
            insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
          ),
          BudgetAllocationStep(
            id: 'common',
            scenarioVersionId: 'v',
            order: 3,
            groupName: 'Commun',
            sourceId: 'a',
            envelopeId: 'common',
            method: BudgetAllocationMethod.fixed,
            amountCents: 0,
            contributionKey: ContributionKeyStrategy.automaticRemainingCapacity,
            insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
          ),
        ],
      );
      expect(noCapacity.householdContributionCapacityCents, 0);
      expect(noCapacity.hasAutomaticContributionCapacity, isFalse);
      expect(noCapacity.memberCapacities.map((item) => item.autoShare), [0, 0]);
    },
  );

  test(
    'uses overridden member resources for automatic shares without mutation',
    () {
      const original = [
        BudgetSource(
          id: 'a',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'A',
          expectedCents: 500000,
          memberUserId: 'a',
        ),
        BudgetSource(
          id: 'b',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'B',
          expectedCents: 500000,
          memberUserId: 'b',
        ),
      ];
      final result = engine.simulate(
        sources: [
          const BudgetSource(
            id: 'a',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'A',
            expectedCents: 750000,
            memberUserId: 'a',
          ),
          original[1],
        ],
        steps: const [],
      );
      expect(result.memberCapacities.map((item) => item.autoShare), [0.6, 0.4]);
      expect(original[0].expectedCents, 500000);
    },
  );

  test('returns ordered details for fixed, percentage and residual', () {
    const source = BudgetSource(
      id: 'income',
      scenarioVersionId: 'v',
      type: BudgetSourceType.memberRecurringIncome,
      name: 'Salaire',
      expectedCents: 100000,
      memberUserId: 'a',
    );
    final result = engine.simulate(
      sources: const [source],
      memberIds: const ['a'],
      steps: const [
        BudgetAllocationStep(
          id: 'residual',
          scenarioVersionId: 'v',
          order: 30,
          groupName: 'Épargne',
          sourceId: 'income',
          envelopeId: 'saving',
          method: BudgetAllocationMethod.residual,
          contributionKey: ContributionKeyStrategy.equal,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: 'percentage',
          scenarioVersionId: 'v',
          order: 20,
          groupName: 'Loisirs',
          sourceId: 'income',
          envelopeId: 'travel',
          method: BudgetAllocationMethod.percentage,
          percentage: 10,
          contributionKey: ContributionKeyStrategy.equal,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: 'fixed',
          scenarioVersionId: 'v',
          order: 10,
          groupName: 'Courses',
          sourceId: 'income',
          envelopeId: 'food',
          method: BudgetAllocationMethod.fixed,
          amountCents: 20000,
          contributionKey: ContributionKeyStrategy.equal,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ],
    );
    expect(result.stepResults.map((item) => item.step.id), [
      'fixed',
      'percentage',
      'residual',
    ]);
    expect(result.stepResults[0].remainingAfterCents, 80000);
    expect(result.stepResults[1].percentageBaseCents, 80000);
    expect(result.stepResults[1].requestedCents, 8000);
    expect(result.stepResults[2].allocatedCents, 72000);
    expect(result.isSimulable, isTrue);
  });

  test('explains insufficient-funds policies and inactive steps', () {
    const source = BudgetSource(
      id: 'income',
      scenarioVersionId: 'v',
      type: BudgetSourceType.other,
      name: 'Source',
      expectedCents: 10000,
    );
    BudgetAllocationStep step(
      String id,
      BudgetInsufficientFundsPolicy policy, {
      bool active = true,
    }) => BudgetAllocationStep(
      id: id,
      scenarioVersionId: 'v',
      order: 1,
      groupName: 'Test',
      sourceId: 'income',
      envelopeId: 'target',
      method: BudgetAllocationMethod.fixed,
      amountCents: 20000,
      contributionKey: ContributionKeyStrategy.equal,
      insufficientFundsPolicy: policy,
      active: active,
    );
    expect(
      engine
          .simulate(
            sources: const [source],
            steps: [step('strict', BudgetInsufficientFundsPolicy.strict)],
          )
          .stepResults
          .single
          .status,
      ProgrammableBudgetStepStatus.blocked,
    );
    final cap = engine
        .simulate(
          sources: const [source],
          steps: [step('cap', BudgetInsufficientFundsPolicy.cap)],
        )
        .stepResults
        .single;
    expect(cap.status, ProgrammableBudgetStepStatus.partiallyExecuted);
    expect(cap.reductionCoefficient, .5);
    expect(
      engine
          .simulate(
            sources: const [source],
            steps: [step('skip', BudgetInsufficientFundsPolicy.skip)],
          )
          .stepResults
          .single
          .status,
      ProgrammableBudgetStepStatus.skipped,
    );
    expect(
      engine
          .simulate(
            sources: const [source],
            steps: [
              step('proportional', BudgetInsufficientFundsPolicy.proportional),
            ],
          )
          .stepResults
          .single
          .status,
      ProgrammableBudgetStepStatus.partiallyExecuted,
    );
    expect(
      engine
          .simulate(
            sources: const [source],
            steps: [
              step(
                'inactive',
                BudgetInsufficientFundsPolicy.strict,
                active: false,
              ),
            ],
          )
          .stepResults
          .single
          .status,
      ProgrammableBudgetStepStatus.inactive,
    );
  });

  test('details contribution keys and configuration blockers', () {
    const sources = [
      BudgetSource(
        id: 'a',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'A',
        expectedCents: 500000,
        memberUserId: 'a',
      ),
      BudgetSource(
        id: 'b',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'B',
        expectedCents: 500000,
        memberUserId: 'b',
      ),
    ];
    final result = engine.simulate(
      sources: sources,
      memberIds: const ['a', 'b'],
      steps: const [
        BudgetAllocationStep(
          id: 'equal',
          scenarioVersionId: 'v',
          order: 1,
          groupName: 'Equal',
          sourceId: 'a',
          envelopeId: 'e',
          method: BudgetAllocationMethod.fixed,
          amountCents: 10000,
          contributionKey: ContributionKeyStrategy.equal,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: 'custom',
          scenarioVersionId: 'v',
          order: 2,
          groupName: 'Custom',
          sourceId: 'a',
          envelopeId: 'c',
          method: BudgetAllocationMethod.fixed,
          amountCents: 10000,
          contributionKey: ContributionKeyStrategy.customPercentage,
          keyDefinition: {'a': 60, 'b': 40},
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
        BudgetAllocationStep(
          id: 'fixed',
          scenarioVersionId: 'v',
          order: 3,
          groupName: 'Fixed',
          sourceId: 'a',
          envelopeId: 'f',
          method: BudgetAllocationMethod.fixed,
          amountCents: 10000,
          contributionKey: ContributionKeyStrategy.fixedByMember,
          keyDefinition: {'a': 7000, 'b': 3000},
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ],
    );
    expect(result.stepResults[0].memberContributions, {'a': 5000, 'b': 5000});
    expect(result.stepResults[1].memberContributions, {'a': 6000, 'b': 4000});
    expect(result.stepResults[2].memberContributions, {'a': 7000, 'b': 3000});
    final invalid = engine.simulate(
      sources: sources,
      steps: const [
        BudgetAllocationStep(
          id: 'invalid',
          scenarioVersionId: 'v',
          order: 1,
          groupName: 'Invalid',
          sourceId: 'missing',
          envelopeId: '',
          method: BudgetAllocationMethod.fixed,
          amountCents: 10000,
          contributionKey: ContributionKeyStrategy.customPercentage,
          keyDefinition: {'a': 80},
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ],
    );
    expect(invalid.isSimulable, isFalse);
    expect(invalid.stepResults.single.requestedCents, 10000);
    expect(
      invalid.diagnostics.map((item) => item.code),
      containsAll(['destination_missing', 'custom_key_invalid']),
    );
  });

  test('keeps a missing source as a blocker for a personal charge', () {
    final result = engine.simulate(
      sources: const [],
      memberIds: const ['member-a'],
      steps: const [
        BudgetAllocationStep(
          id: 'personal-missing-source',
          scenarioVersionId: 'v',
          order: 1,
          groupName: 'Personnel',
          sourceId: 'missing',
          envelopeId: 'envelope',
          method: BudgetAllocationMethod.fixed,
          amountCents: 10000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member-a',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ],
    );

    expect(result.isSimulable, isFalse);
    expect(
      result.diagnostics.map((item) => item.code),
      contains('source_missing'),
    );
  });

  test('keeps the strict 100 percent custom-key guard for injected values', () {
    const sources = [
      BudgetSource(
        id: 'income-a',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Alpha',
        expectedCents: 500000,
        memberUserId: 'a',
      ),
      BudgetSource(
        id: 'income-b',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Beta',
        expectedCents: 500000,
        memberUserId: 'b',
      ),
    ];
    const base = BudgetAllocationStep(
      id: 'shared',
      scenarioVersionId: 'v',
      order: 40,
      groupName: 'Commun',
      sourceId: 'technical',
      envelopeId: 'envelope',
      method: BudgetAllocationMethod.fixed,
      amountCents: 400000,
      contributionKey: ContributionKeyStrategy.customPercentage,
      insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
    );

    for (final invalid in const [
      {'a': 40.0, 'b': 59.99},
      {'a': 40.0, 'b': 60.01},
      {'a': 0.0, 'b': 0.0},
    ]) {
      final result = engine.simulate(
        sources: sources,
        steps: [
          BudgetAllocationStep(
            id: base.id,
            scenarioVersionId: base.scenarioVersionId,
            order: base.order,
            groupName: base.groupName,
            sourceId: base.sourceId,
            envelopeId: base.envelopeId,
            method: base.method,
            amountCents: base.amountCents,
            contributionKey: base.contributionKey,
            insufficientFundsPolicy: base.insufficientFundsPolicy,
            keyDefinition: invalid,
          ),
        ],
        memberIds: const ['a', 'b'],
      );
      expect(result.isSimulable, isFalse);
      expect(
        result.diagnostics.map((item) => item.code),
        contains('custom_key_invalid'),
      );
    }

    final valid = engine.simulate(
      sources: sources,
      steps: [
        BudgetAllocationStep(
          id: base.id,
          scenarioVersionId: base.scenarioVersionId,
          order: base.order,
          groupName: base.groupName,
          sourceId: base.sourceId,
          envelopeId: base.envelopeId,
          method: base.method,
          amountCents: base.amountCents,
          contributionKey: base.contributionKey,
          insufficientFundsPolicy: base.insufficientFundsPolicy,
          keyDefinition: const {'a': 100.0, 'b': 0.0},
        ),
      ],
      memberIds: const ['a', 'b'],
    );
    expect(valid.isSimulable, isTrue);
  });

  test(
    'returns member summaries from the real multi-member simulation state',
    () {
      const sources = [
        BudgetSource(
          id: 'a-source',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'A',
          expectedCents: 1280000,
          memberUserId: 'a',
        ),
        BudgetSource(
          id: 'b-source',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'B',
          expectedCents: 1500000,
          memberUserId: 'b',
        ),
      ];
      BudgetAllocationStep step(
        int order,
        String source,
        String envelope,
        int amount,
        ContributionKeyStrategy key, {
        String? member,
        Map<String, Object?> definition = const {},
      }) => BudgetAllocationStep(
        id: '$order',
        scenarioVersionId: 'v',
        order: order,
        groupName: 'Test',
        sourceId: source,
        envelopeId: envelope,
        method: BudgetAllocationMethod.fixed,
        amountCents: amount,
        contributionKey: key,
        memberUserId: member,
        keyDefinition: definition,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      );
      final result = engine.simulate(
        sources: sources,
        memberIds: const ['a', 'b'],
        steps: [
          step(
            0,
            'a-source',
            'wifi',
            50000,
            ContributionKeyStrategy.singleMember,
            member: 'a',
          ),
          step(
            10,
            'a-source',
            'syndic',
            100000,
            ContributionKeyStrategy.singleMember,
            member: 'a',
          ),
          step(
            20,
            'b-source',
            'tsc',
            70000,
            ContributionKeyStrategy.singleMember,
            member: 'b',
          ),
          step(
            30,
            'b-source',
            'vidange',
            80000,
            ContributionKeyStrategy.singleMember,
            member: 'b',
          ),
          step(
            40,
            'technical',
            'maison',
            400000,
            ContributionKeyStrategy.customPercentage,
            definition: const {'a': 40.0, 'b': 60.0},
          ),
          step(
            50,
            'technical',
            'sorties',
            100000,
            ContributionKeyStrategy.automaticRemainingCapacity,
          ),
          step(
            60,
            'technical',
            'nourriture',
            150000,
            ContributionKeyStrategy.fixedByMember,
            definition: const {'a': 60000, 'b': 90000},
          ),
          step(
            70,
            'technical',
            'test-sandbox',
            3000000,
            ContributionKeyStrategy.customPercentage,
            definition: const {'a': 40.0, 'b': 60.0},
          ),
        ],
      );
      final summaries = {
        for (final summary in result.memberSummaries)
          summary.memberUserId: summary,
      };
      expect(summaries['a']!.initialResourcesCents, 1280000);
      expect(summaries['a']!.allocatedCents, 416635);
      expect(summaries['a']!.remainingCents, 863365);
      expect(summaries['b']!.initialResourcesCents, 1500000);
      expect(summaries['b']!.allocatedCents, 533365);
      expect(summaries['b']!.remainingCents, 966635);
      final blocked = result.stepResults.last;
      expect(blocked.requestedCents, 3000000);
      expect(blocked.availableBeforeCents, 1830000);
      expect(blocked.allocatedCents, 0);
      expect(blocked.remainingAfterCents, 1830000);
      expect(blocked.memberContributions, {'a': 0, 'b': 0});
      expect(blocked.status, ProgrammableBudgetStepStatus.blocked);
      expect(
        blocked.diagnostics.map((item) => item.code),
        contains('strict_insufficient_funds'),
      );
      expect(
        result.memberSummaries.fold<int>(
          0,
          (sum, item) => sum + item.remainingCents,
        ),
        result.remainingCents,
      );
      expect(
        result.memberSummaries.fold<int>(
          0,
          (sum, item) => sum + item.allocatedCents,
        ),
        result.allocatedCents,
      );
    },
  );

  test('blocks an automatic key when no member has positive capacity', () {
    final result = engine.simulate(
      sources: const [
        BudgetSource(
          id: 'a',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'A',
          expectedCents: 0,
          memberUserId: 'a',
        ),
        BudgetSource(
          id: 'common',
          scenarioVersionId: 'v',
          type: BudgetSourceType.commonCapacity,
          name: 'Commun',
          expectedCents: 10000,
        ),
      ],
      memberIds: const ['a'],
      steps: const [
        BudgetAllocationStep(
          id: 'common-step',
          scenarioVersionId: 'v',
          order: 1,
          groupName: 'Commun',
          sourceId: 'common',
          envelopeId: 'food',
          method: BudgetAllocationMethod.fixed,
          amountCents: 10000,
          contributionKey: ContributionKeyStrategy.automaticRemainingCapacity,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ],
    );
    expect(
      result.stepResults.single.status,
      ProgrammableBudgetStepStatus.blocked,
    );
    expect(
      result.diagnostics.map((item) => item.code),
      contains('automatic_key_unavailable'),
    );
    expect(result.isSimulable, isFalse);
  });

  test(
    'treats zero automatic capacity as a non-blocking proportional reduction',
    () {
      final result = engine.simulate(
        sources: const [
          BudgetSource(
            id: 'a',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'A',
            expectedCents: 0,
            memberUserId: 'a',
          ),
          BudgetSource(
            id: 'b',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'B',
            expectedCents: 0,
            memberUserId: 'b',
          ),
        ],
        memberIds: const ['a', 'b'],
        steps: const [
          BudgetAllocationStep(
            id: 'zero-capacity',
            scenarioVersionId: 'v',
            order: 10,
            groupName: 'Commun',
            sourceId: 'technical',
            envelopeId: 'food',
            method: BudgetAllocationMethod.fixed,
            amountCents: 10000,
            contributionKey: ContributionKeyStrategy.automaticRemainingCapacity,
            insufficientFundsPolicy: BudgetInsufficientFundsPolicy.proportional,
          ),
        ],
      );
      final step = result.stepResults.single;
      expect(step.requestedCents, 10000);
      expect(step.availableBeforeCents, 0);
      expect(step.allocatedCents, 0);
      expect(step.remainingAfterCents, 0);
      expect(step.status, ProgrammableBudgetStepStatus.skipped);
      expect(
        step.diagnostics.map((item) => item.code),
        contains('allocation_reduced'),
      );
      expect(
        step.diagnostics.map((item) => item.code),
        isNot(contains('automatic_key_unavailable')),
      );
      expect(result.isSimulable, isTrue);
    },
  );

  test('keeps a partial automatic proportional allocation simulable', () {
    final result = engine.simulate(
      sources: const [
        BudgetSource(
          id: 'a',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'A',
          expectedCents: 12568,
          memberUserId: 'a',
        ),
        BudgetSource(
          id: 'b',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'B',
          expectedCents: 20000,
          memberUserId: 'b',
        ),
      ],
      memberIds: const ['a', 'b'],
      steps: const [
        BudgetAllocationStep(
          id: 'partial-capacity',
          scenarioVersionId: 'v',
          order: 10,
          groupName: 'Commun',
          sourceId: 'technical',
          envelopeId: 'food',
          method: BudgetAllocationMethod.fixed,
          amountCents: 50000,
          contributionKey: ContributionKeyStrategy.automaticRemainingCapacity,
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.proportional,
        ),
      ],
    );
    final step = result.stepResults.single;
    expect(step.availableBeforeCents, 32568);
    expect(step.allocatedCents, 32568);
    expect(step.remainingAfterCents, 0);
    expect(step.status, ProgrammableBudgetStepStatus.partiallyExecuted);
    expect(
      step.memberContributions.values.fold<int>(0, (sum, value) => sum + value),
      step.allocatedCents,
    );
    expect(result.isSimulable, isTrue);
  });

  test('consumes only the selected member resources for a personal charge', () {
    final result = engine.simulate(
      sources: const [
        BudgetSource(
          id: 'a',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'A',
          expectedCents: 100000,
          memberUserId: 'a',
        ),
        BudgetSource(
          id: 'b',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'B',
          expectedCents: 100000,
          memberUserId: 'b',
        ),
      ],
      memberIds: const ['a', 'b'],
      steps: const [
        BudgetAllocationStep(
          id: 'personal-a',
          scenarioVersionId: 'v',
          order: 10,
          groupName: 'Personnel',
          sourceId: 'a',
          envelopeId: 'tsc',
          method: BudgetAllocationMethod.fixed,
          amountCents: 30000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'a',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      ],
    );
    expect(result.stepResults.single.memberContributions, {'a': 30000});
    expect(result.memberRemainingCents, {'a': 70000, 'b': 100000});
  });

  test(
    'splits common charges across members without using an individual source',
    () {
      const sources = [
        BudgetSource(
          id: 'salary-a',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'A',
          expectedCents: 800000,
          memberUserId: 'a',
        ),
        BudgetSource(
          id: 'salary-b',
          scenarioVersionId: 'v',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'B',
          expectedCents: 1200000,
          memberUserId: 'b',
        ),
        BudgetSource(
          id: 'common',
          scenarioVersionId: 'v',
          type: BudgetSourceType.commonCapacity,
          name: 'Capacité commune',
          expectedCents: 0,
        ),
      ];
      BudgetAllocationStep common({
        required String id,
        required ContributionKeyStrategy key,
        Map<String, Object?> definition = const {},
      }) => BudgetAllocationStep(
        id: id,
        scenarioVersionId: 'v',
        order: 10,
        groupName: 'Commun',
        sourceId: 'common',
        envelopeId: 'food',
        method: BudgetAllocationMethod.fixed,
        amountCents: 100000,
        contributionKey: key,
        keyDefinition: definition,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      );

      final custom = engine.simulate(
        sources: sources,
        memberIds: const ['a', 'b'],
        steps: [
          common(
            id: 'custom',
            key: ContributionKeyStrategy.customPercentage,
            definition: const {'a': 40, 'b': 60},
          ),
        ],
      );
      expect(custom.stepResults.single.memberContributions, {
        'a': 40000,
        'b': 60000,
      });
      expect(custom.memberRemainingCents, {'a': 760000, 'b': 1140000});

      final automatic = engine.simulate(
        sources: sources,
        memberIds: const ['a', 'b'],
        steps: [
          common(
            id: 'automatic',
            key: ContributionKeyStrategy.automaticRemainingCapacity,
          ),
        ],
      );
      expect(automatic.stepResults.single.memberContributions, {
        'a': 40000,
        'b': 60000,
      });

      final fixed = engine.simulate(
        sources: sources,
        memberIds: const ['a', 'b'],
        steps: [
          common(
            id: 'fixed',
            key: ContributionKeyStrategy.fixedByMember,
            definition: const {'a': 60000, 'b': 40000},
          ),
        ],
      );
      expect(fixed.stepResults.single.memberContributions, {
        'a': 60000,
        'b': 40000,
      });

      final equal = engine.simulate(
        sources: sources,
        memberIds: const ['a', 'b'],
        steps: [common(id: 'equal', key: ContributionKeyStrategy.equal)],
      );
      expect(equal.stepResults.single.memberContributions, {
        'a': 50000,
        'b': 50000,
      });
      expect(
        equal.stepResults.single.memberContributions.values.fold<int>(
          0,
          (sum, value) => sum + value,
        ),
        100000,
      );
    },
  );

  test(
    'a legacy individual source marker does not fund a common charge alone',
    () {
      final result = engine.simulate(
        sources: const [
          BudgetSource(
            id: 'salary-a',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'A',
            expectedCents: 800000,
            memberUserId: 'a',
          ),
          BudgetSource(
            id: 'salary-b',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: 'B',
            expectedCents: 1200000,
            memberUserId: 'b',
          ),
        ],
        memberIds: const ['a', 'b'],
        steps: const [
          BudgetAllocationStep(
            id: 'legacy-common',
            scenarioVersionId: 'v',
            order: 10,
            groupName: 'Commun',
            sourceId: 'salary-a',
            envelopeId: 'food',
            method: BudgetAllocationMethod.fixed,
            amountCents: 100000,
            contributionKey: ContributionKeyStrategy.customPercentage,
            keyDefinition: {'a': 40, 'b': 60},
            insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
          ),
        ],
      );

      expect(result.stepResults.single.memberContributions, {
        'a': 40000,
        'b': 60000,
      });
      expect(result.memberRemainingCents, {'a': 760000, 'b': 1140000});
    },
  );

  test('derives common capacity from 12800 and 15000 member incomes', () {
    const sources = [
      BudgetSource(
        id: 'salary-a',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Member Alpha',
        expectedCents: 1280000,
        memberUserId: 'member-a',
      ),
      BudgetSource(
        id: 'salary-b',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Member Beta',
        expectedCents: 1500000,
        memberUserId: 'member-b',
      ),
    ];
    const personal = [
      BudgetAllocationStep(
        id: 'personal-a',
        scenarioVersionId: 'v',
        order: 10,
        groupName: 'Personnel',
        sourceId: 'salary-a',
        envelopeId: 'a',
        method: BudgetAllocationMethod.fixed,
        amountCents: 150000,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member-a',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
      BudgetAllocationStep(
        id: 'personal-b',
        scenarioVersionId: 'v',
        order: 20,
        groupName: 'Personnel',
        sourceId: 'salary-b',
        envelopeId: 'b',
        method: BudgetAllocationMethod.fixed,
        amountCents: 150000,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member-b',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
    ];
    BudgetAllocationStep common(
      String id,
      ContributionKeyStrategy key, {
      Map<String, Object?> definition = const {},
    }) => BudgetAllocationStep(
      id: id,
      scenarioVersionId: 'v',
      order: 30,
      groupName: 'Commun',
      // source_id remains a non-null relational anchor, not the funder.
      sourceId: 'salary-a',
      envelopeId: 'common',
      method: BudgetAllocationMethod.fixed,
      amountCents: 100000,
      contributionKey: key,
      keyDefinition: definition,
      insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
    );

    final custom = engine.simulate(
      sources: sources,
      memberIds: const ['member-a', 'member-b'],
      steps: [
        ...personal,
        common(
          'custom',
          ContributionKeyStrategy.customPercentage,
          definition: const {'member-a': 40, 'member-b': 60},
        ),
      ],
    );
    expect(custom.stepResults.last.memberContributions, {
      'member-a': 40000,
      'member-b': 60000,
    });
    expect(custom.memberRemainingCents, {
      'member-a': 1090000,
      'member-b': 1290000,
    });

    final automatic = engine.simulate(
      sources: sources,
      memberIds: const ['member-a', 'member-b'],
      steps: [
        ...personal,
        common('automatic', ContributionKeyStrategy.automaticRemainingCapacity),
      ],
    );
    expect(automatic.stepResults.last.memberContributions, {
      'member-a': 45565,
      'member-b': 54435,
    });
    expect(
      automatic.stepResults.last.memberContributions.values.fold<int>(
        0,
        (sum, value) => sum + value,
      ),
      100000,
    );
  });

  test('conserves every centime for proportional member allocations', () {
    List<BudgetSource> sources(Map<String, int> amounts) => amounts.entries
        .map(
          (entry) => BudgetSource(
            id: 'source-${entry.key}',
            scenarioVersionId: 'v',
            type: BudgetSourceType.memberRecurringIncome,
            name: entry.key,
            expectedCents: entry.value,
            memberUserId: entry.key,
          ),
        )
        .toList(growable: false);
    BudgetAllocationStep step({
      required int amount,
      required ContributionKeyStrategy key,
      Map<String, Object?> definition = const {},
      BudgetInsufficientFundsPolicy policy =
          BudgetInsufficientFundsPolicy.strict,
    }) => BudgetAllocationStep(
      id: 'step',
      scenarioVersionId: 'v',
      order: 10,
      groupName: 'Test',
      sourceId: 'technical',
      envelopeId: 'envelope',
      method: BudgetAllocationMethod.fixed,
      amountCents: amount,
      contributionKey: key,
      keyDefinition: definition,
      insufficientFundsPolicy: policy,
    );
    int contributionTotal(ProgrammableBudgetStepResult result) => result
        .memberContributions
        .values
        .fold<int>(0, (sum, value) => sum + value);

    final equalTwo = engine
        .simulate(
          sources: sources({'a': 10000, 'b': 10000}),
          memberIds: const ['a', 'b'],
          steps: [step(amount: 10000, key: ContributionKeyStrategy.equal)],
        )
        .stepResults
        .single;
    expect(equalTwo.memberContributions, {'a': 5000, 'b': 5000});
    expect(contributionTotal(equalTwo), equalTwo.allocatedCents);

    final equalThree = engine
        .simulate(
          sources: sources({'a': 10000, 'b': 10000, 'c': 10000}),
          memberIds: const ['a', 'b', 'c'],
          steps: [step(amount: 10000, key: ContributionKeyStrategy.equal)],
        )
        .stepResults
        .single;
    expect(equalThree.memberContributions, {'a': 3334, 'b': 3333, 'c': 3333});
    expect(contributionTotal(equalThree), 10000);

    final oneCent = engine
        .simulate(
          sources: sources({'a': 1, 'b': 1, 'c': 1}),
          memberIds: const ['a', 'b', 'c'],
          steps: [step(amount: 1, key: ContributionKeyStrategy.equal)],
        )
        .stepResults
        .single;
    expect(oneCent.memberContributions, {'a': 1, 'b': 0, 'c': 0});
    expect(contributionTotal(oneCent), 1);

    final complexRatios = engine
        .simulate(
          sources: sources({'a': 10000, 'b': 10000, 'c': 10000}),
          memberIds: const ['a', 'b', 'c'],
          steps: [
            step(
              amount: 10000,
              key: ContributionKeyStrategy.customPercentage,
              definition: const {'a': 33.333, 'b': 33.333, 'c': 33.334},
            ),
          ],
        )
        .stepResults
        .single;
    expect(contributionTotal(complexRatios), complexRatios.allocatedCents);
    expect(complexRatios.allocatedCents, 10000);

    final proportional = engine.simulate(
      sources: sources({'ibrahim': 863365, 'nora': 966635}),
      memberIds: const ['ibrahim', 'nora'],
      steps: [
        step(
          amount: 3000000,
          key: ContributionKeyStrategy.automaticRemainingCapacity,
          policy: BudgetInsufficientFundsPolicy.proportional,
        ),
      ],
    );
    final reduced = proportional.stepResults.single;
    expect(reduced.availableBeforeCents, 1830000);
    expect(reduced.allocatedCents, 1830000);
    expect(reduced.remainingAfterCents, 0);
    expect(reduced.memberContributions, {'ibrahim': 863365, 'nora': 966635});
    expect(contributionTotal(reduced), reduced.allocatedCents);
    expect(proportional.memberRemainingCents, {'ibrahim': 0, 'nora': 0});
  });
}
