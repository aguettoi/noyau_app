import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/monthly_close/application/monthly_close_provider.dart';
import 'package:noyau_app/features/monthly_close/domain/monthly_close.dart';
import 'package:noyau_app/features/monthly_close/presentation/monthly_close_page.dart';

void main() {
  final snapshot = MonthlyCloseSnapshot(
    month: DateTime(2026, 10),
    status: MonthlyCloseStatus.open,
    issues: const [
      CloseIssue(
        code: 'cash',
        label: 'Inventaire espèces',
        count: 1,
        severity: CloseIssueSeverity.blocker,
        destination: 'Comptes',
      ),
      CloseIssue(
        code: 'receipt',
        label: 'Justificatifs',
        count: 2,
        severity: CloseIssueSeverity.warning,
        destination: 'Historique',
      ),
    ],
  );

  for (final size in [const Size(390, 700), const Size(1280, 800)]) {
    testWidgets('R2 reste lisible sans overflow à ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monthlyCloseProvider.overrideWith((ref) async => snapshot),
          ],
          child: const MaterialApp(home: MonthlyClosePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('monthly-close-page')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('À faire financier'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('À faire financier'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('close-month-button')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('close-month-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
