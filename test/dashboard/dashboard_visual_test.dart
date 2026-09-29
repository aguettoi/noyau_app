import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/theme/app_design_system.dart';
import 'package:noyau_app/features/dashboard/application/dashboard_metrics.dart';
import 'package:noyau_app/features/dashboard/application/providers/remote_financial_dashboard_provider.dart';
import 'package:noyau_app/features/dashboard/presentation/dashboard_charts.dart';
import 'package:noyau_app/features/dashboard/presentation/dashboard_v2_panels.dart';
import 'package:noyau_app/features/dashboard/presentation/financial_dashboard_page.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/financial_availability/domain/financial_availability.dart';
import 'package:noyau_app/features/priorities/domain/priority_plan.dart';
import 'dashboard_v2_test.dart' as fixtures;

void main() {
  testWidgets('long donut legend remains bounded on mobile', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 350,
            child: ExpenseDonut(
              segments: [
                for (var i = 0; i < 6; i++)
                  (
                    name:
                        'Une enveloppe avec un libellé particulièrement long numéro $i',
                    cents: 100,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Tooltip), findsNWidgets(6));
  });
  testWidgets(
    'goals and timeline use existing projections associated by item ID',
    (tester) async {
      final base = fixtures.snapshot();
      final goal = fixtures.goal();
      final plan = PriorityPlanView(
        plan: PriorityPlan(
          id: 'plan',
          householdId: 'real',
          name: 'Plan actif',
          status: PriorityPlanStatus.active,
          createdBy: 'member',
          createdAt: fixtures.now,
          updatedAt: fixtures.now,
        ),
        items: [
          for (final id in ['second', 'first'])
            PriorityPlanItemView(
              item: PriorityPlanItem(
                id: id,
                planId: 'plan',
                householdId: 'real',
                rank: id == 'first' ? 1 : 2,
                sourceType: PrioritySourceType.budgetGoal,
                sourceId: goal.goal.id,
                createdBy: 'member',
                createdAt: fixtures.now,
                updatedAt: fixtures.now,
              ),
              source: PrioritySourceSnapshot(
                type: PrioritySourceType.budgetGoal,
                id: goal.goal.id,
                label: 'Projet $id',
                status: 'active',
                estimatedNeed: goal.remaining,
              ),
            ),
        ],
      );
      final data = FinancialDashboardSnapshot(
        accounts: [],
        ordinaryEnvelopes: [],
        toAllocate: null,
        budget: base.budget,
        monthlyFlow: base.monthlyFlow,
        debts: [],
        incomeReceivables: [],
        recoveryReceivables: [],
        activeGoals: [goal],
        nextPriority: null,
        alerts: [],
        activePlan: plan,
        availability: FinancialAvailabilitySnapshot(
          realLiquidity: fixtures.zero,
          envelopeTotal: fixtures.zero,
          toAllocate: fixtures.zero,
          debtCommitments: fixtures.zero,
          potentialReceivables: fixtures.zero,
          warnings: [],
          goals: {
            goal.goal.id: GoalFundingProjection(
              goalId: goal.goal.id,
              realAccumulated: goal.accumulated,
              securedFunding: const Money.fromMinorUnits(3000),
              remaining: const Money.fromMinorUnits(97000),
              reliability: ProjectionReliability.estimated,
              completionDate: DateTime(2027, 4, 25),
            ),
          },
          planEntries: {
            'plan': [
              PlanProjectionEntry(
                itemId: 'first',
                remainingNeed: goal.remaining,
                completionDate: DateTime(2027, 2, 25),
              ),
              PlanProjectionEntry(
                itemId: 'second',
                remainingNeed: goal.remaining,
                completionDate: DateTime(2027, 4, 25),
              ),
            ],
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardV2Panels(snapshot: data, open: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final goalText = find.textContaining(
        'Échéance : 01/10/2026 • Projection : 25/04/2027',
      );
      await tester.ensureVisible(goalText);
      await tester.pumpAndSettle();
      expect(goalText, findsOneWidget);
      expect(find.textContaining('3.0 %'), findsOneWidget);
      await tester.ensureVisible(find.text('Projet first'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Projet first')).dy,
        lessThan(tester.getTopLeft(find.text('Projet second')).dy),
      );
      expect(find.text('25/02/2027'), findsOneWidget);
      expect(find.text('25/04/2027'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [360.0, 1920.0]) {
    testWidgets('empty cockpit $width: grid, five real plots, no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            financialDashboardProvider.overrideWith(
              (ref) async => fixtures.snapshot(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: FinancialDashboardPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = find.byKey(const Key('dashboard-kpi-grid'));
      expect(grid, findsOneWidget);
      final cards = find.descendant(of: grid, matching: find.byType(Card));
      expect(cards, findsNWidgets(8));
      final first = tester.getRect(cards.at(0));
      final nextRow = tester.getRect(cards.at(width < 600 ? 2 : 4));
      expect(nextRow.top, greaterThan(first.bottom));
      if (width > 1000) {
        final chart = tester.getRect(
          find.byKey(const Key('dashboard-chart-income')),
        );
        final alerts = tester.getRect(find.text('À faire'));
        expect(chart.bottom, lessThan(1080));
        expect(alerts.right, greaterThan(chart.right));
        expect(alerts.top, lessThan(1080));
      } else {
        expect(
          tester.getTopLeft(find.text('À faire')).dy,
          lessThan(
            tester
                .getTopLeft(find.byKey(const Key('dashboard-chart-income')))
                .dy,
          ),
        );
      }
      for (final key in [
        'income',
        'budget',
        'envelopes',
        'donut',
        'liquidity',
      ]) {
        final plot = find.byKey(Key('dashboard-chart-$key'));
        await tester.ensureVisible(plot);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: plot, matching: find.byType(CustomPaint)),
          findsWidgets,
        );
        expect(tester.getSize(plot).height, greaterThan(100));
        expect(tester.takeException(), isNull);
      }
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
      expect(find.textContaining('TEST'), findsNothing);
      expect(find.textContaining('Sandbox'), findsNothing);
    });
  }

  testWidgets(
    'bar chart top five sorted, donut others, budget warning colors',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = fixtures.snapshot();
      final data = FinancialDashboardSnapshot(
        accounts: base.accounts,
        ordinaryEnvelopes: base.ordinaryEnvelopes,
        toAllocate: null,
        budget: base.budget,
        monthlyFlow: base.monthlyFlow,
        debts: [],
        incomeReceivables: [],
        recoveryReceivables: [],
        activeGoals: [],
        nextPriority: null,
        alerts: [],
        report: [
          for (var i = 1; i <= 7; i++)
            RemoteBudgetReportRow(
              envelopeId: 'e$i',
              plannedCents: 600,
              actualCents: i * 100,
              inflowsCents: 0,
              outflowsCents: 0,
              balanceCents: 0,
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardV2Panels(snapshot: data, open: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bars = tester
          .widgetList<ValueBar>(
            find.descendant(
              of: find.byKey(const Key('dashboard-chart-envelopes')),
              matching: find.byType(ValueBar),
            ),
          )
          .toList();
      expect(bars.map((b) => b.cents), [700, 600, 500, 400, 300]);
      final donut = tester.widget<ExpenseDonut>(find.byType(ExpenseDonut));
      expect(donut.segments.length, 6);
      expect(donut.segments.last, (name: 'Autres', cents: 300));
      final budget = find.byKey(const Key('dashboard-chart-budget'));
      await tester.ensureVisible(budget);
      await tester.pumpAndSettle();
      final budgetBars = tester
          .widgetList<ValueBar>(
            find.descendant(of: budget, matching: find.byType(ValueBar)),
          )
          .toList();
      expect(budgetBars.first.color, Colors.red.shade700);
      expect(budgetBars[1].color, AppColors.accent);
      expect(budgetBars[3].color, AppColors.secondary);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('alerts limited to four and critical first with actual action', (
    tester,
  ) async {
    final base = fixtures.snapshot();
    final data = FinancialDashboardSnapshot(
      accounts: [],
      ordinaryEnvelopes: [],
      toAllocate: null,
      budget: base.budget,
      monthlyFlow: base.monthlyFlow,
      debts: [],
      incomeReceivables: [],
      recoveryReceivables: [],
      activeGoals: [],
      nextPriority: null,
      alerts: [
        for (var i = 0; i < 6; i++)
          DashboardAlert(
            title: 'Alerte $i',
            detail: 'Action $i',
            severity: i == 5
                ? DashboardAlertSeverity.critical
                : DashboardAlertSeverity.attention,
            destination: DashboardDestination.accounts,
          ),
      ],
    );
    DashboardDestination? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardV2Panels(
              snapshot: data,
              open: (value) => destination = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, 'Alerte 5');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(4));
    expect(
      tester.widget<ListTile>(find.byType(ListTile).first).title,
      isA<Text>(),
    );
    expect(
      (tester.widget<ListTile>(find.byType(ListTile).first).title! as Text)
          .data,
      'Alerte 5',
    );
    await tester.tap(tile);
    expect(destination, DashboardDestination.accounts);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero chart data and amounts stay finite', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 220,
                child: IncomeExpenseChart(
                  points: [
                    DashboardFlowPoint(
                      DateTime(2026, 1),
                      fixtures.snapshot().monthlyFlow,
                    ),
                  ],
                ),
              ),
              const SizedBox(
                height: 220,
                child: ExpenseDonut(segments: [(name: 'Zéro', cents: 0)]),
              ),
              const ValueBar(label: 'Zéro', cents: 0, maximum: 0),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    expect(find.textContaining('NaN'), findsNothing);
  });
}
