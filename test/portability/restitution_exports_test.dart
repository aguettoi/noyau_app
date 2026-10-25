import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/portability/application/restitution_formatters.dart';
import 'package:noyau_app/features/portability/domain/restitution_models.dart';
import 'package:noyau_app/features/reporting/domain/business_reporting.dart';
import 'package:noyau_app/features/wealth/domain/wealth_models.dart';

void main() {
  group('périodes calendaires', () {
    test('calcule mois, trimestre, semestre et année sans approximation', () {
      final anchor = DateTime(2026, 10, 25);
      expect(
        RestitutionPeriod.forDate(anchor, ReportPeriodicity.monthly).fileKey,
        '2026-10',
      );
      expect(
        RestitutionPeriod.forDate(anchor, ReportPeriodicity.quarterly).fileKey,
        '2026-T4',
      );
      expect(
        RestitutionPeriod.forDate(anchor, ReportPeriodicity.semiannual).fileKey,
        '2026-S2',
      );
      expect(
        RestitutionPeriod.forDate(
          anchor,
          ReportPeriodicity.annual,
        ).endExclusive,
        DateTime(2027),
      );
    });
  });

  test(
    'XLSX métier contient exactement les quatre feuilles et des nombres typés',
    () {
      final bytes = encodeStructuredHouseholdXlsx(_dataset());
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, [
        'Solde enveloppes',
        'Journal',
        'Soldes cash',
        'Dettes et créances',
      ]);
      expect(
        book['Solde enveloppes'].cell(CellIndex.indexByString('B2')).value,
        anyOf(isA<DoubleCellValue>(), isA<IntCellValue>()),
      );
      expect(
        book['Journal'].cell(CellIndex.indexByString('A2')).value,
        isA<DateCellValue>(),
      );
      expect(String.fromCharCodes(bytes), isNot(contains('SECRET_PRIVÉ')));
    },
  );

  test(
    'PDF est valide pour les quatre périodicités et accepte un jeu partiel',
    () async {
      for (final periodicity in ReportPeriodicity.values) {
        final data = _dataset(periodicity: periodicity);
        final bytes = await encodePeriodReportPdf(data);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      }
    },
  );

  test(
    'PPTX est un package OOXML complet, multi-slide et sans donnée privée',
    () {
      final bytes = encodePeriodPresentationPptx(_dataset());
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(
        names,
        containsAll([
          '[Content_Types].xml',
          'ppt/presentation.xml',
          'ppt/slides/slide1.xml',
        ]),
      );
      expect(
        names
            .where(
              (name) =>
                  name.startsWith('ppt/slides/slide') && name.endsWith('.xml'),
            )
            .length,
        greaterThanOrEqualTo(5),
      );
      expect(String.fromCharCodes(bytes), isNot(contains('SECRET_PRIVÉ')));
    },
  );

  test(
    'échéancier exporté reprend les mathématiques canoniques intérêt et murabaha',
    () {
      for (final structure in [
        FinancingStructure.interestLoan,
        FinancingStructure.murabaha,
      ]) {
        final financing = FinancingProfile(
          id: structure.name,
          label: 'Financement',
          structure: structure,
          obligationId: 'obl',
          principalInitial: const Money.fromMinorUnits(1000000),
          remainingLiability: const Money.fromMinorUnits(1000000),
          startDate: DateTime(2026, 1, 1),
          durationMonths: 12,
          periodicityMonths: 1,
          annualRate: structure == FinancingStructure.interestLoan ? .05 : null,
          fixedTotalCost: structure == FinancingStructure.murabaha
              ? const Money.fromMinorUnits(60000)
              : null,
        );
        final schedule = buildFinancingSchedule(financing);
        final bytes = encodeAmortizationXlsx(
          AmortizationExportDataset(financing: financing, schedule: schedule),
        );
        expect(
          Excel.decodeBytes(bytes).tables['Amortissement']!.maxRows,
          greaterThan(10),
        );
      }
    },
  );

  test('export fiscal distingue explicitement projection et constaté', () {
    final bytes = encodeFiscalHousingXlsx(
      FiscalHousingExportDataset(
        period: RestitutionPeriod.forDate(
          DateTime(2026, 10),
          ReportPeriodicity.annual,
        ),
        rows: [
          FiscalHousingExportRow(
            periodStart: DateTime(2026),
            periodEnd: DateTime(2026, 12, 31),
            recognition: 'Économie fiscale estimée (projection)',
            amount: const Money.fromMinorUnits(10000),
            source: 'Règle versionnée',
          ),
          FiscalHousingExportRow(
            periodStart: DateTime(2026),
            periodEnd: DateTime(2026, 12, 31),
            recognition: 'Avantage fiscal constaté',
            amount: const Money.fromMinorUnits(8000),
            source: 'Flux canonique',
          ),
        ],
        limitations: const ['Non déclaratif'],
      ),
    );
    final sheet = Excel.decodeBytes(bytes)['Fiscalité logement'];
    expect(
      sheet.rows.expand((r) => r).map((c) => c?.value?.toString()).join('|'),
      contains('projection'),
    );
    expect(
      sheet.rows.expand((r) => r).map((c) => c?.value?.toString()).join('|'),
      contains('constaté'),
    );
  });
}

RestitutionDataset _dataset({
  ReportPeriodicity periodicity = ReportPeriodicity.monthly,
}) {
  final period = RestitutionPeriod.forDate(DateTime(2026, 10, 25), periodicity);
  return RestitutionDataset(
    period: period,
    envelopes: const [
      EnvelopeExportRow(
        label: 'Nourriture',
        balance: Money.fromMinorUnits(250000),
        status: 'Active',
        scope: 'Foyer',
        provenance: 'Ledger',
      ),
    ],
    journal: [
      JournalExportRow(
        date: period.start,
        kind: 'Dépenses réalisées',
        label: 'Courses',
        amount: const Money.fromMinorUnits(12000),
        status: ReportFactStatus.observed,
        provenance: 'FinancialEvent',
      ),
    ],
    cashPositions: const [
      CashPositionExportRow(
        label: 'Compte visible',
        kind: 'bank',
        balance: Money.fromMinorUnits(500000),
        scope: 'visible',
        provenance: 'GL autorisé',
      ),
    ],
    obligations: const [
      ObligationExportRow(
        kind: 'Dette',
        label: 'Échéance',
        initialAmount: Money.fromMinorUnits(100000),
        settledAmount: Money.fromMinorUnits(25000),
        remainingAmount: Money.fromMinorUnits(75000),
        status: 'Ouverte',
        provenance: 'Obligation',
      ),
    ],
    timeline: [
      TimelineFact(
        identity: 'x',
        title: 'Fait marquant',
        date: period.start,
        status: ReportFactStatus.observed,
        source: ReportFactSource.financialEvent,
        reason: 'Test',
      ),
    ],
    assets: const [],
    financings: const [],
    netWorth: const Money.fromMinorUnits(425000),
    limitations: const ['Données autorisées uniquement'],
  );
}
