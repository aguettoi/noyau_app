import '../../../core/money/money.dart';
import '../../reporting/domain/business_reporting.dart';
import '../../wealth/domain/wealth_models.dart';

enum ReportPeriodicity { monthly, quarterly, semiannual, annual }

class RestitutionPeriod {
  const RestitutionPeriod({
    required this.start,
    required this.endExclusive,
    required this.periodicity,
  });

  factory RestitutionPeriod.forDate(
    DateTime anchor,
    ReportPeriodicity periodicity,
  ) {
    final month = switch (periodicity) {
      ReportPeriodicity.monthly => anchor.month,
      ReportPeriodicity.quarterly => ((anchor.month - 1) ~/ 3) * 3 + 1,
      ReportPeriodicity.semiannual => anchor.month <= 6 ? 1 : 7,
      ReportPeriodicity.annual => 1,
    };
    final span = switch (periodicity) {
      ReportPeriodicity.monthly => 1,
      ReportPeriodicity.quarterly => 3,
      ReportPeriodicity.semiannual => 6,
      ReportPeriodicity.annual => 12,
    };
    return RestitutionPeriod(
      start: DateTime(anchor.year, month),
      endExclusive: DateTime(anchor.year, month + span),
      periodicity: periodicity,
    );
  }

  final DateTime start;
  final DateTime endExclusive;
  final ReportPeriodicity periodicity;

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(endExclusive);

  String get fileKey {
    String two(int value) => value.toString().padLeft(2, '0');
    return switch (periodicity) {
      ReportPeriodicity.monthly => '${start.year}-${two(start.month)}',
      ReportPeriodicity.quarterly =>
        '${start.year}-T${((start.month - 1) ~/ 3) + 1}',
      ReportPeriodicity.semiannual =>
        '${start.year}-S${start.month == 1 ? 1 : 2}',
      ReportPeriodicity.annual => '${start.year}',
    };
  }

  String get label => switch (periodicity) {
    ReportPeriodicity.monthly =>
      '${start.month.toString().padLeft(2, '0')}/${start.year}',
    ReportPeriodicity.quarterly =>
      'Trimestre ${((start.month - 1) ~/ 3) + 1} ${start.year}',
    ReportPeriodicity.semiannual =>
      'Semestre ${start.month == 1 ? 1 : 2} ${start.year}',
    ReportPeriodicity.annual => 'Année ${start.year}',
  };
}

class EnvelopeExportRow {
  const EnvelopeExportRow({
    required this.label,
    required this.balance,
    required this.status,
    required this.scope,
    required this.provenance,
  });
  final String label;
  final Money balance;
  final String status;
  final String scope;
  final String provenance;
}

class JournalExportRow {
  const JournalExportRow({
    required this.date,
    required this.kind,
    required this.label,
    required this.amount,
    required this.status,
    required this.provenance,
    this.actor,
  });
  final DateTime date;
  final String kind;
  final String label;
  final Money amount;
  final ReportFactStatus status;
  final String provenance;
  final String? actor;
}

class CashPositionExportRow {
  const CashPositionExportRow({
    required this.label,
    required this.kind,
    required this.balance,
    required this.scope,
    required this.provenance,
  });
  final String label;
  final String kind;
  final Money balance;
  final String scope;
  final String provenance;
}

class ObligationExportRow {
  const ObligationExportRow({
    required this.kind,
    required this.label,
    required this.initialAmount,
    required this.settledAmount,
    required this.remainingAmount,
    required this.status,
    required this.provenance,
    this.counterparty,
    this.dueAt,
  });
  final String kind;
  final String label;
  final Money initialAmount;
  final Money settledAmount;
  final Money remainingAmount;
  final String status;
  final String provenance;
  final String? counterparty;
  final DateTime? dueAt;
}

class RestitutionDataset {
  const RestitutionDataset({
    required this.period,
    required this.envelopes,
    required this.journal,
    required this.cashPositions,
    required this.obligations,
    required this.timeline,
    required this.assets,
    required this.financings,
    required this.netWorth,
    required this.limitations,
  });
  final RestitutionPeriod period;
  final List<EnvelopeExportRow> envelopes;
  final List<JournalExportRow> journal;
  final List<CashPositionExportRow> cashPositions;
  final List<ObligationExportRow> obligations;
  final List<TimelineFact> timeline;
  final List<WealthAsset> assets;
  final List<FinancingProfile> financings;
  final Money netWorth;
  final List<String> limitations;

  Money totalFor(String key) => Money.fromMinorUnits(
    journal
        .where((row) => row.kind == key)
        .fold(0, (sum, row) => sum + row.amount.minorUnits),
  );
}

class FiscalHousingExportRow {
  const FiscalHousingExportRow({
    required this.periodStart,
    required this.periodEnd,
    required this.recognition,
    required this.amount,
    required this.source,
    this.rate,
    this.eligibleBase,
    this.ceiling,
    this.effectiveDate,
  });
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? effectiveDate;
  final String recognition;
  final Money amount;
  final double? rate;
  final Money? eligibleBase;
  final Money? ceiling;
  final String source;
}

class FiscalHousingExportDataset {
  const FiscalHousingExportDataset({
    required this.period,
    required this.rows,
    required this.limitations,
  });
  final RestitutionPeriod period;
  final List<FiscalHousingExportRow> rows;
  final List<String> limitations;
}

class AmortizationExportDataset {
  const AmortizationExportDataset({
    required this.financing,
    required this.schedule,
  });
  final FinancingProfile financing;
  final List<FinancingScheduleLine> schedule;
}
