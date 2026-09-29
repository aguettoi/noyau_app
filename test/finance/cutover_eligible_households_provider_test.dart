import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/cutover_opening_import.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';
import 'package:noyau_app/features/finance/presentation/import_preview_page.dart';

void main() {
  test(
    'le Cutover liste uniquement les households membres, techniques inclus',
    () async {
      final gateway = _Gateway();
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          cutoverEligibleHouseholdsGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      final households = await container.read(
        cutoverEligibleHouseholdsProvider.future,
      );

      expect(gateway.userId, 'user-1');
      expect(households.map((item) => item.id), [
        'operational-household',
        'technical-household',
      ]);
      expect(households.last.name, 'CUTOVER-B1-E2E');
      expect(households.last.classification, HouseholdClassification.technical);
      expect(households.last.classificationLabel, 'TECHNIQUE');
      expect(households.map((item) => item.id), isNot(contains('non-member')));
    },
  );

  test('sans session, le Cutover ne propose aucun household', () async {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(null),
        cutoverEligibleHouseholdsGatewayProvider.overrideWithValue(_Gateway()),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(cutoverEligibleHouseholdsProvider.future),
      isEmpty,
    );
  });

  testWidgets(
    'le selecteur Cutover propose operational et technique sans changer le foyer actif',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const operationalId = 'operational-household';
      const technicalId = 'technical-household';
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          cutoverEligibleHouseholdsGatewayProvider.overrideWithValue(
            _Gateway(),
          ),
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.singleHousehold,
              householdId: operationalId,
              householdIds: [operationalId],
            ),
          ),
          workbookImportProvider.overrideWith(_ConfirmedCutoverController.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ImportPreviewPage())),
        ),
      );
      await tester.pumpAndSettle();

      final selector = find.byKey(const Key('cutover-household-selector'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();

      expect(find.text('Sandbox — OPÉRATIONNEL'), findsOneWidget);
      expect(find.text('CUTOVER-B1-E2E — TECHNIQUE'), findsOneWidget);

      await tester.tap(find.text('CUTOVER-B1-E2E — TECHNIQUE'));
      await tester.pumpAndSettle();
      expect(find.text('ENVIRONNEMENT TECHNIQUE'), findsOneWidget);

      final active = await container.read(activeHouseholdProvider.future);
      expect(active.householdId, operationalId);
      expect(active.householdIds, [operationalId]);
      expect(active.householdId, isNot(technicalId));
      expect(tester.takeException(), isNull);
    },
  );
}

class _ConfirmedCutoverController extends WorkbookImportController {
  @override
  WorkbookImportState build() => const WorkbookImportState(
    analysis: WorkbookImportAnalysis(
      fileName: 'CUTOVER-B1-E2E.xlsx',
      sourceFingerprint:
          '7029001b145ef672a83d1a642c20eea410ee372141afabf0420a19932bac92bb',
      sheetPreviews: [
        SheetImportPreview(
          importerId: 'cutover-opening-positions',
          sourceSheetName: 'Positions ouverture',
          detectedRecords: 5,
          issues: [],
          isTransactionReady: true,
        ),
      ],
      unhandledSheetNames: [],
      sourceSheets: [],
    ),
    selectedImporterIds: {'cutover-opening-positions'},
    isConfirmed: true,
  );
}

class _Gateway implements CutoverEligibleHouseholdsGateway {
  String? userId;

  @override
  Future<List<CutoverEligibleHousehold>> householdsForUser(String value) async {
    userId = value;
    return const [
      CutoverEligibleHousehold(
        id: 'operational-household',
        name: 'Sandbox',
        classification: HouseholdClassification.operational,
      ),
      CutoverEligibleHousehold(
        id: 'technical-household',
        name: 'CUTOVER-B1-E2E',
        classification: HouseholdClassification.technical,
      ),
    ];
  }
}
