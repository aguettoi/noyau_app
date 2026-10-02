import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/historical_analytic_materialization.dart';
import 'package:noyau_app/features/finance/application/historical_analytics.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';
import 'package:noyau_app/features/finance/application/cutover_opening_import.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/historical_analytics_provider.dart';
import 'package:noyau_app/features/finance/presentation/historical_analytics_preview_card.dart';

void main() {
  const source =
      'f3cbc99e335586d5628791017e5fd8119430a03d32674ba1d11f284157c8f8bc';
  const household = '51cfd7c6-8edc-4c42-94db-1be78289fe81';
  final classifications = [
    ...List.filled(26, 'validated_income'),
    ...List.filled(10, 'internal_transfer'),
    ...List.filled(7, 'technical_adjustment'),
    ...List.filled(2, 'budget_funding'),
  ];
  Map<String, dynamic> backupJson() => {
    'format_version': 1,
    'export_type': 'historical_analytic_human_decisions',
    'decision_count': 45,
    'decisions': List.generate(
      45,
      (i) => {
        'source_sha256': source,
        'sheet_name': 'Journal',
        'source_row_number': i + 1,
        'source_content_hash': 'a' * 64,
        'household_id': household,
        'decision_origin': 'human',
        'initial_classification': 'ambiguous_positive',
        'final_classification': classifications[i],
      },
    ),
  };
  HistoricalAnalyticDecisionBackup decode(Map<String, dynamic> json) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    return HistoricalAnalyticDecisionBackup.decodeStrict(
      bytes,
      expectedSha256: sha256.convert(bytes).toString(),
      expectedSourceFingerprint: source,
      expectedHouseholdId: household,
    );
  }

  test('strict restoration keeps all 45 human identities', () {
    final backup = decode(backupJson());
    expect(backup.decisions, hasLength(45));
    expect(
      backup.decisions.every(
        (d) =>
            d.initialClassification ==
            HistoricalAnalyticClassification.ambiguousPositive,
      ),
      isTrue,
    );
  });
  test('rejects wrong checksum', () {
    expect(
      () => HistoricalAnalyticDecisionBackup.decodeStrict(
        Uint8List.fromList([1]),
        expectedSha256: 'a' * 64,
        expectedSourceFingerprint: source,
        expectedHouseholdId: household,
      ),
      throwsFormatException,
    );
  });
  for (final field in [
    'source_sha256',
    'household_id',
    'sheet_name',
    'decision_origin',
    'final_classification',
  ]) {
    test('rejects invalid $field', () {
      final json = backupJson();
      (json['decisions'] as List).first[field] = 'invalid';
      expect(() => decode(json), throwsFormatException);
    });
  }
  test('rejects duplicated source rows and incorrect distribution', () {
    final json = backupJson();
    (json['decisions'] as List)[1]['source_row_number'] = 1;
    expect(() => decode(json), throwsFormatException);
    final other = backupJson();
    (other['decisions'] as List)[0]['final_classification'] = 'ignored';
    expect(() => decode(other), throwsFormatException);
  });
  final sourcePath = Platform.environment['C4B_TEST_SOURCE'];
  final backupPath = Platform.environment['C4B_TEST_DECISIONS'];
  testWidgets(
    'restored preview writes only after explicit confirmation through one gateway call',
    (tester) async {
      final analysis = await tester.runAsync(
        () async => WorkbookImportEngine.analyzeInBackground(
          fileName: 'SIMULATION_CUTOVER_FINAL_20260929.xlsx.xlsx',
          bytes: await File(sourcePath!).readAsBytes(),
          expectedEnvelopeNames: const [],
        ),
      );
      final bytes = await tester.runAsync(
        () => File(backupPath!).readAsBytes(),
      );
      final gateway = _RecordingGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cutoverEligibleHouseholdsProvider.overrideWith(
              (ref) async => [
                const CutoverEligibleHousehold(
                  id: household,
                  name: 'Foyer certifié',
                  classification: HouseholdClassification.operational,
                ),
              ],
            ),
            historicalDecisionFilePickerProvider.overrideWithValue(
              () async => bytes,
            ),
            historicalAnalyticsGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [HistoricalAnalyticsPreviewCard(analysis: analysis!)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('historical-materialization-household')),
      );
      await tester.tap(
        find.byKey(const Key('historical-materialization-household')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foyer certifié — OPÉRATIONNEL').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('load-historical-decisions')),
      );
      await tester.tap(find.byKey(const Key('load-historical-decisions')));
      await tester.pumpAndSettle();
      expect(gateway.calls, 0);
      expect(find.text('0 positifs à valider'), findsOneWidget);
      expect(
        find.textContaining('1581 lignes · 45 décisions humaines · 0 ambigu'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('materialize-historical-analytics')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('materialize-historical-analytics')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(gateway.calls, 0);
      await tester.tap(
        find.byKey(const Key('materialize-historical-analytics')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(gateway.calls, 1);
      expect(gateway.plan!.linePayload, hasLength(1581));
      expect(gateway.plan!.decisionPayload, hasLength(45));
      expect(tester.takeException(), isNull);
    },
    skip: sourcePath == null || backupPath == null,
  );
  test(
    'certified source rebuild restores 1581 lines and 45 decisions after restart',
    () async {
      final bytes = await File(sourcePath!).readAsBytes();
      final analysis = await WorkbookImportEngine.analyzeInBackground(
        fileName: 'SIMULATION_CUTOVER_FINAL_20260929.xlsx.xlsx',
        bytes: bytes,
        expectedEnvelopeNames: const [],
      );
      expect(analysis.sourceFingerprint, source);
      final backup = HistoricalAnalyticDecisionBackup.decodeStrict(
        await File(backupPath!).readAsBytes(),
        expectedSha256:
            'a98806810967481921508df92138ab58e6e1b02cde5e40f390c08ec5b0519663',
        expectedSourceFingerprint: source,
        expectedHouseholdId: household,
      );
      final preview = const HistoricalAnalyticsPreviewBuilder().build(analysis);
      final plan = HistoricalAnalyticMaterializationPlan.restore(
        preview: preview,
        backup: backup,
        sourceFingerprint: source,
        householdId: household,
      );
      expect(plan.lines, hasLength(1581));
      expect(plan.decisions, hasLength(45));
      expect(plan.count(HistoricalAnalyticClassification.ambiguousPositive), 0);
      expect(plan.count(HistoricalAnalyticClassification.expense), 1366);
      expect(plan.count(HistoricalAnalyticClassification.validatedIncome), 26);
      expect(plan.count(HistoricalAnalyticClassification.internalTransfer), 52);
      expect(
        plan.count(HistoricalAnalyticClassification.technicalAdjustment),
        19,
      );
      expect(plan.count(HistoricalAnalyticClassification.budgetFunding), 118);
      expect(
        preview.amount(HistoricalAnalyticClassification.expense),
        closeTo(211720.99, .001),
      );
      expect(preview.duplicateCandidates, 311);
      expect(
        plan.linePayload.where(
          (l) => l['initial_classification'] == 'ambiguous_positive',
        ),
        hasLength(45),
      );
      expect(
        plan.idempotencyKey,
        HistoricalAnalyticMaterializationPlan.restore(
          preview: preview,
          backup: backup,
          sourceFingerprint: source,
          householdId: household,
        ).idempotencyKey,
      );
    },
    skip: sourcePath == null || backupPath == null
        ? 'Set C4B_TEST_SOURCE and C4B_TEST_DECISIONS for certified local source verification'
        : false,
  );
}

class _RecordingGateway implements HistoricalAnalyticsGateway {
  int calls = 0;
  HistoricalAnalyticMaterializationPlan? plan;
  @override
  Future<Map<String, dynamic>> materialize(
    HistoricalAnalyticMaterializationPlan value,
  ) async {
    calls++;
    plan = value;
    return {
      'inserted_lines': 1581,
      'inserted_decisions': 45,
      'replayed': false,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLines(String householdId) async => [];
  @override
  Future<Map<String, int>> commitPreview({
    required String householdId,
    required String importSheetRunId,
    required String sourceFingerprint,
    required List<HistoricalAnalyticLine> lines,
  }) => throw StateError('Legacy boundary must not be used');
}
