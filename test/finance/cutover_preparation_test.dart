import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/cutover_preparation.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';

const fingerprint =
    '0123456789012345678901234567890123456789012345678901234567890123';

void main() {
  test('les candidats ne deviennent jamais confirmés automatiquement', () {
    final preparation = const CutoverPreparationBuilder().build(_analysis());

    expect(preparation.accounts, hasLength(5));
    expect(preparation.envelopes, hasLength(26));
    expect(preparation.accounts.every((item) => !item.isConfirmed), isTrue);
    expect(preparation.envelopes.every((item) => !item.isConfirmed), isTrue);
    expect(preparation.effectiveDate, isNull);
    expect(preparation.canPrepareFuturePlan, isFalse);
    expect(
      const CutoverPreparationBuilder().isRealCutoverSource(_analysis()),
      isTrue,
    );
  });

  test(
    'un solde réel édité reste distinct du candidat et son écart est local',
    () {
      final preparation = const CutoverPreparationBuilder().build(_analysis());
      final account = preparation.accounts.first;
      final changed = preparation.updateAccount(
        account.copyWith(confirmedAmount: 1234.5),
      );

      expect(changed.accounts.first.candidateAmount, isNull);
      expect(changed.accounts.first.confirmedAmount, 1234.5);
      expect(changed.accounts.first.isConfirmed, isFalse);
      expect(changed.confirmedAccountsTotal, 1234.5);
    },
  );

  test(
    'À répartir est une position indépendante sans compensation de ledger',
    () {
      final preparation = const CutoverPreparationBuilder().build(_analysis());
      final toAllocate = preparation.envelopes.singleWhere(
        (item) => item.isToAllocate,
      );
      final changed = preparation.updateEnvelope(
        toAllocate.copyWith(confirmedAmount: 50, isConfirmed: true),
      );

      expect(toAllocate.name, 'À répartir');
      expect(changed.confirmedEnvelopesTotal, 50);
      expect(changed.confirmedAccountsTotal, 0);
      expect(changed.envelopesDifference, 50);
    },
  );

  test('une obligation non confirmée exclut toute préparation future', () {
    final base = const CutoverPreparationBuilder().build(_analysis());
    final debt = base.obligations.first.copyWith(exists: true);
    final preparation = base.copyWith(
      effectiveDate: DateTime(2026, 9, 16),
      accounts: base.accounts
          .map((item) => item.copyWith(confirmedAmount: 0, isConfirmed: true))
          .toList(),
      envelopes: base.envelopes
          .map((item) => item.copyWith(confirmedAmount: 0, isConfirmed: true))
          .toList(),
      obligations: [debt, ...base.obligations.skip(1)],
    );

    expect(preparation.remainingConfirmations, 1);
    expect(preparation.canPrepareFuturePlan, isFalse);
  });

  test('les obligations de scénario restent ambiguës et non automatiques', () {
    final preparation = const CutoverPreparationBuilder().build(_analysis());
    final parentNora = preparation.obligations.first;
    final car = preparation.obligations.last;

    expect(
      parentNora.classification,
      CutoverObligationClassification.ambiguous,
    );
    expect(parentNora.candidateAmount, 40000);
    expect(parentNora.exists, isFalse);
    expect(
      car.classification,
      CutoverObligationClassification.nonImportableAutomatically,
    );
    expect(car.candidateAmount, isNull);
    expect(car.exists, isFalse);
    expect(preparation.remainingConfirmations, 31);
  });

  test('les salaires de référence ne sont pas des encaissements', () {
    final preparation = const CutoverPreparationBuilder().build(_analysis());

    expect(preparation.incomes.map((item) => item.candidateAmount), [
      12800,
      15000,
    ]);
    expect(preparation.incomes.every((item) => item.isConfiguration), isTrue);
    expect(preparation.incomes.every((item) => !item.isActive), isTrue);
    expect(preparation.incomes.every((item) => !item.isConfirmed), isTrue);
  });
}

WorkbookImportAnalysis _analysis() => const WorkbookImportAnalysis(
  fileName: 'source.xlsx',
  sourceFingerprint: fingerprint,
  sheetPreviews: [],
  unhandledSheetNames: [],
  sourceSheets: [
    SourceSheetSnapshot(
      sourceSheetName: 'Enveloppes',
      cells: [
        SourceCellSnapshot(coordinate: 'B17', value: 'Traite maison'),
        SourceCellSnapshot(coordinate: 'B18', value: 'Traite normale'),
        SourceCellSnapshot(coordinate: 'B19', value: 'TSC'),
        SourceCellSnapshot(coordinate: 'B20', value: 'Syndic'),
        SourceCellSnapshot(coordinate: 'B21', value: 'Eau elec abonnement'),
        SourceCellSnapshot(coordinate: 'B22', value: 'Mouton'),
        SourceCellSnapshot(coordinate: 'B23', value: 'Ecole Niece'),
        SourceCellSnapshot(coordinate: 'B24', value: 'Parrents'),
        SourceCellSnapshot(coordinate: 'B25', value: 'Parrents Nora'),
        SourceCellSnapshot(coordinate: 'B26', value: 'Traite voiture'),
        SourceCellSnapshot(coordinate: 'B27', value: 'Wifi'),
        SourceCellSnapshot(coordinate: 'B28', value: 'Besoin perso'),
        SourceCellSnapshot(coordinate: 'B29', value: 'Nourriture'),
        SourceCellSnapshot(coordinate: 'B30', value: 'Habits'),
        SourceCellSnapshot(coordinate: 'B31', value: 'Imprévus'),
        SourceCellSnapshot(coordinate: 'B32', value: 'Voyages'),
        SourceCellSnapshot(coordinate: 'B33', value: 'Sorties WE'),
        SourceCellSnapshot(coordinate: 'B34', value: 'Fêtes religieuses'),
        SourceCellSnapshot(coordinate: 'B35', value: 'Navette'),
        SourceCellSnapshot(coordinate: 'B36', value: 'Epargne'),
        SourceCellSnapshot(
          coordinate: 'B37',
          value: 'Reste epargne (primes Ibrahim et Nora)',
        ),
        SourceCellSnapshot(coordinate: 'B38', value: 'Vidange'),
        SourceCellSnapshot(coordinate: 'B39', value: 'Entretien'),
        SourceCellSnapshot(coordinate: 'B40', value: 'Assurance'),
        SourceCellSnapshot(coordinate: 'B41', value: 'Vignette'),
      ],
    ),
  ],
);
