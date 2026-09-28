import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/dashboard/application/dashboard_metrics.dart';
import 'package:noyau_app/features/dashboard/application/providers/dashboard_history_provider.dart';
import 'package:noyau_app/features/dashboard/application/providers/remote_financial_dashboard_provider.dart';
import 'package:noyau_app/features/dashboard/presentation/financial_dashboard_page.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_debts_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/financial_availability/domain/financial_availability.dart';
import 'package:noyau_app/features/priorities/domain/priority_plan.dart';
import 'package:noyau_app/features/savings_goals/domain/savings_goal.dart';

const zero = Money.fromMinorUnits(0);
final now = DateTime(2026, 10, 15);
const availability = FinancialAvailabilitySnapshot(
  realLiquidity: zero,
  envelopeTotal: zero,
  toAllocate: zero,
  debtCommitments: zero,
  potentialReceivables: zero,
  goals: {},
  planEntries: {},
  warnings: [],
);
const budget = DashboardBudgetSummary(
  period: null,
  planned: zero,
  consumed: zero,
  overspentEnvelopeIds: {},
);

RemoteEnvelopeBalance envelope(int cents) => RemoteEnvelopeBalance(
  id: 'food',
  name: 'Nourriture',
  inflows: zero,
  outflows: zero,
  balance: Money.fromMinorUnits(cents),
  isSystem: false,
);
RemoteBudgetReportRow report(int actual, {int planned = 10000}) =>
    RemoteBudgetReportRow(
      envelopeId: 'food',
      plannedCents: planned,
      actualCents: actual,
      inflowsCents: 0,
      outflowsCents: 0,
      balanceCents: 0,
    );
DashboardAccountBalance account({
  String id = 'bank',
  int balance = 10000,
  FinancialAccountType type = FinancialAccountType.bank,
}) => DashboardAccountBalance(
  account: FinancialAccount(
    id: id,
    name: 'Compte $id',
    type: type,
    openingBalance: zero,
  ),
  balance: Money.fromMinorUnits(balance),
);
SavingsGoalProgress goal() => SavingsGoalProgress(
  goal: SavingsGoal(
    id: 'goal',
    householdId: 'real',
    name: 'Voyage',
    type: SavingsGoalType.travel,
    targetAmount: const Money.fromMinorUnits(100000),
    priority: 1,
    status: SavingsGoalStatus.active,
    fundingEnvelopeId: 'food',
    createdBy: 'member',
    createdAt: now,
    updatedAt: now,
    targetDate: DateTime(2026, 10, 1),
  ),
  envelopeName: 'Voyages',
  accumulated: const Money.fromMinorUnits(3000),
);
List<DashboardAlert> alerts({
  List<DashboardAccountBalance> accounts = const [],
  List<RemoteEnvelopeBalance> envelopes = const [],
  List<RemoteBudgetReportRow> reports = const [],
  List<RemoteDebtBalance> debts = const [],
  List<RemoteReceivableBalance> receivables = const [],
  List<DashboardReconciliation> cases = const [],
  List<SavingsGoalProgress> goals = const [],
  PriorityPlanView? plan,
}) => buildDashboardAlerts(
  accounts: accounts,
  envelopes: envelopes,
  toAllocate: null,
  budget: budget,
  debts: debts,
  incomeReceivables: receivables,
  recoveryReceivables: const [],
  now: now,
  report: reports,
  reconciliations: cases,
  goals: goals,
  availability: availability,
  activePlan: plan,
  thresholds: const DashboardThresholds(),
);
FinancialDashboardSnapshot snapshot({
  DashboardPeriod period = DashboardPeriod.currentMonth,
  bool populated = false,
}) => FinancialDashboardSnapshot(
  accounts: populated ? [account()] : [],
  ordinaryEnvelopes: populated ? [envelope(20000)] : [],
  toAllocate: null,
  budget: budget,
  monthlyFlow: const DashboardMonthlyFlow(income: zero, expense: zero),
  debts: const [],
  incomeReceivables: const [],
  recoveryReceivables: const [],
  activeGoals: populated ? [goal()] : [],
  nextPriority: null,
  alerts: populated
      ? alerts(
          accounts: [account()],
          envelopes: [envelope(-100)],
          reports: [report(9000)],
        )
      : [],
  report: populated ? [report(9000)] : [],
  history: populated
      ? [
          DashboardFlowPoint(
            DateTime(2026, 10),
            const DashboardMonthlyFlow(
              income: Money.fromMinorUnits(100000),
              expense: Money.fromMinorUnits(9000),
            ),
          ),
        ]
      : [],
  availability: availability,
  period: period,
);

