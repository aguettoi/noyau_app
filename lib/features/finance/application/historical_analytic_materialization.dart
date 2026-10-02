import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'historical_analytics.dart';

class HistoricalAnalyticHumanDecision {
  const HistoricalAnalyticHumanDecision({
    required this.sourceFingerprint,
    required this.sheetName,
    required this.sourceRowNumber,
    required this.sourceContentHash,
    required this.householdId,
    required this.initialClassification,
    required this.finalClassification,
  });

  final String sourceFingerprint;
  final String sheetName;
  final int sourceRowNumber;
  final String sourceContentHash;
  final String householdId;
  final HistoricalAnalyticClassification initialClassification;
  final HistoricalAnalyticClassification finalClassification;
}

class HistoricalAnalyticDecisionBackup {
  const HistoricalAnalyticDecisionBackup({
    required this.sha256,
    required this.decisions,
  });

  final String sha256;
  final List<HistoricalAnalyticHumanDecision> decisions;

  static HistoricalAnalyticDecisionBackup decodeStrict(
    Uint8List bytes, {
    required String expectedSha256,
    required String expectedSourceFingerprint,
    required String expectedHouseholdId,
    int expectedDecisionCount = 45,
  }) {
    final actualSha = crypto.sha256.convert(bytes).toString();
    if (actualSha != expectedSha256) {
      throw const FormatException('SHA-256 du fichier de décisions invalide.');
    }
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map<String, dynamic> ||
        root['format_version'] != 1 ||
        root['export_type'] != 'historical_analytic_human_decisions' ||
        root['decision_count'] != expectedDecisionCount ||
        root['decisions'] is! List) {
      throw const FormatException('Sauvegarde de décisions invalide.');
    }
    final decisions = <HistoricalAnalyticHumanDecision>[];
    final rows = <int>{};
    for (final raw in root['decisions'] as List) {
      if (raw is! Map) throw const FormatException('Décision invalide.');
      final item = Map<String, dynamic>.from(raw);
      final row = item['source_row_number'];
      if (row is! int || !rows.add(row)) {
        throw const FormatException('Numéro de ligne source dupliqué.');
      }
      if (item['source_sha256'] != expectedSourceFingerprint ||
          item['sheet_name'] != 'Journal' ||
          item['household_id'] != expectedHouseholdId ||
          item['decision_origin'] != 'human' ||
          item['source_content_hash'] is! String ||
          !RegExp(
            r'^[0-9a-f]{64}$',
          ).hasMatch(item['source_content_hash'] as String)) {
        throw const FormatException('Identité source de décision invalide.');
      }
      decisions.add(
        HistoricalAnalyticHumanDecision(
          sourceFingerprint: item['source_sha256'] as String,
          sheetName: item['sheet_name'] as String,
          sourceRowNumber: row,
          sourceContentHash: item['source_content_hash'] as String,
          householdId: item['household_id'] as String,
          initialClassification: _classification(
            item['initial_classification'] as String?,
          ),
          finalClassification: _classification(
            item['final_classification'] as String?,
          ),
        ),
      );
    }
    if (decisions.length != expectedDecisionCount) {
      throw const FormatException('Nombre de décisions invalide.');
    }
    const expected = {
      HistoricalAnalyticClassification.validatedIncome: 26,
      HistoricalAnalyticClassification.internalTransfer: 10,
      HistoricalAnalyticClassification.technicalAdjustment: 7,
      HistoricalAnalyticClassification.budgetFunding: 2,
    };
    for (final entry in expected.entries) {
      if (decisions.where((d) => d.finalClassification == entry.key).length !=
          entry.value) {
        throw const FormatException('Ventilation des décisions invalide.');
      }
    }
    return HistoricalAnalyticDecisionBackup(
      sha256: actualSha,
      decisions: List.unmodifiable(decisions),
    );
  }
}

class HistoricalAnalyticMaterializationPlan {
  const HistoricalAnalyticMaterializationPlan({
    required this.householdId,
    required this.sourceFingerprint,
    required this.periodStart,
    required this.periodEnd,
    required this.lines,
    required this.decisions,
    required this.decisionBackupSha256,
  });

