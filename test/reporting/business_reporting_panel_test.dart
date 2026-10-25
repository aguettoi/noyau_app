import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/monthly_close/domain/monthly_close.dart';
import 'package:noyau_app/features/reporting/application/reporting_provider.dart';
import 'package:noyau_app/features/reporting/domain/business_reporting.dart';
import 'package:noyau_app/features/reporting/presentation/business_reporting_panel.dart';

void main() {
  final data = ReportingData(
    report: BusinessPeriodReport(
      period: ReportingPeriod.month(DateTime(2026, 10)),
      categories: [
        BusinessReportCategory(
          key: 'income',
          label: 'Revenus réalisés',
          total: Money.fromDirhams(1200),
          count: 1,
          status: ReportFactStatus.observed,
        ),
      ],
      closeStatus: MonthlyCloseStatus.open,
      blockers: 0,
      warnings: 0,
      isPartial: true,
      explanations: const ['Source canonique filtrée côté serveur'],
    ),
    timeline: [
      TimelineFact(
        identity: 'obligation:o1',
        title: 'Échéance logement',
        date: DateTime(2026, 10, 20),
        amount: Money.fromDirhams(500),
        status: ReportFactStatus.expected,
        source: ReportFactSource.obligation,
        reason: 'Échéance attendue sur la période',
      ),
    ],
  );

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedReportingMonthProvider.overrideWith(
            (ref) => DateTime(2026, 10),
          ),
          reportingDataProvider.overrideWith((ref) async => data),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BusinessReportingPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('rapport et timeline sont lisibles sur desktop', (tester) async {
    await pump(tester, const Size(1200, 800));
    expect(find.text('Octobre 2026'), findsOneWidget);
    expect(find.text('Rapport métier'), findsOneWidget);
    expect(find.text('Revenus réalisés'), findsOneWidget);
    expect(find.text('Timeline significative'), findsOneWidget);
    expect(find.text('Échéance logement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('surface reste sans overflow sur largeur mobile', (tester) async {
    await pump(tester, const Size(390, 844));
    expect(find.byKey(const Key('business-reporting-list')), findsOneWidget);
    expect(find.text('Rapport métier'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
