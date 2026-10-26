import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/operational_kpis/application/operational_kpi_provider.dart';
import 'package:noyau_app/features/operational_kpis/domain/operational_kpis.dart';
import 'package:noyau_app/features/operational_kpis/presentation/operational_kpi_panel.dart';

void main() {
  testWidgets(
    'dashboard KPI stays readable on mobile and exposes explanations',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final start = DateTime(2026, 10);
      final end = DateTime(2026, 11);
      final quality = analyzeOperationalQuality(
        periodStart: start,
        periodEndExclusive: end,
        expectedNotMaterialized: 1,
        entries: const [],
        reconciliations: const [],
      );
      final cash = analyzeCashQuality(
        periodStart: start,
        periodEndExclusive: end,
        inventories: const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            operationalKpiProvider.overrideWith(
              (ref) async => OperationalKpiBundle(
                global: quality,
                byMember: {'m1': quality, 'm2': quality, 'm3': quality},
                cash: cash,
                memberNames: const {
                  'm1': 'Membre 1',
                  'm2': 'Membre 2',
                  'm3': 'Membre 3',
                },
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: OperationalKpiPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Qualité et fiabilité'), findsOneWidget);
      expect(find.text('Membre 3'), findsOneWidget);
      expect(find.text('Opérations attendues'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('kpi-explanations')));
      await tester.tap(find.byKey(const Key('kpi-explanations')));
      await tester.pumpAndSettle();
      expect(find.text('Ponctualité de saisie'), findsOneWidget);
    },
  );
}
