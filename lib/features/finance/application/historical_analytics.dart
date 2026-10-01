import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'workbook_import.dart';

enum HistoricalAnalyticClassification {
  expense,
  budgetFunding,
  internalTransfer,
  ambiguousPositive,
  technicalAdjustment,
  ignored,
  validatedIncome,
}

enum HistoricalAnalyticConfidence { high, medium, low }

enum HistoricalAnalyticRepetition { strictSource, businessSimilarity }

class HistoricalAnalyticLine {
  const HistoricalAnalyticLine({
    required this.sourceRowNumber,
    required this.occurredOn,
    required this.sourceEnvelopeLabel,
    required this.mappedEnvelopeLabel,
    required this.sourceAmount,
    required this.classification,
    required this.analyticalAmount,
    required this.detail,
    required this.confidence,
    required this.proposalReason,
    required this.sourceContentHash,
    this.transferGroupKey,
    this.duplicateCandidateKey,
    this.repetition,
  });

  final int sourceRowNumber;
  final DateTime occurredOn;
  final String sourceEnvelopeLabel;
  final String mappedEnvelopeLabel;
  final double sourceAmount;
  final HistoricalAnalyticClassification classification;
  final double analyticalAmount;
  final String detail;
  final HistoricalAnalyticConfidence confidence;
  final String proposalReason;
  final String sourceContentHash;
  final String? transferGroupKey;
  final String? duplicateCandidateKey;
  final HistoricalAnalyticRepetition? repetition;

  Map<String, Object?> toCommitJson() => {
    'source_row_number': sourceRowNumber,
    'source_content_hash': sourceContentHash,
    'occurred_on': occurredOn.toIso8601String().substring(0, 10),
    'source_envelope_label': sourceEnvelopeLabel,
    'source_amount': sourceAmount,
    'classification': classification.dbValue,
    'analytical_amount': analyticalAmount,
    'detail': detail,
    'confidence': confidence.name,
    'proposal_reason': proposalReason,
    if (transferGroupKey != null) 'transfer_group_key': transferGroupKey,
    if (duplicateCandidateKey != null)
      'duplicate_candidate_key': duplicateCandidateKey,
  };
}

extension HistoricalAnalyticClassificationPresentation
    on HistoricalAnalyticClassification {
  String get dbValue => switch (this) {
    HistoricalAnalyticClassification.budgetFunding => 'budget_funding',
    HistoricalAnalyticClassification.internalTransfer => 'internal_transfer',
    HistoricalAnalyticClassification.ambiguousPositive => 'ambiguous_positive',
    HistoricalAnalyticClassification.technicalAdjustment =>
      'technical_adjustment',
    HistoricalAnalyticClassification.validatedIncome => 'validated_income',
    _ => name,
  };

  String get label => switch (this) {
    HistoricalAnalyticClassification.expense => 'Dépense analytique',
    HistoricalAnalyticClassification.budgetFunding => 'Alimentation budget',
    HistoricalAnalyticClassification.internalTransfer => 'Transfert interne',
    HistoricalAnalyticClassification.ambiguousPositive => 'Positif ambigu',
    HistoricalAnalyticClassification.technicalAdjustment =>
      'Ajustement technique',
    HistoricalAnalyticClassification.ignored => 'Ignoré',
    HistoricalAnalyticClassification.validatedIncome => 'Revenu validé',
  };
}

class HistoricalAnalyticsPreview {
  const HistoricalAnalyticsPreview({
    required this.lines,
    required this.periodStart,
    required this.periodEnd,
  });

  final List<HistoricalAnalyticLine> lines;
  final DateTime periodStart;
  final DateTime periodEnd;

  int count(HistoricalAnalyticClassification value) =>
      lines.where((line) => line.classification == value).length;
  double amount(HistoricalAnalyticClassification value) => lines
      .where((line) => line.classification == value)
      .fold(0, (sum, line) => sum + line.analyticalAmount);
  int get duplicateCandidates =>
      lines.where((line) => line.duplicateCandidateKey != null).length;
  int repetitionLineCount(HistoricalAnalyticRepetition value) =>
      lines.where((line) => line.repetition == value).length;
  int repetitionGroupCount(HistoricalAnalyticRepetition value) => lines
      .where((line) => line.repetition == value)
      .map((line) => line.duplicateCandidateKey)
      .whereType<String>()
      .toSet()
      .length;
}