  final String householdId;
  final String sourceFingerprint;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<HistoricalAnalyticLine> lines;
  final List<HistoricalAnalyticHumanDecision> decisions;
  final String decisionBackupSha256;

  HistoricalAnalyticClassification finalClassification(
    HistoricalAnalyticLine line,
  ) =>
      decisions
          .where((decision) => decision.sourceRowNumber == line.sourceRowNumber)
          .map((decision) => decision.finalClassification)
          .firstOrNull ??
      line.classification;

  int count(HistoricalAnalyticClassification value) =>
      lines.where((line) => finalClassification(line) == value).length;

  String get idempotencyKey => crypto.sha256
      .convert(
        utf8.encode(
          'c4b:$householdId:$sourceFingerprint:Journal:$decisionBackupSha256',
        ),
      )
      .toString();

  List<Map<String, Object?>> get linePayload => lines
      .map(
        (line) => {
          ...line.toCommitJson(),
          'initial_classification': line.classification.dbValue,
          if (line.repetition != null)
            'repetition_kind': switch (line.repetition!) {
              HistoricalAnalyticRepetition.strictSource => 'strict_source',
              HistoricalAnalyticRepetition.businessSimilarity =>
                'business_similarity',
            },
        },
      )
      .toList(growable: false);

  List<Map<String, Object?>> get decisionPayload => decisions
      .map(
        (decision) => {
          'source_sha256': decision.sourceFingerprint,
          'sheet_name': decision.sheetName,
          'source_row_number': decision.sourceRowNumber,
          'source_content_hash': decision.sourceContentHash,
          'initial_classification': decision.initialClassification.dbValue,
          'final_classification': decision.finalClassification.dbValue,
          'decision_origin': 'human',
        },
      )
      .toList(growable: false);

  static HistoricalAnalyticMaterializationPlan restore({
    required HistoricalAnalyticsPreview preview,
    required HistoricalAnalyticDecisionBackup backup,
    required String sourceFingerprint,
    required String householdId,
  }) {
    final byRow = {
      for (final line in preview.lines) line.sourceRowNumber: line,
    };
    for (final decision in backup.decisions) {
      final line = byRow[decision.sourceRowNumber];
      if (line == null ||
          decision.sourceFingerprint != sourceFingerprint ||
          decision.householdId != householdId ||
          decision.sourceContentHash != line.sourceContentHash ||
          decision.initialClassification != line.classification) {
        throw FormatException(
          'Décision incompatible avec la ligne ${decision.sourceRowNumber}.',
        );
      }
    }
    final plan = HistoricalAnalyticMaterializationPlan(
      householdId: householdId,
      sourceFingerprint: sourceFingerprint,
      periodStart: preview.periodStart,
      periodEnd: preview.periodEnd,
      lines: List.unmodifiable(preview.lines),
      decisions: List.unmodifiable(backup.decisions),
      decisionBackupSha256: backup.sha256,
    );
    if (plan.lines.length != 1581 ||
        preview.periodStart != DateTime(2026, 5, 1) ||
        preview.periodEnd != DateTime(2026, 9, 29) ||
        (preview.amount(HistoricalAnalyticClassification.expense) - 211720.99)
                .abs() >
            .005 ||
        plan.count(HistoricalAnalyticClassification.ambiguousPositive) != 0 ||
        plan.count(HistoricalAnalyticClassification.expense) != 1366 ||
        plan.count(HistoricalAnalyticClassification.validatedIncome) != 26 ||
        plan.count(HistoricalAnalyticClassification.internalTransfer) != 52 ||
        plan.count(HistoricalAnalyticClassification.technicalAdjustment) !=
            19 ||
        plan.count(HistoricalAnalyticClassification.budgetFunding) != 118 ||
        plan.count(HistoricalAnalyticClassification.ignored) != 0) {
      throw const FormatException('Ventilation finale C4B invalide.');
    }
    return plan;
  }
}

HistoricalAnalyticClassification _classification(String? value) {
  for (final classification in HistoricalAnalyticClassification.values) {
    if (classification.dbValue == value) return classification;
  }
  throw const FormatException('Classification analytique invalide.');
}