void main() {
  test(
    'period boundaries include year transition without invented history',
    () {
      expect(
        DashboardPeriod.previousMonth.bounds(DateTime(2026, 1, 5)).start,
        DateTime(2025, 12),
      );
      expect(DashboardPeriod.threeMonths.bounds(now).start, DateTime(2026, 8));
      expect(DashboardPeriod.sixMonths.bounds(now).start, DateTime(2026, 5));
      expect(DashboardPeriod.year.bounds(now).start, DateTime(2026));
      expect(dashboardFlowSeries([]), isEmpty);
    },
  );
  test(
    'series aggregates recognition only; no settlements, openings or missing months',
    () {
      final result = dashboardFlowSeries([
        {
          'occurred_at': '2026-10-01T12:00:00Z',
          'type': 'income',
          'amount': '100.00',
        },
        {
          'occurred_at': '2026-10-02T12:00:00Z',
          'type': 'income_receivable',
          'amount': '50.00',
        },
        {
          'occurred_at': '2026-10-03T12:00:00Z',
          'type': 'expense',
          'amount': '20.00',
        },
        {
          'occurred_at': '2026-10-03T12:00:00Z',
          'type': 'debt_expense',
          'amount': '10.00',
        },
        {
          'occurred_at': '2026-09-03T12:00:00Z',
          'type': 'account_opening',
          'amount': '1000.00',
        },
        {
          'occurred_at': '2026-10-03T12:00:00Z',
          'type': 'receivable_settlement',
          'amount': '50.00',
        },
      ]);
      expect(result.length, 1);
      expect(result.single.flow.income.minorUnits, 15000);
      expect(result.single.flow.expense.minorUnits, 3000);
      expect(result.single.flow.remainder.minorUnits, 12000);
    },
  );
  test('budget warning starts exactly at 80%, critical only above budget', () {
    expect(alerts(reports: [report(7999)]), isEmpty);
    expect(
      alerts(reports: [report(8000)]).single.severity,
      DashboardAlertSeverity.warning,
    );
    expect(
      alerts(reports: [report(10000)]).single.severity,
      DashboardAlertSeverity.warning,
    );
    expect(
      alerts(reports: [report(10001)]).single.severity,
      DashboardAlertSeverity.critical,
    );
    expect(alerts(reports: [report(100, planned: 0)]), isEmpty);
  });
  test('negative envelope and account route to correct destinations', () {
    expect(
      alerts(envelopes: [envelope(-1)]).single.destination,
      DashboardDestination.envelopes,
    );
    expect(
      alerts(
        accounts: [account(balance: -1)],
      ).firstWhere((a) => a.title == 'Compte négatif').destination,
      DashboardDestination.accounts,
    );
  });
  test('only reliable debt due dates trigger temporal alerts', () {
    RemoteDebtBalance debt(DateTime? due) => RemoteDebtBalance(
      id: 'd',
      description: 'Dette',
      initialAmount: const Money.fromMinorUnits(10000),
      settledAmount: zero,
      remainingAmount: const Money.fromMinorUnits(10000),
      status: 'open',
      dueAt: due,
    );
    expect(alerts(debts: [debt(null)]), isEmpty);
    expect(
      alerts(debts: [debt(DateTime(2026, 10, 20))]).single.title,
      'Dette à échéance proche',
    );
    expect(
      alerts(debts: [debt(DateTime(2026, 10, 1))]).single.title,
      'Dette en retard',
    );
  });
  test('receivable alert uses net open amount not initial value', () {
    final result = alerts(
      receivables: [
        RemoteReceivableBalance(
          id: 'r',
          description: 'Salaire',
          kind: 'income',
          initialAmount: const Money.fromMinorUnits(10000),
          settledAmount: const Money.fromMinorUnits(6000),
          remainingAmount: const Money.fromMinorUnits(4000),
          status: 'open',
          dueAt: DateTime(2026, 10, 10),
        ),
      ],
    );
    expect(result.single.detail, contains('40.00'));
    expect(result.single.destination, DashboardDestination.receivables);
  });
  test(
    'older open case survives later reconciled observation; legacy null is not reconstructed',
    () {
      final cases = [
        DashboardReconciliation(
          accountId: 'bank',
          status: 'open',
          observedAt: DateTime(2026, 10, 1),
          remaining: const Money.fromMinorUnits(5000),
        ),
        DashboardReconciliation(
          accountId: 'bank',
          status: 'reconciled',
          observedAt: now,
          remaining: zero,
        ),
        DashboardReconciliation.fromRow({
          'account_id': 'bank',
          'status': 'legacy_unfrozen',
          'observed_at': '2026-09-01T00:00:00Z',
          'remaining_difference': null,
        }),
      ];
      expect(cases.last.remaining, isNull);
      expect(
        alerts(accounts: [account()], cases: cases).single.title,
        'Écart de rapprochement',
      );
      expect(alerts(accounts: [account()], cases: [cases[1]]), isEmpty);
    },
  );
  test('cash with no inventory gets cash wording', () {
    expect(
      alerts(accounts: [account(type: FinancialAccountType.cash)]).single.title,
      'Espèces à contrôler',
    );
  });
  test('goal alerts use existing goal and projection, not second forecast', () {
    final result = alerts(goals: [goal()]);
    expect(
      result.map((a) => a.title),
      containsAll(['Objectif en retard', 'Objectif sans financement sécurisé']),
    );
  });
  test('active PRIOS without capacity alerts without financial action', () {
    final plan = PriorityPlanView(
      plan: PriorityPlan(
        id: 'p',
        householdId: 'real',
        name: 'Plan',
        status: PriorityPlanStatus.active,
        createdBy: 'm',
        createdAt: now,
        updatedAt: now,
      ),
      items: [],
    );
    expect(
      alerts(plan: plan).single.destination,
      DashboardDestination.priorities,
    );
  });
  test(
    'read gateway is household-scoped GET-only with stable paginated ordering',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.url.queryParameters['household_id'], 'eq.real');
          expect(request.url.queryParameters['order'], contains('.asc.'));
          final rows = request.url.path.endsWith('financial_transactions')
              ? [
                  {
                    'type': 'income',
                    'amount': 100,
                    'occurred_at': '2026-10-01T12:00:00Z',
                  },
                ]
              : [
                  {
                    'account_id': 'bank',
                    'status': 'legacy_unfrozen',
                    'observed_at': '2026-09-01T00:00:00Z',
                    'remaining_difference': null,
                  },
                ];
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final gateway = SupabaseDashboardHistoryGateway(client);
      expect(
        (await gateway.transactions(
          'real',
          DateTime(2026, 10),
          DateTime(2026, 11),
        )).length,
        1,
      );
      expect((await gateway.reconciliations('real')).single.remaining, isNull);
      expect(requests.length, 2);
    },
  );
  test(
    'provider reload on household switch never reuses archived household history',
    () async {
      final current = StateProvider<String>((ref) => 'real');
      final seen = <String>[];
      final container = ProviderContainer(
        overrides: [
          activeHouseholdProvider.overrideWith((ref) async {
            final id = ref.watch(current);
            return ActiveHouseholdState(
              status: ActiveHouseholdStatus.singleHousehold,
              householdId: id,
              householdIds: [id],
            );
          }),
          dashboardHistoryGatewayProvider.overrideWithValue(_History(seen)),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        dashboardHistoryProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(await container.read(dashboardHistoryProvider.future), isEmpty);
      container.read(current.notifier).state = 'other-operational';
      expect(await container.read(dashboardHistoryProvider.future), isEmpty);
      expect(seen, ['real', 'other-operational']);
    },
  );
  test('dashboard files expose no financial mutation or RPC', () {
    for (final f
        in Directory('lib/features/dashboard')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = f.readAsStringSync();
      for (final token in [
        '.rpc(',
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
      ]) {
        expect(source, isNot(contains(token)), reason: f.path);
      }
    }
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'dashboard empty and populated responsive $width, period UI updates',
      (tester) async {
        final diagnostics = <String>[];
        final originalHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          diagnostics.add(details.toString());
          originalHandler!(details);
        };
        addTearDown(() => FlutterError.onError = originalHandler);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var populated = false;
        final container = ProviderContainer(
          overrides: [
            financialDashboardProvider.overrideWith(
              (ref) async => snapshot(
                period: ref.watch(dashboardPeriodProvider),
                populated: populated,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: FinancialDashboardPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dashboard-v2-empty')), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Mois précédent'));
        await tester.pumpAndSettle();
        expect(
          container.read(dashboardPeriodProvider),
          DashboardPeriod.previousMonth,
        );
        populated = true;
        container.invalidate(financialDashboardProvider);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dashboard-v2-empty')), findsNothing);
        expect(find.text('À faire'), findsOneWidget);
        for (var i = 0; i < 18; i++) {
          await tester.drag(
            find.byKey(const Key('financial-dashboard-page')),
            const Offset(0, -450),
          );
          await tester.pumpAndSettle();
          final exception = tester.takeException();
          expect(exception, isNull, reason: diagnostics.join('\n'));
        }
      },
    );
  }
}

class _History implements DashboardHistoryGateway {
  _History(this.seen);
  final List<String> seen;
  @override
  Future<List<Map<String, Object?>>> transactions(
    String householdId,
    DateTime start,
    DateTime end,
  ) async {
    seen.add(householdId);
    return [];
  }

  @override
  Future<List<DashboardReconciliation>> reconciliations(
    String householdId,
  ) async => [];
}
