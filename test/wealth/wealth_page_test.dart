import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/financial_availability/domain/financial_availability.dart';
import 'package:noyau_app/features/wealth/application/providers/wealth_provider.dart';
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
}
