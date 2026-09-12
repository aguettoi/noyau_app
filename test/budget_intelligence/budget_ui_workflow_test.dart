import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/core/theme/app_design_system.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';
import 'package:noyau_app/features/budget_intelligence/infrastructure/budget_supabase_repository.dart';
import 'package:noyau_app/features/budget_intelligence/presentation/budget_page.dart';
import 'package:noyau_app/features/budget_intelligence/presentation/budget_scenarios_page.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';
import 'package:noyau_app/features/budget_intelligence/presentation/budget_contribution_wizard_page.dart';
import 'package:noyau_app/features/budget_intelligence/presentation/budget_monthly_preparation_page.dart';
import 'package:noyau_app/features/budget_intelligence/presentation/programmable_budget_program_page.dart';

void main() {
  final period = RemoteBudgetPeriod(
    id: 'period',
    householdId: 'home',
    startsOn: DateTime(2026, 8, 1),
    endsOn: DateTime(2026, 8, 31),
    status: 'active',
  );
  const scenario = BudgetScenario(
    id: 'scenario',
    householdId: 'home',
    name: 'Budget test',
    active: true,
  );
  final envelope = RemoteEnvelopeBalance(
    id: 'food',
    name: 'Courses',
    inflows: const Money.fromMinorUnits(0),
    outflows: const Money.fromMinorUnits(0),
    balance: const Money.fromMinorUnits(0),
    isSystem: false,
  );

  ProviderScope scope({
    required _Gateway gateway,
    required Widget child,
    List<Override> extra = const [],
  }) {
    final repository = BudgetSupabaseRepository(
      gateway: gateway,
      householdId: 'home',
      userId: 'member',
    );
    return ProviderScope(
      overrides: [
        budgetSupabaseRepositoryProvider.overrideWith(
          (ref) async => repository,
        ),
        remoteBudgetScenariosProvider.overrideWith((ref) async => [scenario]),
        remoteBudgetPeriodsProvider.overrideWith((ref) async => [period]),
        budgetScenarioRulesProvider.overrideWith((ref, id) async => const []),
        budgetScenarioVersionsProvider.overrideWith(
          (ref, id) async => [
            BudgetScenarioVersion(
              id: 'version',
              scenarioId: 'scenario',
              version: 1,
              createdAt: DateTime(2026),
            ),
          ],
        ),
        budgetScenarioMemberIncomesProvider.overrideWith(
          (ref, id) async => const [
            BudgetScenarioMemberIncome(
              memberUserId: 'member',
              netRecurringCents: 1000000,
            ),
          ],
        ),
        remoteEnvelopeBalancesProvider.overrideWith((ref) async => [envelope]),
        remoteBudgetReportingProvider.overrideWith(
          (ref, query) async => const [],
        ),
        remoteBudgetRunsProvider.overrideWith((ref) async => const []),
        remoteAccountsProvider.overrideWith((ref) async => const []),
        remoteHouseholdMembersProvider.overrideWith(
          (ref) async => const [
            HouseholdMember(id: 'member', displayName: 'Membre du foyer'),
          ],
        ),
        ...extra,
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('create scenario widget saves a real scenario', (tester) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(gateway: gateway, child: const BudgetScenariosPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-budget-scenario')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('budget-scenario-name')),
      'Septembre',
    );
    await tester.tap(find.byKey(const Key('save-budget-scenario')));
    await tester.pumpAndSettle();
    expect(gateway.inserts.single.$1, 'budget_scenarios');
    expect(gateway.inserts.single.$2['name'], 'Septembre');
  });

  testWidgets('l’état vide propose et prépare le mois courant sans UUID', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
        extra: [
          remoteBudgetPeriodsProvider.overrideWith((ref) async => const []),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Aucun budget n’a encore été préparé'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('prepare-current-month')), findsOneWidget);
    expect(find.textContaining('00000000-'), findsNothing);
    await tester.tap(find.byKey(const Key('next-budget-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-current-month')));
    await tester.pumpAndSettle();
    expect(gateway.inserts.single.$1, 'budget_periods');
    expect(gateway.rpcs, isEmpty);
  });

  testWidgets('edit and toggle scenario widgets persist the active state', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const BudgetScenarioDetailPage(scenarioId: 'scenario'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toggle-budget-scenario')));
    await tester.pumpAndSettle();
    expect(gateway.updates.single.$2['active'], isFalse);
    await tester.tap(find.byKey(const Key('edit-budget-scenario')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('budget-scenario-name')),
      'Modifié',
    );
    await tester.tap(find.byKey(const Key('save-budget-scenario')));
    await tester.pumpAndSettle();
    expect(gateway.updates.last.$2['name'], 'Modifié');
  });

  testWidgets(
    'batch programme editor exposes the supported methods and validation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _Gateway();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetAllocationBatchEditor(
            versionId: 'version',
            scenarioId: 'scenario',
            sources: const [
              BudgetSource(
                id: 'source',
                scenarioVersionId: 'version',
                type: BudgetSourceType.commonCapacity,
                name: 'Capacité commune',
                expectedCents: 0,
              ),
            ],
            envelopes: [envelope],
            members: const [],
            nextOrder: 10,
          ),
          extra: [
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => const [
                BudgetSource(
                  id: 'source',
                  scenarioVersionId: 'version',
                  type: BudgetSourceType.other,
                  name: 'Revenu',
                  expectedCents: 0,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Configurer plusieurs enveloppes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-other-batch-step')));
      await tester.pumpAndSettle();
      expect(
        find.byType(DropdownButtonFormField<BudgetAllocationMethod>),
        findsOneWidget,
      );
      await tester.tap(
        find.byType(DropdownButtonFormField<BudgetAllocationMethod>),
      );
      await tester.pumpAndSettle();
      expect(find.text('Montant fixe'), findsNWidgets(2));
      expect(find.text('Pourcentage'), findsOneWidget);
      expect(find.text('Reste'), findsOneWidget);
      expect(find.text('Méthode'), findsNothing);
      await tester.tap(find.text('Montant fixe').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-batch-steps')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('batch-step-validation-error')),
        findsOneWidget,
      );
      expect(gateway.inserts, isEmpty);
    },
  );

  testWidgets('batch programme editor exposes budget contribution sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _Gateway();
    const members = [
      HouseholdMember(id: 'member-a', displayName: 'Membre A'),
      HouseholdMember(id: 'member-b', displayName: 'Membre B'),
    ];
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const ProgrammableBudgetProgramPage(scenario: scenario),
        extra: [
          remoteHouseholdMembersProvider.overrideWith((ref) async => members),
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => const [
              BudgetSource(
                id: 'source',
                scenarioVersionId: 'version',
                type: BudgetSourceType.other,
                name: 'Revenu',
                expectedCents: 0,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final addStep = find.byKey(const Key('add-budget-step'));
    await tester.ensureVisible(addStep);
    await tester.tap(addStep);
    await tester.pumpAndSettle();
    expect(find.text('Charges personnelles'), findsOneWidget);
    expect(find.text('Clé personnalisée'), findsOneWidget);
    expect(find.text('Clé automatique'), findsOneWidget);
  });

  testWidgets(
    'warns from the engine when a strict common step exceeds its real position balance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const members = [
        HouseholdMember(id: 'ibrahim', displayName: 'Ibrahim'),
        HouseholdMember(id: 'nora', displayName: 'Nora'),
      ];
      const sources = [
        BudgetSource(
          id: 'salary-ibrahim',
          scenarioVersionId: 'version',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'Salaire Ibrahim',
          expectedCents: 1280000,
          memberUserId: 'ibrahim',
        ),
        BudgetSource(
          id: 'salary-nora',
          scenarioVersionId: 'version',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'Salaire Nora',
          expectedCents: 1500000,
          memberUserId: 'nora',
        ),
      ];
      BudgetAllocationStep step(
        int order,
        int amount,
        ContributionKeyStrategy key, {
        String? memberId,
        Map<String, Object?> definition = const {},
      }) => BudgetAllocationStep(
        id: 'existing-$order',
        scenarioVersionId: 'version',
        order: order,
        groupName: 'Existante',
        sourceId: 'salary-ibrahim',
        envelopeId: 'food',
        method: BudgetAllocationMethod.fixed,
        amountCents: amount,
        contributionKey: key,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        memberUserId: memberId,
        keyDefinition: definition,
      );
      final gateway = _Gateway();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetAllocationBatchEditor(
            versionId: 'version',
            scenarioId: 'scenario',
            sources: sources,
            envelopes: [envelope],
            members: members,
            nextOrder: 60,
            existingSteps: [
              step(
                10,
                150000,
                ContributionKeyStrategy.singleMember,
                memberId: 'ibrahim',
              ),
              step(
                20,
                150000,
                ContributionKeyStrategy.singleMember,
                memberId: 'nora',
              ),
              step(
                30,
                400000,
                ContributionKeyStrategy.customPercentage,
                definition: const {'ibrahim': 40.0, 'nora': 60.0},
              ),
              step(
                40,
                100000,
                ContributionKeyStrategy.automaticRemainingCapacity,
              ),
              step(
                50,
                150000,
                ContributionKeyStrategy.fixedByMember,
                definition: const {'ibrahim': 60000, 'nora': 90000},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-shared-custom-step')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('batch-step-value-60')),
        '30000',
      );
      await tester.enterText(
        find.byKey(const Key('batch-custom-60-ibrahim')),
        '40',
      );
      await tester.enterText(
        find.byKey(const Key('batch-custom-60-nora')),
        '60',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('batch-strict-funds-warning-60')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Fonds insuffisants : cette étape demande 30000.00 MAD alors que '
          '18300.00 MAD sont disponibles à ce stade du scénario.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-batch-steps')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('does not expose the internal common-capacity source', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const ProgrammableBudgetProgramPage(scenario: scenario),
        extra: [
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => const [
              BudgetSource(
                id: 'common-internal',
                scenarioVersionId: 'version',
                type: BudgetSourceType.commonCapacity,
                name: 'Capacité commune technique',
                expectedCents: 0,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Capacité commune technique'), findsNothing);
    expect(find.text('Aucune source définie.'), findsOneWidget);
  });

  testWidgets(
    'month navigation prepares a month without an existing snapshot',
    (tester) async {
      final gateway = _Gateway();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Budget — 2026-08'), findsOneWidget);
      await tester.tap(find.byKey(const Key('next-budget-month')));
      await tester.pumpAndSettle();

      expect(
        find.text('Aucun budget n’a encore été préparé pour ce mois.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('prepare-current-month')), findsOneWidget);
      expect(find.textContaining('Septembre 2026'), findsWidgets);
      expect(gateway.inserts, isEmpty);
      expect(gateway.rpcs, isEmpty);
    },
  );

  testWidgets(
    'a historical month keeps month navigation and does not create a new run',
    (tester) async {
      final gateway = _Gateway();
      final savedRun = RemoteBudgetRun(
        id: 'run-august',
        scenarioId: 'scenario',
        periodId: 'period',
        status: 'applied',
        availableCents: 1000000,
        totalCents: 1000000,
        remainingCents: 0,
        createdAt: DateTime(2026, 8, 1),
        summary: const {
          'monthly_snapshot': true,
          'scenario_name': 'Budget août',
          'sources': [],
          'steps': [],
        },
      );

      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
          extra: [
            remoteBudgetRunsProvider.overrideWith((ref) async => [savedRun]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prepared-month-snapshot')), findsOneWidget);
      expect(find.text('Août 2026'), findsWidgets);
      expect(find.byKey(const Key('next-budget-month')), findsOneWidget);

      await tester.tap(find.byKey(const Key('next-budget-month')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prepared-month-snapshot')), findsNothing);
      expect(
        find.text('Aucun budget n’a encore été préparé pour ce mois.'),
        findsOneWidget,
      );
      expect(find.text('Septembre 2026'), findsWidgets);
      expect(gateway.inserts, isEmpty);
      expect(gateway.rpcs, isEmpty);

      await tester.tap(find.byKey(const Key('previous-budget-month')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prepared-month-snapshot')), findsOneWidget);
      expect(find.text('Août 2026'), findsWidgets);
      expect(gateway.inserts, isEmpty);
      expect(gateway.rpcs, isEmpty);
    },
  );

  testWidgets('month navigation crosses a calendar year without a write', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 12)),
        extra: [
          remoteBudgetPeriodsProvider.overrideWith((ref) async => const []),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Décembre 2026'), findsWidgets);
    await tester.tap(find.byKey(const Key('next-budget-month')));
    await tester.pumpAndSettle();
    expect(find.text('Janvier 2027'), findsWidgets);

    await tester.tap(find.byKey(const Key('previous-budget-month')));
    await tester.pumpAndSettle();
    expect(find.text('Décembre 2026'), findsWidgets);
    expect(gateway.inserts, isEmpty);
    expect(gateway.rpcs, isEmpty);
  });

  testWidgets(
    'batch editor saves personal rows for two members in one session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const members = [
        HouseholdMember(id: 'member-a', displayName: 'Member Alpha'),
        HouseholdMember(id: 'member-b', displayName: 'Member Beta'),
      ];
      const sources = [
        BudgetSource(
          id: 'income-a',
          scenarioVersionId: 'version',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'Salaire Alpha',
          expectedCents: 100000,
          memberUserId: 'member-a',
        ),
        BudgetSource(
          id: 'income-b',
          scenarioVersionId: 'version',
          type: BudgetSourceType.memberRecurringIncome,
          name: 'Salaire Beta',
          expectedCents: 120000,
          memberUserId: 'member-b',
        ),
      ];
      final tsc = RemoteEnvelopeBalance(
        id: 'tsc',
        name: 'TSC',
        inflows: const Money.fromMinorUnits(0),
        outflows: const Money.fromMinorUnits(0),
        balance: const Money.fromMinorUnits(0),
        isSystem: false,
      );
      final gateway = _Gateway();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetAllocationBatchEditor(
            versionId: 'version',
            scenarioId: 'scenario',
            sources: sources,
            envelopes: [tsc],
            members: members,
            nextOrder: 10,
          ),
          extra: [
            remoteHouseholdMembersProvider.overrideWith((ref) async => members),
            remoteEnvelopeBalancesProvider.overrideWith((ref) async => [tsc]),
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => sources,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-personal-step-member-a')));
      await tester.tap(find.byKey(const Key('add-personal-step-member-b')));
      await tester.pumpAndSettle();
      final firstAmount = find.byKey(const Key('batch-step-value-10'));
      await tester.ensureVisible(firstAmount);
      await tester.enterText(firstAmount, '700');
      final secondAmount = find.byKey(const Key('batch-step-value-20'));
      await tester.ensureVisible(secondAmount);
      await tester.enterText(secondAmount, '300');
      final save = find.byKey(const Key('save-batch-steps'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final inserts = gateway.inserts
          .where((entry) => entry.$1 == 'budget_scenario_steps')
          .map((entry) => entry.$2)
          .toList(growable: false);
      expect(inserts, hasLength(2));
      expect(inserts.map((row) => row['member_user_id']), [
        'member-a',
        'member-b',
      ]);
      expect(inserts.map((row) => row['envelope_id']), ['tsc', 'tsc']);
      expect(inserts.map((row) => row['step_order']), [1000010, 1000020]);
      final stepUpdates = gateway.updates
          .where((update) => update.$1 == 'budget_scenario_steps')
          .toList(growable: false);
      expect(
        stepUpdates
            .skip(stepUpdates.length - 2)
            .map((update) => update.$2['step_order']),
        [1, 2],
      );
      expect(inserts.map((row) => row['amount']), ['700.00', '300.00']);
      expect(inserts.map((row) => row['contribution_key']), [
        'single_member',
        'single_member',
      ]);
      expect(gateway.rpcs, isEmpty);
    },
  );

  testWidgets(
    'batch editor blocks a custom key that does not total 100 percent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const members = [
        HouseholdMember(id: 'member-a', displayName: 'Member Alpha'),
        HouseholdMember(id: 'member-b', displayName: 'Member Beta'),
        HouseholdMember(id: 'member-c', displayName: 'Member Gamma'),
      ];
      final gateway = _Gateway();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetAllocationBatchEditor(
            versionId: 'version',
            scenarioId: 'scenario',
            sources: const [
              BudgetSource(
                id: 'common-income',
                scenarioVersionId: 'version',
                type: BudgetSourceType.commonCapacity,
                name: 'Capacité commune',
                expectedCents: 200000,
              ),
            ],
            envelopes: [envelope],
            members: members,
            nextOrder: 10,
          ),
          extra: [
            remoteHouseholdMembersProvider.overrideWith((ref) async => members),
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => const [
                BudgetSource(
                  id: 'common-income',
                  scenarioVersionId: 'version',
                  type: BudgetSourceType.commonCapacity,
                  name: 'Capacité commune',
                  expectedCents: 200000,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-shared-custom-step')));
      await tester.pumpAndSettle();
      expect(find.text('Financement : contributions du foyer'), findsOneWidget);
      expect(find.text('Source personnelle'), findsNothing);
      final amount = find.byKey(const Key('batch-step-value-10'));
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '100');
      for (final entry in const {
        'member-a': '40',
        'member-b': '30',
        'member-c': '29,99',
      }.entries) {
        final field = find.byKey(Key('batch-custom-10-${entry.key}'));
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      final save = find.byKey(const Key('save-batch-steps'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();

      expect(find.text('Total de la clé : 99.99 %'), findsOneWidget);
      expect(find.byKey(const Key('batch-custom-error-10')), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(gateway.inserts, isEmpty);
      expect(gateway.rpcs, isEmpty);

      for (final entry in const {
        'member-a': '40',
        'member-b': '30',
        'member-c': '30',
      }.entries) {
        await tester.enterText(
          find.byKey(Key('batch-custom-10-${entry.key}')),
          entry.value,
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Total de la clé : 100.00 %'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    },
  );

  testWidgets('batch editor creates the shared technical anchor internally', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const members = [
      HouseholdMember(id: 'member-a', displayName: 'Member Alpha'),
      HouseholdMember(id: 'member-b', displayName: 'Member Beta'),
    ];
    const sources = [
      BudgetSource(
        id: 'salary-a',
        scenarioVersionId: 'version',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire Alpha',
        expectedCents: 1280000,
        memberUserId: 'member-a',
      ),
      BudgetSource(
        id: 'salary-b',
        scenarioVersionId: 'version',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire Beta',
        expectedCents: 1500000,
        memberUserId: 'member-b',
      ),
    ];
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: BudgetAllocationBatchEditor(
          versionId: 'version',
          scenarioId: 'scenario',
          sources: sources,
          envelopes: [envelope],
          members: members,
          nextOrder: 10,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-shared-custom-step')));
    await tester.pumpAndSettle();
    expect(find.text('Source personnelle'), findsNothing);
    expect(find.text('Financement : contributions du foyer'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('batch-step-value-10')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const Key('batch-custom-10-member-a')),
      '40',
    );
    await tester.enterText(
      find.byKey(const Key('batch-custom-10-member-b')),
      '60',
    );
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('save-batch-steps'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final technical = gateway.inserts.singleWhere(
      (entry) => entry.$1 == 'budget_scenario_sources',
    );
    expect(technical.$2['source_type'], 'common_capacity');
    expect(technical.$2['expected_amount'], '0.00');
    final step = gateway.inserts.singleWhere(
      (entry) => entry.$1 == 'budget_scenario_steps',
    );
    expect(step.$2['source_id'], 'common-capacity-internal');
    expect(step.$2['key_definition'], {'member-a': 40.0, 'member-b': 60.0});
    expect(gateway.rpcs, isEmpty);
  });

  testWidgets(
    'custom percentages validate live and only enable saving at exactly 100 percent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const members = [
        HouseholdMember(id: 'member-a', displayName: 'Member Alpha'),
        HouseholdMember(id: 'member-b', displayName: 'Member Beta'),
      ];
      final gateway = _Gateway();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetAllocationBatchEditor(
            versionId: 'version',
            scenarioId: 'scenario',
            sources: const [
              BudgetSource(
                id: 'income-a',
                scenarioVersionId: 'version',
                type: BudgetSourceType.memberRecurringIncome,
                name: 'Salaire Alpha',
                expectedCents: 1000000,
                memberUserId: 'member-a',
              ),
              BudgetSource(
                id: 'income-b',
                scenarioVersionId: 'version',
                type: BudgetSourceType.memberRecurringIncome,
                name: 'Salaire Beta',
                expectedCents: 1000000,
                memberUserId: 'member-b',
              ),
            ],
            envelopes: [envelope],
            members: members,
            nextOrder: 10,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-shared-custom-step')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('batch-step-value-10')),
        '4000',
      );
      await tester.enterText(
        find.byKey(const Key('batch-custom-10-member-a')),
        '40',
      );
      final beta = find.byKey(const Key('batch-custom-10-member-b'));
      await tester.enterText(beta, '59,99');
      await tester.pumpAndSettle();

      final save = find.byKey(const Key('save-batch-steps'));
      expect(find.text('Total de la clé : 99.99 %'), findsOneWidget);
      expect(
        find.text(
          'La répartition doit totaliser exactement 100 %. Total actuel : 99.99 %.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(gateway.inserts, isEmpty);

      await tester.enterText(beta, '60,01');
      await tester.pumpAndSettle();
      expect(find.text('Total de la clé : 100.01 %'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('batch-custom-10-member-a')),
        '50',
      );
      await tester.enterText(beta, '50');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

      await tester.enterText(
        find.byKey(const Key('batch-custom-10-member-a')),
        '100',
      );
      await tester.enterText(beta, '0');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

      await tester.enterText(
        find.byKey(const Key('batch-custom-10-member-a')),
        '0',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('batch-custom-10-member-a')),
        '-1',
      );
      await tester.enterText(beta, '101');
      await tester.pumpAndSettle();
      expect(
        find.text('Chaque pourcentage doit être compris entre 0 % et 100 %.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('batch-custom-10-member-a')),
        'invalide',
      );
      await tester.enterText(beta, '60');
      await tester.pumpAndSettle();
      expect(
        find.text('Saisissez un pourcentage pour chaque membre concerné.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('batch-custom-10-member-a')),
        '40',
      );
      await tester.enterText(beta, '60');
      await tester.pumpAndSettle();
      expect(find.text('Total de la clé : 100.00 %'), findsOneWidget);
      expect(find.byKey(const Key('batch-custom-error-10')), findsNothing);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        gateway.inserts.where((entry) => entry.$1 == 'budget_scenario_steps'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'editing an existing inactive step preserves its stored boolean',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _Gateway();
      const existing = BudgetAllocationStep(
        id: 'existing-step',
        scenarioVersionId: 'version',
        order: 10,
        groupName: 'Courses',
        sourceId: 'source',
        envelopeId: 'food',
        method: BudgetAllocationMethod.fixed,
        amountCents: 10000,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        active: false,
      );
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: const ProgrammableBudgetProgramPage(scenario: scenario),
          extra: [
            budgetScenarioStepsProvider.overrideWith(
              (ref, id) async => [existing],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final edit = find.byKey(const Key('edit-budget-step-existing-step'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isFalse);
    },
  );

  testWidgets('budget dashboard routes simulation to monthly preparation', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(scope(gateway: gateway, child: const BudgetPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('simulate-budget')), findsNothing);
    expect(find.byKey(const Key('save-budget-simulation')), findsNothing);
    await tester.tap(find.byKey(const Key('open-monthly-preparation')));
    await tester.pumpAndSettle();
    expect(find.text('Préparer mon mois'), findsOneWidget);
    expect(gateway.rpcs, isEmpty);
  });

  testWidgets(
    'budget screens keep a readable desktop width at supported resolutions',
    (tester) async {
      final gateway = _Gateway();
      for (final size in const [
        Size(1920, 1080),
        Size(1440, 900),
        Size(1366, 768),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          scope(gateway: gateway, child: const BudgetPage()),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(ListView).first).width,
          lessThanOrEqualTo(1360),
        );
        expect(tester.takeException(), isNull);
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    },
  );

  testWidgets('batch editor uses a compact readable width on desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      scope(
        gateway: _Gateway(),
        child: const BudgetAllocationBatchEditor(
          versionId: 'version',
          scenarioId: 'scenario',
          sources: [],
          envelopes: [],
          members: [],
          nextOrder: 10,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(ListView).first).width,
      lessThanOrEqualTo(1180),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'contribution wizard keeps member incomes while navigating its five steps',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _Gateway();
      const members = [
        HouseholdMember(id: 'member-a', displayName: 'Membre A'),
        HouseholdMember(id: 'member-b', displayName: 'Membre B'),
        HouseholdMember(id: 'member-c', displayName: 'Membre C'),
      ];
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: const BudgetContributionWizardPage(scenarioId: 'scenario'),
          extra: [
            remoteHouseholdMembersProvider.overrideWith((ref) async => members),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Membre A'), findsWidgets);
      expect(find.text('Membre B'), findsWidgets);
      expect(find.text('Membre C'), findsWidgets);
      await tester.enterText(
        find.byKey(const Key('income-net-member-a')),
        '12000',
      );
      expect(find.text('Continuer'), findsWidgets);
      await tester.ensureVisible(find.text('Continuer').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer').first);
      await tester.pumpAndSettle();
      expect(
        gateway.inserts.where(
          (entry) => entry.$1 == 'budget_scenario_member_incomes',
        ),
        hasLength(3),
      );
      expect(find.text('Charges personnelles'), findsWidgets);
      expect(find.text('Précédent'), findsWidgets);
      await tester.tap(find.text('Précédent').first);
      await tester.pumpAndSettle();
      expect(find.text('12000'), findsOneWidget);
    },
  );

  testWidgets(
    'monthly preparation offers the default scenario and simulates without a financial event',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _Gateway();
      const defaultScenario = BudgetScenario(
        id: 'default-scenario',
        householdId: 'home',
        name: 'Budget normal',
        active: true,
        isDefault: true,
      );
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
          extra: [
            remoteBudgetScenariosProvider.overrideWith(
              (ref) async => [defaultScenario],
            ),
            // A legacy-only scenario has no programmable version to select.
            budgetScenarioVersionsProvider.overrideWith(
              (ref, id) async => const [],
            ),
            budgetScenarioRulesProvider.overrideWith(
              (ref, id) async => [
                BudgetScenarioRule(
                  id: 'rule',
                  scenarioId: 'default-scenario',
                  envelopeId: 'food',
                  method: BudgetAllocationMethod.fixed,
                  priority: 1,
                  rolloverPolicy: RolloverPolicy.reset,
                  amountCents: 10000,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('monthly-default-scenario-prompt')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('use-default-monthly-scenario')));
      await tester.pumpAndSettle();
      final simulate = find.byKey(const Key('simulate-monthly-budget'));
      await tester.ensureVisible(simulate);
      await tester.tap(simulate);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('monthly-budget-summary')), findsOneWidget);
      expect(gateway.rpcs, isEmpty);
    },
  );

  testWidgets('monthly programmable mode ignores legacy incomes and rules', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _Gateway();
    const programmableScenario = BudgetScenario(
      id: 'programmable-scenario',
      householdId: 'home',
      name: 'TEST BUDGET UI',
      active: true,
      currentVersionId: 'version-current',
    );
    const source = BudgetSource(
      id: 'source-10000',
      scenarioVersionId: 'version-current',
      type: BudgetSourceType.other,
      name: 'Salaire 1',
      expectedCents: 1000000,
      memberUserId: 'member',
    );
    final steps = [
      const BudgetAllocationStep(
        id: 'transport',
        scenarioVersionId: 'version-current',
        order: 10,
        groupName: 'Transport',
        sourceId: 'source-10000',
        envelopeId: 'transport',
        method: BudgetAllocationMethod.percentage,
        percentage: 10,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
      const BudgetAllocationStep(
        id: 'courses',
        scenarioVersionId: 'version-current',
        order: 20,
        groupName: 'Courses',
        sourceId: 'source-10000',
        envelopeId: 'food',
        method: BudgetAllocationMethod.fixed,
        amountCents: 200000,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
      const BudgetAllocationStep(
        id: 'savings',
        scenarioVersionId: 'version-current',
        order: 30,
        groupName: 'Épargne',
        sourceId: 'source-10000',
        envelopeId: 'savings',
        method: BudgetAllocationMethod.residual,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
    ];
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
        extra: [
          remoteBudgetScenariosProvider.overrideWith(
            (ref) async => [programmableScenario],
          ),
          budgetScenarioVersionsProvider.overrideWith(
            (ref, id) async => [
              BudgetScenarioVersion(
                id: 'version-other',
                scenarioId: 'programmable-scenario',
                version: 2,
                createdAt: DateTime(2026),
              ),
              BudgetScenarioVersion(
                id: 'version-current',
                scenarioId: 'programmable-scenario',
                version: 1,
                createdAt: DateTime(2025),
              ),
            ],
          ),
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => id == 'version-current' ? [source] : const [],
          ),
          budgetScenarioStepsProvider.overrideWith(
            (ref, id) async => id == 'version-current' ? steps : const [],
          ),
          budgetScenarioMemberIncomesProvider.overrideWith(
            (ref, id) async => const [
              BudgetScenarioMemberIncome(
                memberUserId: 'member-a',
                netRecurringCents: 1310000,
              ),
              BudgetScenarioMemberIncome(
                memberUserId: 'member-b',
                netRecurringCents: 1400000,
              ),
            ],
          ),
          budgetScenarioRulesProvider.overrideWith(
            (ref, id) async => const [
              BudgetScenarioRule(
                id: 'legacy-rule',
                scenarioId: 'programmable-scenario',
                envelopeId: 'food',
                method: BudgetAllocationMethod.fixed,
                priority: 1,
                rolloverPolicy: RolloverPolicy.reset,
                amountCents: 2710000,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser').first);
    await tester.pumpAndSettle();

    expect(find.text('Version actuelle : 1'), findsOneWidget);
    expect(find.text('1 source(s) • 3 étape(s) • 3 groupe(s)'), findsOneWidget);
    expect(find.textContaining('revenu à confirmer'), findsNothing);
    expect(find.text('3 étape(s) du programme.'), findsNothing);
    await tester.tap(find.byKey(const Key('simulate-monthly-budget')));
    await tester.pumpAndSettle();
    expect(find.text('Ressources : 10000.00 MAD'), findsWidgets);
    expect(find.text('Alloué : 10000.00 MAD'), findsWidgets);
    expect(find.text('Reste : 0.00 MAD'), findsWidgets);
    expect(find.textContaining('27100.00'), findsNothing);
    expect(find.byKey(const Key('save-monthly-budget')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-monthly-budget')))
          .onPressed,
      isNotNull,
    );
    expect(gateway.rpcs, isEmpty);
  });

  testWidgets(
    'monthly preparation falls back to the newest version only when current version is absent',
    (tester) async {
      const scenarioWithoutCurrentVersion = BudgetScenario(
        id: 'fallback-scenario',
        householdId: 'home',
        name: 'Fallback explicite',
        active: true,
      );
      await tester.pumpWidget(
        scope(
          gateway: _Gateway(),
          child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
          extra: [
            remoteBudgetScenariosProvider.overrideWith(
              (ref) async => [scenarioWithoutCurrentVersion],
            ),
            budgetScenarioVersionsProvider.overrideWith(
              (ref, id) async => [
                BudgetScenarioVersion(
                  id: 'newest-version',
                  scenarioId: 'fallback-scenario',
                  version: 2,
                  createdAt: DateTime(2026),
                ),
                BudgetScenarioVersion(
                  id: 'older-version',
                  scenarioId: 'fallback-scenario',
                  version: 1,
                  createdAt: DateTime(2025),
                ),
              ],
            ),
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => id == 'newest-version'
                  ? const [
                      BudgetSource(
                        id: 'fallback-source',
                        scenarioVersionId: 'newest-version',
                        type: BudgetSourceType.other,
                        name: 'Source de fallback',
                        expectedCents: 1000000,
                      ),
                    ]
                  : const [],
            ),
            budgetScenarioStepsProvider.overrideWith(
              (ref, id) async => const [],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Utiliser').first);
      await tester.pumpAndSettle();

      expect(find.text('Version actuelle : 2'), findsOneWidget);
      expect(find.text('Source de fallback'), findsOneWidget);
      expect(
        find.text(
          'Programme programmable incomplet : ajoutez au moins une étape avant de simuler et enregistrer le mois.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('programmable source without active steps blocks simulation', (
    tester,
  ) async {
    const programmableScenario = BudgetScenario(
      id: 'incomplete-scenario',
      householdId: 'home',
      name: 'Incomplet',
      active: true,
      currentVersionId: 'incomplete-version',
    );
    await tester.pumpWidget(
      scope(
        gateway: _Gateway(),
        child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
        extra: [
          remoteBudgetScenariosProvider.overrideWith(
            (ref) async => [programmableScenario],
          ),
          budgetScenarioVersionsProvider.overrideWith(
            (ref, id) async => [
              BudgetScenarioVersion(
                id: 'incomplete-version',
                scenarioId: 'incomplete-scenario',
                version: 1,
                createdAt: DateTime(2026),
              ),
            ],
          ),
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => const [
              BudgetSource(
                id: 'incomplete-source',
                scenarioVersionId: 'incomplete-version',
                type: BudgetSourceType.other,
                name: 'Salaire 1',
                expectedCents: 1000000,
              ),
            ],
          ),
          budgetScenarioStepsProvider.overrideWith((ref, id) async => const []),
          budgetScenarioMemberIncomesProvider.overrideWith(
            (ref, id) async => const [
              BudgetScenarioMemberIncome(
                memberUserId: 'legacy',
                netRecurringCents: 2710000,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser').first);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Programme programmable incomplet : ajoutez au moins une étape avant de simuler et enregistrer le mois.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('simulate-monthly-budget')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('revenu à confirmer'), findsNothing);
    expect(find.byKey(const Key('save-monthly-budget')), findsNothing);
  });

  testWidgets('monthly snapshot uses only the programmable snapshot RPC', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
        extra: [
          budgetScenarioVersionsProvider.overrideWith(
            (ref, id) async => [
              BudgetScenarioVersion(
                id: 'version',
                scenarioId: 'scenario',
                version: 1,
                createdAt: DateTime(2026),
              ),
            ],
          ),
          budgetScenarioRulesProvider.overrideWith(
            (ref, id) async => [
              BudgetScenarioRule(
                id: 'rule',
                scenarioId: 'scenario',
                envelopeId: 'food',
                method: BudgetAllocationMethod.fixed,
                priority: 1,
                rolloverPolicy: RolloverPolicy.reset,
                amountCents: 10000,
              ),
            ],
          ),
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => const [
              BudgetSource(
                id: 'source-saved',
                scenarioVersionId: 'version',
                type: BudgetSourceType.memberRecurringIncome,
                name: 'Salaire sauvegardé',
                expectedCents: 1000000,
                memberUserId: 'member',
              ),
            ],
          ),
          budgetScenarioStepsProvider.overrideWith(
            (ref, id) async => const [
              BudgetAllocationStep(
                id: 'step-saved',
                scenarioVersionId: 'version',
                order: 10,
                groupName: 'Courses',
                sourceId: 'source-saved',
                envelopeId: 'food',
                method: BudgetAllocationMethod.fixed,
                contributionKey: ContributionKeyStrategy.singleMember,
                insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
                amountCents: 10000,
                memberUserId: 'member',
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('monthly-source-source-saved-1000000')),
      '12500',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('simulate-monthly-budget')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simulate-monthly-budget')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('save-monthly-budget')), findsOneWidget);
    await tester.ensureVisible(find.text('Modifier cette étape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier cette étape'));
    await tester.pumpAndSettle();
    expect(find.text('IDENTIFICATION'), findsOneWidget);
    expect(find.text('ALLOCATION'), findsOneWidget);
    expect(find.text('POLITIQUE'), findsOneWidget);
    expect(find.text('ÉTAT'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('budget-step-method'))).height,
      greaterThanOrEqualTo(50),
    );
    await tester.enterText(find.byKey(const Key('budget-step-value')), '150');
    await tester.tap(find.text('Enregistrer').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('simulate-monthly-budget')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simulate-monthly-budget')));
    await tester.pumpAndSettle();
    expect(find.text('Modifié ce mois'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-monthly-budget')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-monthly-budget')));
    await tester.pumpAndSettle();
    expect(gateway.rpcs.single.$1, 'save_programmable_budget_run');
    expect(gateway.rpcs.single.$1, isNot('apply_budget_allocation_run'));
    final summary = gateway.rpcs.single.$2['p_summary'] as Map<String, Object?>;
    expect(summary['scenario_name'], 'Budget test');
    expect(summary['scenario_version'], 1);
    expect(summary['source_overrides_cents'], {'source-saved': 1250000});
    expect((summary['sources'] as List).single['expected_cents'], 1250000);
    expect((summary['steps'] as List).single['id'], 'step-saved');
    expect(
      ((summary['step_overrides'] as Map)['step-saved'] as Map)['amount_cents'],
      15000,
    );
    expect(summary['programmable_result'], isA<Map>());
  });

  testWidgets(
    'a saved month reopens its immutable programmable snapshot instead of the current template',
    (tester) async {
      final gateway = _Gateway();
      final savedRun = RemoteBudgetRun(
        id: 'run-historical',
        scenarioId: 'scenario',
        scenarioVersionId: 'version-v1',
        periodId: 'period',
        status: 'simulated',
        availableCents: 25000,
        totalCents: 20000,
        remainingCents: 5000,
        createdAt: DateTime(2026, 8, 1),
        summary: const {
          'monthly_snapshot': true,
          'scenario_id': 'scenario',
          'scenario_name': 'Scénario V1',
          'scenario_version_id': 'version-v1',
          'scenario_version': 1,
          'sources': [
            {
              'id': 'source-v1',
              'name': 'Salaire V1',
              'expected_cents': 1000000,
              'member_user_id': 'member-a',
              'member_name': 'Member Alpha',
            },
          ],
          'source_overrides_cents': {'source-v1': 1250000},
          'steps': [
            {
              'id': 'step-v1',
              'order': 10,
              'group': 'Charges essentielles',
              'method': 'fixed',
            },
          ],
          'step_overrides': {
            'step-v1': {'amount_cents': 200000, 'active': true},
          },
          'programmable_result': {
            'simulable': true,
            'capacities': [
              {
                'member_user_id': 'member-a',
                'capacity_cents': 1050000,
                'auto_share': 1.0,
              },
            ],
            'steps': [
              {
                'step_id': 'step-v1',
                'requested_cents': 200000,
                'allocated_cents': 200000,
                'status': 'executed',
              },
            ],
            'diagnostics': [
              {
                'severity': 'warning',
                'code': 'historical_warning',
                'message': 'Avertissement historique',
              },
            ],
          },
        },
      );
      const changedSource = BudgetSource(
        id: 'source-v2',
        scenarioVersionId: 'version-v2',
        type: BudgetSourceType.other,
        name: 'Template modifié',
        expectedCents: 9999999,
      );
      const changedStep = BudgetAllocationStep(
        id: 'step-v2',
        scenarioVersionId: 'version-v2',
        order: 99,
        groupName: 'Template modifié',
        sourceId: 'source-v2',
        envelopeId: 'food',
        method: BudgetAllocationMethod.percentage,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.skip,
      );

      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: BudgetMonthlyPreparationPage(initialMonth: DateTime(2026, 8)),
          extra: [
            remoteBudgetRunsProvider.overrideWith((ref) async => [savedRun]),
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => const [changedSource],
            ),
            budgetScenarioStepsProvider.overrideWith(
              (ref, id) async => const [changedStep],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prepared-month-snapshot')), findsOneWidget);
      expect(find.text('Budget préparé'), findsOneWidget);
      expect(find.text('Scénario : Scénario V1'), findsOneWidget);
      expect(find.text('Version : 1'), findsOneWidget);
      expect(find.text('Salaire V1'), findsOneWidget);
      expect(
        find.textContaining('Member Alpha • Modifié ce mois'),
        findsOneWidget,
      );
      expect(find.text('10. Charges essentielles'), findsOneWidget);
      expect(
        find.text('Montant fixe • Modifiée ce mois • Montant : 2000.00 MAD'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Avertissement : Avertissement historique'),
        320,
        scrollable: find.descendant(
          of: find.byKey(const Key('prepared-month-snapshot')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Avertissement : Avertissement historique'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Budget simulable'),
        320,
        scrollable: find.descendant(
          of: find.byKey(const Key('prepared-month-snapshot')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Budget simulable'), findsOneWidget);
      expect(find.text('Template modifié'), findsNothing);
      expect(find.byKey(const Key('simulate-monthly-budget')), findsNothing);
      expect(gateway.inserts, isEmpty);
      expect(gateway.updates, isEmpty);
      expect(gateway.rpcs, isEmpty);
      expect(find.textContaining('source-v1'), findsNothing);
      expect(find.textContaining('step-v1'), findsNothing);
      expect(find.textContaining('member-a'), findsNothing);
    },
  );

  testWidgets('source libre est confirmée puis supprimée depuis le programme', (
    tester,
  ) async {
    const source = BudgetSource(
      id: 'source-free',
      scenarioVersionId: 'version',
      type: BudgetSourceType.other,
      name: 'Prime',
      expectedCents: 5000,
    );
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const ProgrammableBudgetProgramPage(scenario: scenario),
        extra: [
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => const [source],
          ),
          budgetScenarioStepsProvider.overrideWith((ref, id) async => const []),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-budget-source-source-free')));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette source ?'), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(gateway.updates.single.$1, 'budget_scenario_sources');
  });

  testWidgets(
    'suppression source rafraîchit immédiatement la liste canonique',
    (tester) async {
      final gateway = _Gateway()
        ..rowsByTable['budget_scenario_sources'] = [
          {
            'id': 'source-refresh',
            'scenario_version_id': 'version',
            'source_type': 'other',
            'name': 'À supprimer',
            'expected_amount': '50.00',
            'active': true,
          },
        ];
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: const ProgrammableBudgetProgramPage(scenario: scenario),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('À supprimer'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('delete-budget-source-source-refresh')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('À supprimer'), findsNothing);
    },
  );

  testWidgets('source utilisée affiche les noms d’étapes sans UUID', (
    tester,
  ) async {
    const source = BudgetSource(
      id: 'source-used',
      scenarioVersionId: 'version',
      type: BudgetSourceType.other,
      name: 'Salaire',
      expectedCents: 100000,
    );
    const step = BudgetAllocationStep(
      id: 'step-uuid-hidden',
      scenarioVersionId: 'version',
      order: 10,
      groupName: 'Charges communes',
      sourceId: 'source-used',
      envelopeId: 'food',
      method: BudgetAllocationMethod.fixed,
      amountCents: 10000,
      contributionKey: ContributionKeyStrategy.equal,
      insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
    );
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const ProgrammableBudgetProgramPage(scenario: scenario),
        extra: [
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => const [source],
          ),
          budgetScenarioStepsProvider.overrideWith(
            (ref, id) async => const [step],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-budget-source-source-used')));
    await tester.pumpAndSettle();
    expect(find.text('Impossible de supprimer cette source.'), findsOneWidget);
    expect(find.text('• Charges communes'), findsOneWidget);
    expect(find.textContaining('step-uuid-hidden'), findsNothing);
    expect(gateway.updates, isEmpty);
  });

  testWidgets('étape est supprimée après confirmation depuis le programme', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const step = BudgetAllocationStep(
      id: 'step-delete',
      scenarioVersionId: 'version',
      order: 10,
      groupName: 'Courses',
      sourceId: 'source',
      envelopeId: 'food',
      method: BudgetAllocationMethod.fixed,
      amountCents: 10000,
      contributionKey: ContributionKeyStrategy.equal,
      insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
    );
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const ProgrammableBudgetProgramPage(scenario: scenario),
        extra: [
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => const [],
          ),
          budgetScenarioStepsProvider.overrideWith(
            (ref, id) async => const [step],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final delete = find.byKey(const Key('delete-budget-step-step-delete'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette étape du scénario ?'), findsOneWidget);
    expect(
      find.text(
        'Les simulations et historiques déjà enregistrés ne seront pas modifiés.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(gateway.updates.single.$1, 'budget_scenario_steps');
  });

  testWidgets(
    'dupliquer crée une copie persistée immédiatement après l’original',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const first = BudgetAllocationStep(
        id: 'first',
        scenarioVersionId: 'version',
        order: 10,
        groupName: 'Charges fixes',
        sourceId: 'source',
        envelopeId: 'food',
        method: BudgetAllocationMethod.fixed,
        amountCents: 10000,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      );
      const second = BudgetAllocationStep(
        id: 'second',
        scenarioVersionId: 'version',
        order: 20,
        groupName: 'Épargne',
        sourceId: 'source',
        envelopeId: 'food',
        method: BudgetAllocationMethod.residual,
        contributionKey: ContributionKeyStrategy.equal,
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      );
      final gateway = _Gateway();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: const ProgrammableBudgetProgramPage(scenario: scenario),
          extra: [
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => const [],
            ),
            budgetScenarioStepsProvider.overrideWith(
              (ref, id) async => const [first, second],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final duplicate = find.byKey(const Key('duplicate-budget-step-first'));
      await tester.ensureVisible(duplicate);
      await tester.tap(duplicate);
      await tester.pumpAndSettle();
      expect(gateway.inserts.single.$1, 'budget_scenario_steps');
      expect(gateway.inserts.single.$2['group_name'], 'Charges fixes');
      expect(gateway.updates.skip(3).map((update) => update.$2['step_order']), [
        1,
        2,
        3,
      ]);
    },
  );

  testWidgets(
    'les flèches gardent un ordre visible 1..N et confirment la persistance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const source = BudgetSource(
        id: 'source-order',
        scenarioVersionId: 'version',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire',
        expectedCents: 100000,
        memberUserId: 'member',
      );
      final steps = List.generate(
        3,
        (index) => BudgetAllocationStep(
          id: 'ordered-${index + 1}',
          scenarioVersionId: 'version',
          order: index * 10,
          groupName: 'Étape ${index + 1}',
          sourceId: source.id,
          envelopeId: 'food',
          method: BudgetAllocationMethod.fixed,
          amountCents: 1000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      );
      final gateway = _Gateway();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: const ProgrammableBudgetProgramPage(scenario: scenario),
          extra: [
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => [source],
            ),
            budgetScenarioStepsProvider.overrideWith((ref, id) async => steps),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 • Étape 1'), findsOneWidget);
      expect(find.text('2 • Étape 2'), findsOneWidget);
      expect(find.text('3 • Étape 3'), findsOneWidget);
      final moveUp = find.byKey(const Key('move-budget-step-up-ordered-3'));
      await tester.ensureVisible(moveUp);
      await tester.tap(moveUp);
      await tester.pumpAndSettle();

      expect(find.text('Ordre enregistré'), findsOneWidget);
      final saved = gateway.updates
          .where((update) => update.$1 == 'budget_scenario_steps')
          .skip(3)
          .map((update) => '${update.$3['id']}:${update.$2['step_order']}');
      expect(saved, ['ordered-1:1', 'ordered-3:2', 'ordered-2:3']);
    },
  );

  testWidgets('la poignée desktop déclenche le glisser-déposer persistant', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const source = BudgetSource(
      id: 'source-drag',
      scenarioVersionId: 'version',
      type: BudgetSourceType.memberRecurringIncome,
      name: 'Salaire',
      expectedCents: 100000,
      memberUserId: 'member',
    );
    final steps = List.generate(
      3,
      (index) => BudgetAllocationStep(
        id: 'drag-${index + 1}',
        scenarioVersionId: 'version',
        order: index + 1,
        groupName: 'Ligne ${index + 1}',
        sourceId: source.id,
        envelopeId: 'food',
        method: BudgetAllocationMethod.fixed,
        amountCents: 1000,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
    );
    final gateway = _Gateway()..updateBarrier = Completer<void>();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const ProgrammableBudgetProgramPage(scenario: scenario),
        extra: [
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => [source],
          ),
          budgetScenarioStepsProvider.overrideWith((ref, id) async => steps),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final handle = find.byKey(const Key('drag-budget-step-drag-3'));
    expect(handle, findsOneWidget);
    await tester.ensureVisible(handle);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, -320));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(
      find.byKey(const Key('budget-step-reordering-feedback')),
      findsOneWidget,
    );
    gateway.updateBarrier!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Ordre enregistré'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final id in ['drag-1', 'drag-2', 'drag-3']) {
      expect(find.byKey(Key('budget-step-$id')), findsOneWidget);
      expect(find.byKey(Key('drag-budget-step-$id')), findsOneWidget);
    }
    expect(
      gateway.updates.where((update) => update.$1 == 'budget_scenario_steps'),
      isNotEmpty,
    );
  });

  testWidgets(
    'le drag auto-défile sans muter le layout pendant plusieurs frames',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const source = BudgetSource(
        id: 'source-autoscroll',
        scenarioVersionId: 'version',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire',
        expectedCents: 100000,
        memberUserId: 'member',
      );
      final steps = List.generate(
        12,
        (index) => BudgetAllocationStep(
          id: 'scroll-${index + 1}',
          scenarioVersionId: 'version',
          order: index + 1,
          groupName: 'Défilement ${index + 1}',
          sourceId: source.id,
          envelopeId: 'food',
          method: BudgetAllocationMethod.fixed,
          amountCents: 1000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      );
      await tester.pumpWidget(
        scope(
          gateway: _Gateway(),
          child: const ProgrammableBudgetProgramPage(scenario: scenario),
          extra: [
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => [source],
            ),
            budgetScenarioStepsProvider.overrideWith((ref, id) async => steps),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('budget-program-step-list'));
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      final scrollState = tester.state<ScrollableState>(scrollable);
      scrollState.position.jumpTo(120);
      await tester.pump();
      final handle = find.byKey(const Key('drag-budget-step-scroll-6'));
      expect(handle, findsOneWidget);

      final listRect = tester.getRect(list);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      final beforeUp = scrollState.position.pixels;
      await gesture.moveTo(Offset(listRect.center.dx, listRect.top + 4));
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
      }
      expect(scrollState.position.pixels, lessThan(beforeUp));

      final beforeDown = scrollState.position.pixels;
      await gesture.moveTo(Offset(listRect.center.dx, listRect.bottom - 4));
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
      }
      expect(scrollState.position.pixels, greaterThan(beforeDown));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The viewport lazily builds rows, but the dragged row retains its
      // immutable identity after multiple layout frames and the reordering.
      expect(find.byKey(const Key('budget-step-scroll-6')), findsOneWidget);
      expect(
        find.byKey(const Key('drag-budget-step-scroll-6')),
        findsOneWidget,
      );
    },
  );

  testWidgets('la position directe valide ses bornes et déplace sans perte', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const source = BudgetSource(
      id: 'source-position',
      scenarioVersionId: 'version',
      type: BudgetSourceType.memberRecurringIncome,
      name: 'Salaire',
      expectedCents: 100000,
      memberUserId: 'member',
    );
    final steps = List.generate(
      3,
      (index) => BudgetAllocationStep(
        id: 'position-${index + 1}',
        scenarioVersionId: 'version',
        order: index + 1,
        groupName: 'Position ${index + 1}',
        sourceId: source.id,
        envelopeId: 'food',
        method: BudgetAllocationMethod.fixed,
        amountCents: 1000,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
      ),
    );
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const ProgrammableBudgetProgramPage(scenario: scenario),
        extra: [
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => [source],
          ),
          budgetScenarioStepsProvider.overrideWith((ref, id) async => steps),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final edit = find.byKey(const Key('edit-budget-step-position-3'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Position'), findsOneWidget);
    final position = find.widgetWithText(TextField, 'Position');
    await tester.enterText(position, '0');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
      find.text('Saisissez une position entière entre 1 et 3.'),
      findsOneWidget,
    );

    await tester.enterText(position, '-1');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
      find.text('Saisissez une position entière entre 1 et 3.'),
      findsOneWidget,
    );
    await tester.enterText(position, '4');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
      find.text('Saisissez une position entière entre 1 et 3.'),
      findsOneWidget,
    );

    await tester.enterText(position, '1');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final stepUpdates = gateway.updates
        .where((update) => update.$1 == 'budget_scenario_steps')
        .toList(growable: false);
    final saved = stepUpdates
        .skip(stepUpdates.length - 3)
        .map((update) => '${update.$3['id']}:${update.$2['step_order']}');
    expect(saved, ['position-3:1', 'position-1:2', 'position-2:3']);
  });

  testWidgets(
    'le réordonnancement montre son chargement, bloque une seconde action et confirme',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const source = BudgetSource(
        id: 'source-feedback',
        scenarioVersionId: 'version',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire',
        expectedCents: 100000,
        memberUserId: 'member',
      );
      final steps = List.generate(
        2,
        (index) => BudgetAllocationStep(
          id: 'feedback-${index + 1}',
          scenarioVersionId: 'version',
          order: index + 1,
          groupName: 'Feedback ${index + 1}',
          sourceId: source.id,
          envelopeId: 'food',
          method: BudgetAllocationMethod.fixed,
          amountCents: 1000,
          contributionKey: ContributionKeyStrategy.singleMember,
          memberUserId: 'member',
          insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
        ),
      );
      final gateway = _Gateway()..updateBarrier = Completer<void>();
      await tester.pumpWidget(
        scope(
          gateway: gateway,
          child: const ProgrammableBudgetProgramPage(scenario: scenario),
          extra: [
            budgetScenarioSourcesProvider.overrideWith(
              (ref, id) async => [source],
            ),
            budgetScenarioStepsProvider.overrideWith((ref, id) async => steps),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final moveUp = find.byKey(const Key('move-budget-step-up-feedback-2'));
      await tester.ensureVisible(moveUp);
      await tester.tap(moveUp);
      await tester.pump();
      // The production implementation waits for the drag/layout frame and
      // deliberately yields one event-loop turn before changing its feedback.
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        find.byKey(const Key('budget-step-reordering-feedback')),
        findsOneWidget,
      );
      expect(find.text('Réorganisation en cours…'), findsOneWidget);
      expect(tester.widget<IconButton>(moveUp).onPressed, isNull);

      gateway.updateBarrier!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Ordre enregistré'), findsOneWidget);
    },
  );

  testWidgets('une erreur de réordonnancement restaure un état explicite', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const source = BudgetSource(
      id: 'source-error',
      scenarioVersionId: 'version',
      type: BudgetSourceType.memberRecurringIncome,
      name: 'Salaire',
      expectedCents: 100000,
      memberUserId: 'member',
    );
    const first = BudgetAllocationStep(
      id: 'error-1',
      scenarioVersionId: 'version',
      order: 1,
      groupName: 'Erreur 1',
      sourceId: 'source-error',
      envelopeId: 'food',
      method: BudgetAllocationMethod.fixed,
      amountCents: 1000,
      contributionKey: ContributionKeyStrategy.singleMember,
      memberUserId: 'member',
      insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
    );
    const second = BudgetAllocationStep(
      id: 'error-2',
      scenarioVersionId: 'version',
      order: 2,
      groupName: 'Erreur 2',
      sourceId: 'source-error',
      envelopeId: 'food',
      method: BudgetAllocationMethod.fixed,
      amountCents: 1000,
      contributionKey: ContributionKeyStrategy.singleMember,
      memberUserId: 'member',
      insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
    );
    final gateway = _Gateway()
      ..updateFailure = StateError('réseau indisponible');
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const ProgrammableBudgetProgramPage(scenario: scenario),
        extra: [
          budgetScenarioSourcesProvider.overrideWith(
            (ref, id) async => [source],
          ),
          budgetScenarioStepsProvider.overrideWith(
            (ref, id) async => const [first, second],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final moveUp = find.byKey(const Key('move-budget-step-up-error-2'));
    await tester.ensureVisible(moveUp);
    await tester.tap(moveUp);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('budget-step-reordering-error')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Réorganisation impossible. Vérifiez votre connexion puis réessayez.',
      ),
      findsWidgets,
    );
    expect(tester.widget<IconButton>(moveUp).onPressed, isNotNull);
  });

  testWidgets('réinitialiser les valeurs restaure la source normale', (
    tester,
  ) async {
    const source = BudgetSource(
      id: 'salary',
      scenarioVersionId: 'v',
      type: BudgetSourceType.memberRecurringIncome,
      name: 'Salaire',
      expectedCents: 10000,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScenarioTestSheet(sources: [source], steps: [], members: []),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '250');
    await tester.pump();
    expect(find.text('Reste : 250.00 MAD'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reset-test-source-values')));
    await tester.pump();
    expect(find.text('Reste : 100.00 MAD'), findsOneWidget);
  });

  testWidgets('résout les membres personnels par leur identifiant', (
    tester,
  ) async {
    const sources = [
      BudgetSource(
        id: 'a',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Revenu A',
        expectedCents: 1,
        memberUserId: 'a',
      ),
      BudgetSource(
        id: 'b',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Revenu B',
        expectedCents: 1,
        memberUserId: 'b',
      ),
    ];
    const members = [
      HouseholdMember(id: 'a', displayName: 'Member Alpha'),
      HouseholdMember(id: 'b', displayName: 'Member Beta'),
      HouseholdMember(id: 'c', displayName: 'Member Gamma'),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScenarioTestSheet(
            sources: sources,
            steps: [],
            members: members,
          ),
        ),
      ),
    );
    expect(find.textContaining('Revenu A • Member Alpha'), findsOneWidget);
    expect(find.textContaining('Revenu B • Member Beta'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.textContaining('Member Gamma'), findsOneWidget);
  });

  testWidgets('explique la capacité et la clé automatique de trois membres', (
    tester,
  ) async {
    const sources = [
      BudgetSource(
        id: 'income-a',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire Alpha',
        expectedCents: 600000,
        memberUserId: 'a',
      ),
      BudgetSource(
        id: 'income-b',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire Beta',
        expectedCents: 300000,
        memberUserId: 'b',
      ),
      BudgetSource(
        id: 'income-c',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire Gamma',
        expectedCents: 200000,
        memberUserId: 'c',
      ),
    ];
    const steps = [
      BudgetAllocationStep(
        id: 'charge-alpha',
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
    ];
    const members = [
      HouseholdMember(id: 'a', displayName: 'Member Alpha'),
      HouseholdMember(id: 'b', displayName: 'Member Beta'),
      HouseholdMember(id: 'c', displayName: 'Member Gamma'),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScenarioTestSheet(
            sources: sources,
            steps: steps,
            members: members,
          ),
        ),
      ),
    );
    expect(find.text('Capacité contributive'), findsOneWidget);
    expect(find.text('Member Alpha'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('Member Beta'), findsOneWidget);
    expect(find.text('Member Gamma'), findsOneWidget);
    expect(find.text('Capacité brute : 5000.00 MAD'), findsOneWidget);
    expect(find.text('Clé automatique : 50.00 %'), findsOneWidget);
    expect(find.text('Clé automatique : 30.00 %'), findsOneWidget);
    expect(find.text('Clé automatique : 20.00 %'), findsOneWidget);
    expect(
      find.text('Capacité contributive totale du foyer : 10000.00 MAD'),
      findsOneWidget,
    );
  });

  testWidgets('le test temporaire ne déclenche aucune mutation persistante', (
    tester,
  ) async {
    const source = BudgetSource(
      id: 'income',
      scenarioVersionId: 'version',
      type: BudgetSourceType.memberRecurringIncome,
      name: 'Revenu configuré',
      expectedCents: 10000,
      memberUserId: 'member',
    );
    const step = BudgetAllocationStep(
      id: 'step',
      scenarioVersionId: 'version',
      order: 10,
      groupName: 'Commun',
      sourceId: 'income',
      envelopeId: 'envelope',
      method: BudgetAllocationMethod.fixed,
      amountCents: 5000,
      contributionKey: ContributionKeyStrategy.automaticRemainingCapacity,
      insufficientFundsPolicy: BudgetInsufficientFundsPolicy.strict,
    );
    final gateway = _Gateway();
    await tester.pumpWidget(
      scope(
        gateway: gateway,
        child: const Scaffold(
          body: ScenarioTestSheet(
            sources: [source],
            steps: [step],
            members: [HouseholdMember(id: 'member', displayName: 'Member')],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '250');
    await tester.pump();
    expect(find.text('Reste : 200.00 MAD'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reset-test-source-values')));
    await tester.pump();

    expect(source.expectedCents, 10000);
    expect(step.amountCents, 5000);
    expect(gateway.inserts, isEmpty);
    expect(gateway.updates, isEmpty);
    expect(gateway.rpcs, isEmpty);
  });

  testWidgets('fermer puis rouvrir le test oublie les overrides temporaires', (
    tester,
  ) async {
    const source = BudgetSource(
      id: 'income',
      scenarioVersionId: 'version',
      type: BudgetSourceType.memberRecurringIncome,
      name: 'Revenu configuré',
      expectedCents: 10000,
    );
    Future<void> open() => tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScenarioTestSheet(sources: [source], steps: [], members: []),
        ),
      ),
    );

    await open();
    await tester.enterText(find.byType(TextFormField), '250');
    await tester.pump();
    expect(find.text('Reste : 250.00 MAD'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await open();
    expect(find.text('Reste : 100.00 MAD'), findsOneWidget);
    expect(source.expectedCents, 10000);
  });

  testWidgets(
    'affiche un résultat détaillé lisible sans identifiants techniques',
    (tester) async {
      const source = BudgetSource(
        id: 'source-internal',
        scenarioVersionId: 'v',
        type: BudgetSourceType.memberRecurringIncome,
        name: 'Salaire net',
        expectedCents: 10000,
        memberUserId: 'member-internal',
      );
      const step = BudgetAllocationStep(
        id: 'step-internal',
        scenarioVersionId: 'v',
        order: 10,
        groupName: 'Courses',
        sourceId: 'source-internal',
        envelopeId: 'envelope-internal',
        method: BudgetAllocationMethod.fixed,
        amountCents: 20000,
        contributionKey: ContributionKeyStrategy.singleMember,
        memberUserId: 'member-internal',
        insufficientFundsPolicy: BudgetInsufficientFundsPolicy.cap,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ScenarioTestSheet(
              sources: [source],
              steps: [step],
              members: [
                HouseholdMember(id: 'member-internal', displayName: 'Member'),
              ],
              envelopeNames: {'envelope-internal': 'Alimentation'},
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pump();
      final stepTitle = find.text('Étape 10 — Courses');
      await tester.ensureVisible(stepTitle);
      expect(stepTitle, findsOneWidget);
      expect(find.text('Exécutée partiellement'), findsOneWidget);
      expect(find.text('100.00 MAD alloués'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Exécutée partiellement')).style?.color,
        AppColors.warning,
      );
      await tester.tap(stepTitle);
      await tester.pump();
      expect(find.text('Source : Salaire net'), findsOneWidget);
      expect(find.text('Destination : Alimentation'), findsOneWidget);
      expect(find.text('Demandé'), findsOneWidget);
      expect(find.text('Alloué'), findsOneWidget);
      expect(find.text('200.00 MAD'), findsWidgets);
      expect(find.text('100.00 MAD'), findsWidgets);
      expect(
        find.text('Allocation plafonnée aux ressources disponibles.'),
        findsOneWidget,
      );
      expect(find.textContaining('source-internal'), findsNothing);
      expect(find.textContaining('step-internal'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump();
      expect(find.text('Synthèse par membre'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
      expect(find.text('Synthèse finale du foyer'), findsOneWidget);
      expect(find.text('Budget simulable : Oui'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Budget simulable : Oui')).style?.color,
        AppColors.success,
      );
    },
  );

  test(
    'preserves a visible partial reduction coefficient below 100 percent',
    () {
      expect(formatReductionCoefficient(32568 / 32569), '99.9969 %');
      expect(formatReductionCoefficient(1), '100.00 %');
      expect(formatReductionCoefficient(.875), '87.50 %');
    },
  );
}

class _Gateway implements BudgetSupabaseGateway {
  final inserts = <(String, Map<String, Object?>)>[];
  final updates = <(String, Map<String, Object?>, Map<String, Object?>)>[];
  final rpcs = <(String, Map<String, Object?>)>[];
  final rowsByTable = <String, List<Map<String, Object?>>>{};
  Completer<void>? updateBarrier;
  Object? updateFailure;

  @override
  Future<Object?> insert(String table, Map<String, Object?> values) async {
    inserts.add((table, values));
    if (table == 'budget_scenario_sources') {
      const result = {'id': 'common-capacity-internal'};
      rowsByTable.putIfAbsent(table, () => []).add({...values, ...result});
      return result;
    }
    if (table == 'budget_scenario_steps') {
      const result = {'id': 'step-copy'};
      rowsByTable.putIfAbsent(table, () => []).add({...values, ...result});
      return result;
    }
    return values;
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
    await updateBarrier?.future;
    if (updateFailure != null) throw updateFailure!;
    updates.add((table, values, filters));
    final id = filters['id'];
    for (final row in rowsByTable[table] ?? const []) {
      if (row['id'] == id) row.addAll(values);
    }
  }

  @override
  Future<void> delete(String table, Map<String, Object?> filters) async {
    updates.add((table, const {'deleted': true}, filters));
    rowsByTable[table]?.removeWhere((row) => row['id'] == filters['id']);
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
  ) async => List.unmodifiable(rowsByTable[table] ?? const []);
}
