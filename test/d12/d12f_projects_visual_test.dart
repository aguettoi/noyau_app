import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/projects_hub_page.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/financial_availability/application/providers/financial_availability_provider.dart';
import 'package:noyau_app/features/financial_availability/domain/financial_availability.dart';
import 'package:noyau_app/features/priorities/application/providers/remote_priority_plans_provider.dart';
import 'package:noyau_app/features/priorities/domain/priority_plan.dart';
import 'package:noyau_app/features/priorities/presentation/priorities_page.dart';
import 'package:noyau_app/features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import 'package:noyau_app/features/savings_goals/domain/savings_goal.dart';
import 'package:noyau_app/features/savings_goals/presentation/savings_goals_page.dart';
import 'package:noyau_app/features/wealth/application/providers/wealth_provider.dart';
import 'package:noyau_app/features/wealth/domain/wealth_models.dart';
import 'package:noyau_app/features/wealth/presentation/wealth_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!Platform.isWindows) return;
    final bytes = await File(r'C:\Windows\Fonts\tahoma.ttf').readAsBytes();
    final loader = FontLoader('D12FArabic')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final proofs = <_Proof>[
    const _Proof('01_hub_desktop', _Surface.hub, Size(1280, 800)),
    const _Proof('02_hub_mobile', _Surface.hub, Size(390, 844)),
    const _Proof('03_goals_desktop', _Surface.goals, Size(1280, 800)),
    const _Proof('04_goals_mobile', _Surface.goals, Size(390, 844)),
    const _Proof('05_goal_creation_edit', _Surface.goals, Size(900, 760)),
    const _Proof('06_goal_progress', _Surface.goals, Size(900, 760)),
    const _Proof('07_prios_desktop', _Surface.priorities, Size(1280, 800)),
    const _Proof('08_prios_mobile', _Surface.priorities, Size(390, 844)),
    const _Proof('09_prio_detail', _Surface.priorities, Size(900, 760)),
    const _Proof('10_simulations_hub', _Surface.financing, Size(900, 760)),
    const _Proof(
      '11_financing_simulation',
      _Surface.comparison,
      Size(1280, 850),
    ),
    const _Proof('12_simulation_result', _Surface.comparison, Size(1280, 850)),
    const _Proof('13_comparison_desktop', _Surface.comparison, Size(1280, 850)),
    const _Proof('14_comparison_mobile', _Surface.comparison, Size(390, 844)),
    const _Proof('15_murabaha', _Surface.comparison, Size(900, 800)),
    const _Proof('16_schedule_summary', _Surface.financing, Size(900, 760)),
    const _Proof('17_schedule_detail', _Surface.schedule, Size(1280, 800)),
    const _Proof('18_wealth_desktop', _Surface.wealth, Size(1280, 800)),
    const _Proof('19_wealth_mobile', _Surface.wealth, Size(390, 844)),
    const _Proof('20_assets_liabilities', _Surface.wealth, Size(900, 760)),
    const _Proof('21_valuation', _Surface.wealth, Size(900, 760)),
    const _Proof('22_investment', _Surface.investments, Size(900, 760)),
    const _Proof('23_privacy_hidden', _Surface.hub, Size(900, 760)),
    const _Proof('24_one_member', _Surface.goals, Size(900, 760)),
    const _Proof('25_five_members', _Surface.priorities, Size(900, 760)),
    const _Proof('26_empty', _Surface.goalsEmpty, Size(390, 844)),
    const _Proof('27_dark', _Surface.hub, Size(900, 760), dark: true),
    const _Proof('28_rtl_arabic', _Surface.hub, Size(900, 760), arabic: true),
  ];

  for (final proof in proofs) {
    testWidgets('D1.2-F runtime proof ${proof.name}', (tester) async {
      await _pump(tester, proof);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('runtime_goldens/d12f_${proof.name}.png'),
      );
    });
  }
}

Future<void> _pump(WidgetTester tester, _Proof proof) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = proof.size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final language = proof.arabic ? AppLanguage.arabic : AppLanguage.french;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appLocaleProvider.overrideWith(
          (ref) =>
              AppLocaleController(environmentLocales: () => [language.locale]),
        ),
        savingsGoalsProvider.overrideWith(
          (ref) async =>
              proof.surface == _Surface.goalsEmpty ? const [] : [_goal()],
        ),
        priorityPlansProvider.overrideWith((ref) async => [_priority()]),
        financialAvailabilityProvider.overrideWith(
          (ref) async => _availability,
        ),
        wealthDataProvider.overrideWith((ref) async => _wealth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: language.locale,
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(fontFamily: 'D12FArabic'),
        darkTheme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'D12FArabic'),
        ),
        themeMode: proof.dark ? ThemeMode.dark : ThemeMode.light,
        home: _page(proof.surface),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (proof.surface == _Surface.comparison) {
    await tester.tap(find.byKey(const Key('open-financing-comparison')));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }
}

