import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/financial_availability/domain/financial_availability.dart';
import 'package:noyau_app/features/wealth/application/providers/home_auto_provider.dart';
import 'package:noyau_app/features/wealth/application/providers/wealth_provider.dart';
import 'package:noyau_app/features/wealth/domain/wealth_models.dart';
import 'package:noyau_app/features/wealth/presentation/wealth_page.dart';

void main() {
  testWidgets(
    'logement et véhicules restent responsive et vides sans écriture',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const zero = Money.fromMinorUnits(0);
      final wealth = WealthData(
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
      const specialized = HomeAutoData(
        homeProfiles: [],
        vehicleProfiles: [],
        benefits: [],
        expenses: [],
        costPlans: [],
        mileage: [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wealthDataProvider.overrideWith((ref) async => wealth),
            homeAutoDataProvider.overrideWith((ref) async => specialized),
          ],
          child: const MaterialApp(home: WealthPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Logement'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun actif immobilier'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Véhicules'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun véhicule'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
