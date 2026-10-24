import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/financial_availability/domain/financial_availability.dart';
import 'package:noyau_app/features/wealth/application/providers/wealth_provider.dart';
import 'package:noyau_app/features/wealth/domain/wealth_history.dart';
import 'package:noyau_app/features/wealth/domain/wealth_models.dart';
import 'package:noyau_app/features/wealth/presentation/wealth_page.dart';

void main() {
  testWidgets('patrimoine vide reste utilisable sur mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const zero = Money.fromMinorUnits(0);
    final data = WealthData(
      snapshot: const WealthSnapshot(
        liquidity: zero,
        investments: zero,
        assets: zero,
        liabilities: zero,
      ),
      assets: const [],
      investments: const [],
      financings: const [],
      eventCandidates: const [],
      availability: const FinancialAvailabilitySnapshot(
        realLiquidity: zero,
        envelopeTotal: zero,
        toAllocate: zero,
        debtCommitments: zero,
        potentialReceivables: zero,
        goals: {},
        planEntries: {},
        warnings: [],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wealthDataProvider.overrideWith((ref) async => data)],
        child: const MaterialApp(home: WealthPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Valeur nette'), findsOneWidget);
    expect(find.text('Investissements'), findsWidgets);
    await tester.tap(find.widgetWithText(Tab, 'Financements'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun financement configuré'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparateur de financements est accessible et read-only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const zero = Money.fromMinorUnits(0);
    final data = WealthData(
      snapshot: const WealthSnapshot(
        liquidity: zero,
        investments: zero,
        assets: zero,
        liabilities: zero,
      ),
      assets: const [],
      investments: const [],
      financings: const [],
      eventCandidates: const [],
      availability: const FinancialAvailabilitySnapshot(
        realLiquidity: Money.fromMinorUnits(5000000),
        envelopeTotal: zero,
        toAllocate: zero,
        debtCommitments: zero,
        potentialReceivables: zero,
        goals: {},
        planEntries: {},
        warnings: [],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wealthDataProvider.overrideWith((ref) async => data)],
        child: const MaterialApp(home: WealthPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Financements'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-financing-comparison')));
    await tester.pumpAndSettle();
    expect(
      find.text('Comparer des simulations de financement'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('financing-offer-0')), findsOneWidget);
    expect(find.byKey(const Key('financing-offer-1')), findsOneWidget);
    expect(find.textContaining('Aucune dette'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('financed-amount-0')),
      '100000',
    );
    await tester.enterText(
      find.byKey(const Key('financed-amount-1')),
      '120000',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('compare-financing-offers')),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('compare-financing-offers')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('financing-comparison-results')),
      findsOneWidget,
    );
    expect(
      find.textContaining('ne désignent pas automatiquement'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('historique et échéancier sont accessibles sans écriture', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const zero = Money.fromMinorUnits(0);
    final data = WealthData(
      snapshot: const WealthSnapshot(
        liquidity: zero,
        investments: zero,
        assets: zero,
        liabilities: zero,
      ),
      assets: const [],
      investments: const [],
      financings: const [],
      eventCandidates: const [],
      availability: const FinancialAvailabilitySnapshot(
        realLiquidity: zero,
        envelopeTotal: zero,
        toAllocate: zero,
        debtCommitments: zero,
        potentialReceivables: zero,
        goals: {},
        planEntries: {},
        warnings: [],
      ),
      history: [
        WealthHistoryPoint(
          date: DateTime(2026, 10, 24),
          assets: zero,
          investments: zero,
          liquidity: zero,
          liabilities: zero,
          isComplete: true,
          explanations: const ['Situation actuelle canonique'],
        ),
      ],
      consolidatedDues: [
        ConsolidatedDue(
          identity: 'expected:test',
          label: 'Échéance test',
          date: DateTime(2026, 10, 31),
          amount: const Money.fromMinorUnits(10000),
          kind: ConsolidatedDueKind.expected,
          state: ConsolidatedDueState.expected,
          sourceId: 'test',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wealthDataProvider.overrideWith((ref) async => data)],
        child: const MaterialApp(home: WealthPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Historique & échéances'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wealth-history-and-dues')), findsOneWidget);
    expect(find.text('Échéance test'), findsOneWidget);
    expect(find.byKey(const Key('export-wealth-history')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
