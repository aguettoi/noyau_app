import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/cutover_opening_import.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';

void main() {
  const fingerprint =
      '0123456789012345678901234567890123456789012345678901234567890123';

  test(
    'le plan B1 porte cible explicite, fingerprint et positions fictives',
    () {
      const analysis = WorkbookImportAnalysis(
        fileName: 'fictif.xlsx',
        sourceFingerprint: fingerprint,
        sheetPreviews: [],
        unhandledSheetNames: [],
        sourceSheets: [
          SourceSheetSnapshot(
            sourceSheetName: 'Positions ouverture',
            cells: [
              SourceCellSnapshot(coordinate: 'A1', value: 'Type'),
              SourceCellSnapshot(coordinate: 'B1', value: 'Nom'),
              SourceCellSnapshot(coordinate: 'C1', value: 'Kind'),
              SourceCellSnapshot(coordinate: 'D1', value: 'Montant'),
              SourceCellSnapshot(coordinate: 'A2', value: 'Compte'),
              SourceCellSnapshot(coordinate: 'B2', value: 'Banque A'),
              SourceCellSnapshot(coordinate: 'C2', value: 'bank'),
              SourceCellSnapshot(coordinate: 'D2', value: '1000'),
              SourceCellSnapshot(coordinate: 'A3', value: 'Compte'),
              SourceCellSnapshot(coordinate: 'B3', value: 'Caisse'),
              SourceCellSnapshot(coordinate: 'C3', value: 'cash'),
              SourceCellSnapshot(coordinate: 'D3', value: '200'),
              SourceCellSnapshot(coordinate: 'A4', value: 'Enveloppe'),
              SourceCellSnapshot(coordinate: 'B4', value: 'Nourriture'),
              SourceCellSnapshot(coordinate: 'D4', value: '500'),
              SourceCellSnapshot(coordinate: 'A5', value: 'Enveloppe'),
              SourceCellSnapshot(coordinate: 'B5', value: 'Épargne'),
              SourceCellSnapshot(coordinate: 'D5', value: '250'),
              SourceCellSnapshot(coordinate: 'A6', value: 'Enveloppe'),
              SourceCellSnapshot(coordinate: 'B6', value: 'À répartir'),
              SourceCellSnapshot(coordinate: 'D6', value: '50'),
            ],
          ),
        ],
      );
      final plan = CutoverOpeningPlanBuilder().build(
        analysis: analysis,
        householdId: 'household',
        effectiveDate: DateTime(2026, 9, 14),
        cutoverId: '11111111-1111-4111-8111-111111111111',
      );
      expect(plan.canConfirm, isTrue, reason: plan.blockingErrors.join(' | '));
      expect(plan.householdId, 'household');
      expect(plan.sourceFingerprint, fingerprint);
      expect(plan.accounts, hasLength(2));
      expect(plan.envelopes, hasLength(3));
      expect(plan.envelopes.last.isToAllocate, isTrue);
      expect(plan.confirm(DateTime(2026)).confirmedAt, isNotNull);
    },
  );

  test(
    'les erreurs bloquantes empêchent confirmation et changement de source',
    () {
      const analysis = WorkbookImportAnalysis(
        fileName: 'empty.xlsx',
        sourceFingerprint: fingerprint,
        sheetPreviews: [],
        unhandledSheetNames: [],
        sourceSheets: [],
      );
      final plan = CutoverOpeningPlanBuilder().build(
        analysis: analysis,
        householdId: 'h',
        effectiveDate: DateTime(2026),
      );
      expect(plan.canConfirm, isFalse);
      expect(plan.blockingErrors, isNotEmpty);
    },
  );

  test('un plan complété peut être restauré pour reprendre le même run', () {
    final plan = CutoverOpeningPlan(
      cutoverId: '11111111-1111-4111-8111-111111111111',
      householdId: 'household',
      sourceFingerprint: fingerprint,
      effectiveDate: DateTime(2026, 9, 14),
      accounts: const [
        CutoverOpeningAccount(
          sourceLabel: 'A2',
          name: 'Banque A',
          kind: 'bank',
          openingAmount: 1000,
        ),
      ],
      envelopes: const [
        CutoverOpeningEnvelope(
          sourceLabel: 'A3',
          name: 'Nourriture',
          openingAmount: 500,
          isToAllocate: false,
        ),
      ],
    ).confirm(DateTime(2026, 9, 14, 9, 42));

    final restored = CutoverOpeningPlan.fromJson(
      Map<String, dynamic>.from(plan.toJson()),
    );

    expect(restored.cutoverId, plan.cutoverId);
    expect(restored.sourceFingerprint, plan.sourceFingerprint);
    expect(restored.effectiveDate, plan.effectiveDate);
    expect(restored.confirmedAt, plan.confirmedAt);
    expect(restored.accounts.single.openingAmount, 1000);
    expect(restored.envelopes.single.name, 'Nourriture');
  });
}