Widget _page(_Surface surface) => switch (surface) {
  _Surface.hub => Scaffold(
    body: ProjectsHubPage(
      onOpenGoals: () {},
      onOpenPriorities: () {},
      onOpenSimulations: () {},
      onOpenFinancings: () {},
      onOpenWealth: () {},
    ),
  ),
  _Surface.goals ||
  _Surface.goalsEmpty => const Scaffold(body: SavingsGoalsPage()),
  _Surface.priorities => const Scaffold(body: PrioritiesPage()),
  _Surface.wealth => const WealthPage(),
  _Surface.investments => const WealthPage(initialTab: 1),
  _Surface.financing || _Surface.comparison => const WealthPage(initialTab: 2),
  _Surface.schedule => const WealthPage(initialTab: 5),
};

SavingsGoalProgress _goal() => SavingsGoalProgress(
  goal: SavingsGoal(
    id: 'goal',
    householdId: 'household',
    name: 'Projet familial',
    type: SavingsGoalType.majorPurchase,
    targetAmount: Money.fromDirhams(100000),
    targetDate: DateTime(2027, 6, 1),
    priority: 1,
    status: SavingsGoalStatus.active,
    fundingEnvelopeId: 'envelope',
    createdBy: 'member',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  envelopeName: 'Projet',
  accumulated: Money.fromDirhams(42000),
);

PriorityPlanView _priority() => PriorityPlanView(
  plan: PriorityPlan(
    id: 'plan',
    householdId: 'household',
    name: 'Décisions du foyer',
    status: PriorityPlanStatus.active,
    monthlyCapacity: Money.fromDirhams(3000),
    notes: 'Priorités actives et prochaines actions',
    createdBy: 'member',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  items: const [],
);

const _availability = FinancialAvailabilitySnapshot(
  realLiquidity: Money.fromMinorUnits(5000000),
  envelopeTotal: Money.fromMinorUnits(0),
  toAllocate: Money.fromMinorUnits(0),
  debtCommitments: Money.fromMinorUnits(0),
  potentialReceivables: Money.fromMinorUnits(0),
  goals: {},
  planEntries: {},
  warnings: [],
);

final _wealth = WealthData(
  snapshot: const WealthSnapshot(
    liquidity: Money.fromMinorUnits(5000000),
    investments: Money.fromMinorUnits(3000000),
    assets: Money.fromMinorUnits(15000000),
    liabilities: Money.fromMinorUnits(7000000),
  ),
  assets: [
    WealthAsset(
      id: 'asset',
      label: 'Logement principal',
      type: WealthAssetType.realEstate,
      ownershipType: WealthOwnershipType.household,
      currentValue: Money.fromDirhams(150000),
      valuationDate: DateTime(2026, 11, 1),
    ),
  ],
  investments: const [
    InvestmentPosition(
      id: 'investment',
      label: 'Placement long terme',
      currentValue: Money.fromMinorUnits(3000000),
      contributed: Money.fromMinorUnits(2500000),
      withdrawn: Money.fromMinorUnits(0),
      distributions: Money.fromMinorUnits(0),
      taxes: Money.fromMinorUnits(0),
    ),
  ],
  financings: [
    FinancingProfile(
      id: 'financing',
      label: 'Financement immobilier',
      structure: FinancingStructure.murabaha,
      obligationId: 'obligation',
      principalInitial: Money.fromDirhams(100000),
      remainingLiability: Money.fromDirhams(70000),
      startDate: DateTime(2025),
      durationMonths: 120,
      periodicityMonths: 1,
      fixedTotalCost: Money.fromDirhams(20000),
      scheduledPayment: Money.fromDirhams(1000),
    ),
  ],
  eventCandidates: const [],
  availability: _availability,
);

enum _Surface {
  hub,
  goals,
  goalsEmpty,
  priorities,
  wealth,
  investments,
  financing,
  comparison,
  schedule,
}

class _Proof {
  const _Proof(
    this.name,
    this.surface,
    this.size, {
    this.dark = false,
    this.arabic = false,
  });
  final String name;
  final _Surface surface;
  final Size size;
  final bool dark;
  final bool arabic;
}
