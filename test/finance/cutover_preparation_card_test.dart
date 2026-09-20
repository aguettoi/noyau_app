import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';
import 'package:noyau_app/features/finance/presentation/cutover_preparation_card.dart';

void main() {
  testWidgets(
    'la préparation conserve À répartir indépendant et non confirmé',
    (tester) async {
      tester.view.physicalSize = const Size(480, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                CutoverPreparationCard(
                  analysis: _analysis(),
                  onDirtyChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('start-real-cutover-preparation')));
      await tester.pumpAndSettle();

      expect(find.text('À répartir'), findsOneWidget);
      expect(
        find.textContaining(
          'Aucune différence ne sera compensée automatiquement',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('future-cutover-plan-button')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

WorkbookImportAnalysis _analysis() => const WorkbookImportAnalysis(
  fileName: 'source.xlsx',
  sourceFingerprint:
      '0123456789012345678901234567890123456789012345678901234567890123',
  sheetPreviews: [],
  unhandledSheetNames: [],
  sourceSheets: [
    SourceSheetSnapshot(
      sourceSheetName: 'Enveloppes',
      cells: [
        SourceCellSnapshot(coordinate: 'B17', value: 'Nourriture'),
        SourceCellSnapshot(coordinate: 'B18', value: 'Épargne'),
      ],
    ),
  ],
);