class HistoricalAnalyticsPreviewBuilder {
  const HistoricalAnalyticsPreviewBuilder();

  HistoricalAnalyticsPreview build(
    WorkbookImportAnalysis analysis, {
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    periodStart ??= DateTime(2026, 5, 1);
    periodEnd ??= DateTime(2026, 9, 29);
    final journal = analysis.sourceSheets
        .where((sheet) => _norm(sheet.sourceSheetName) == 'journal')
        .firstOrNull;
    if (journal == null) {
      return HistoricalAnalyticsPreview(
        lines: const [],
        periodStart: periodStart,
        periodEnd: periodEnd,
      );
    }
    final byRow = <int, Map<String, String>>{};
    for (final cell in journal.cells) {
      final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(cell.coordinate);
      if (match == null || !const {'B', 'C', 'D', 'E'}.contains(match[1])) {
        continue;
      }
      byRow.putIfAbsent(int.parse(match[2]!), () => {})[match[1]!] = cell.value
          .trim();
    }
    final raw = <_RawLine>[];
    for (final entry in byRow.entries) {
      final values = entry.value;
      final date = _date(values['B']);
      final amount = _amount(values['D']);
      final envelope = values['C']?.trim() ?? '';
      final detail = values['E']?.trim() ?? '';
      if (date == null || amount == null || amount == 0 || envelope.isEmpty) {
        continue;
      }
      final day = DateTime(date.year, date.month, date.day);
      if (day.isBefore(periodStart) || day.isAfter(periodEnd)) continue;
      raw.add(
        _RawLine(
          row: entry.key,
          date: day,
          envelope: envelope,
          amount: amount,
          detail: detail.isEmpty ? 'Sans détail' : detail,
        ),
      );
    }

    final transferKeys = <int, String>{};
    final transferGroups = <String, List<_RawLine>>{};
    for (final line in raw) {
      final key = '${_day(line.date)}|${_norm(line.detail)}';
      transferGroups.putIfAbsent(key, () => []).add(line);
    }
    for (final entry in transferGroups.entries) {
      final group = entry.value;
      final sum = group.fold<double>(0, (value, line) => value + line.amount);
      if (group.any((line) => line.amount < 0) &&
          group.any((line) => line.amount > 0) &&
          sum.abs() < 0.005) {
        final key = sha256.convert(utf8.encode(entry.key)).toString();
        for (final line in group) {
          transferKeys[line.row] = key;
        }
      }
    }

    final duplicateKeys = <int, String>{};
    final repetitions = <int, HistoricalAnalyticRepetition>{};
    final duplicateGroups = <String, List<_RawLine>>{};
    for (final line in raw) {
      if (transferKeys.containsKey(line.row) ||
          _norm(line.detail).contains('alimentation')) {
        continue;
      }
      final key =
          '${_day(line.date)}|${_norm(line.envelope)}|'
          '${line.amount.toStringAsFixed(2)}|${_norm(line.detail)}';
      duplicateGroups.putIfAbsent(key, () => []).add(line);
    }
    for (final entry in duplicateGroups.entries.where(
      (entry) => entry.value.length > 1,
    )) {
      final key = sha256.convert(utf8.encode(entry.key)).toString();
      final rawSignatures = entry.value
          .map(
            (line) =>
                '${_day(line.date)}|${line.envelope}|'
                '${line.amount.toStringAsFixed(2)}|${line.detail}',
          )
          .toSet();
      final repetition = rawSignatures.length == 1
          ? HistoricalAnalyticRepetition.strictSource
          : HistoricalAnalyticRepetition.businessSimilarity;
      for (final line in entry.value) {
        duplicateKeys[line.row] = key;
        repetitions[line.row] = repetition;
      }
    }

    final lines =
        raw
            .map((source) {
              final transferKey = transferKeys[source.row];
              final normalizedDetail = _norm(source.detail);
              late final HistoricalAnalyticClassification classification;
              late final HistoricalAnalyticConfidence confidence;
              late final String reason;
              if (transferKey != null) {
                classification =
                    HistoricalAnalyticClassification.internalTransfer;
                confidence = HistoricalAnalyticConfidence.high;
                reason =
                    'Paire interne de même date et détail, somme nette nulle.';
              } else if ((source.amount - 59630).abs() < 0.005 &&
                  normalizedDetail.contains('syndic') &&
                  normalizedDetail.contains('notaire')) {
                classification =
                    HistoricalAnalyticClassification.technicalAdjustment;
                confidence = HistoricalAnalyticConfidence.high;
                reason =
                    'Ajustement technique Syndic et notaire confirmé hors flux.';
              } else if (RegExp(
                r'adjust|regul|ecart inconnu|reajust',
              ).hasMatch(normalizedDetail)) {
                classification =
                    HistoricalAnalyticClassification.technicalAdjustment;
                confidence = HistoricalAnalyticConfidence.medium;
                reason = 'Libellé identifiant une régularisation technique.';
              } else if (normalizedDetail.contains('alimentation')) {
                classification = HistoricalAnalyticClassification.budgetFunding;
                confidence = HistoricalAnalyticConfidence.high;
                reason = 'Alimentation analytique d’enveloppe, sans revenu.';
              } else if (source.amount > 0) {
                classification =
                    HistoricalAnalyticClassification.ambiguousPositive;
                confidence = HistoricalAnalyticConfidence.low;
                reason =
                    'Montant positif conservé ambigu jusqu’à validation humaine.';
              } else {
                classification = HistoricalAnalyticClassification.expense;
                confidence = HistoricalAnalyticConfidence.high;
                reason = 'Montant négatif retenu comme dépense analytique.';
              }
              final content =
                  '${source.row}|${_day(source.date)}|'
                  '${source.envelope}|${source.amount.toStringAsFixed(2)}|${source.detail}';
              return HistoricalAnalyticLine(
                sourceRowNumber: source.row,
                occurredOn: source.date,
                sourceEnvelopeLabel: source.envelope,
                mappedEnvelopeLabel: _mappedEnvelope(source.envelope),
                sourceAmount: source.amount,
                classification: classification,
                analyticalAmount: source.amount.abs(),
                detail: source.detail,
                confidence: confidence,
                proposalReason: reason,
                sourceContentHash: sha256
                    .convert(utf8.encode(content))
                    .toString(),
                transferGroupKey: transferKey,
                duplicateCandidateKey: duplicateKeys[source.row],
                repetition: repetitions[source.row],
              );
            })
            .toList(growable: false)
          ..sort((a, b) => a.sourceRowNumber.compareTo(b.sourceRowNumber));
    return HistoricalAnalyticsPreview(
      lines: lines,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }
}

class _RawLine {
  const _RawLine({
    required this.row,
    required this.date,
    required this.envelope,
    required this.amount,
    required this.detail,
  });
  final int row;
  final DateTime date;
  final String envelope;
  final double amount;
  final String detail;
}

String _mappedEnvelope(String value) => switch (_norm(value)) {
  'wifi home' || 'wifi' => 'Wifi',
  'besoin personnel' => 'Besoin perso',
  _ => value.trim(),
};

DateTime? _date(String? value) {
  if (value == null) return null;
  final iso = DateTime.tryParse(value);
  if (iso != null) return iso;
  final match = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})').firstMatch(value);
  return match == null
      ? null
      : DateTime(
          int.parse(match[3]!),
          int.parse(match[2]!),
          int.parse(match[1]!),
        );
}

double? _amount(String? value) {
  if (value == null) return null;
  var text = value
      .trim()
      .replaceFirst(RegExp(r'^='), '')
      .replaceAll(RegExp(r'[^0-9,.-]'), '');
  if (text.contains(',') && text.contains('.')) {
    text = text.replaceAll('.', '').replaceAll(',', '.');
  } else {
    text = text.replaceAll(',', '.');
  }
  return double.tryParse(text);
}

String _day(DateTime value) => value.toIso8601String().substring(0, 10);
String _norm(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
