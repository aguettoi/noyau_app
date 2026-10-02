import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../historical_analytics.dart';
import '../historical_analytic_materialization.dart';
import 'supabase_client_provider.dart';

abstract interface class HistoricalAnalyticsGateway {
  Future<Map<String, dynamic>> materialize(
    HistoricalAnalyticMaterializationPlan plan,
  );
  Future<Map<String, int>> commitPreview({
    required String householdId,
    required String importSheetRunId,
    required String sourceFingerprint,
    required List<HistoricalAnalyticLine> lines,
  });

  Future<List<Map<String, dynamic>>> fetchLines(String householdId);
}

class SupabaseHistoricalAnalyticsGateway implements HistoricalAnalyticsGateway {
  SupabaseHistoricalAnalyticsGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> materialize(
    HistoricalAnalyticMaterializationPlan plan,
  ) async => Map<String, dynamic>.from(
    await _client.rpc<Map<String, dynamic>>(
      'materialize_historical_analytic_import',
      params: {
        'p_household_id': plan.householdId,
        'p_source_file_name': 'SIMULATION_CUTOVER_FINAL_20260929.xlsx.xlsx',
        'p_source_fingerprint': plan.sourceFingerprint,
        'p_source_sheet_name': 'Journal',
        'p_period_start': plan.periodStart.toIso8601String().substring(0, 10),
        'p_period_end': plan.periodEnd.toIso8601String().substring(0, 10),
        'p_expected_line_count': plan.lines.length,
        'p_idempotency_key': plan.idempotencyKey,
        'p_lines': plan.linePayload,
        'p_human_decisions': plan.decisionPayload,
      },
    ),
  );

  @override
  Future<Map<String, int>> commitPreview({
    required String householdId,
    required String importSheetRunId,
    required String sourceFingerprint,
    required List<HistoricalAnalyticLine> lines,
  }) async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'commit_historical_analytic_import',
      params: {
        'p_household_id': householdId,
        'p_import_sheet_run_id': importSheetRunId,
        'p_source_fingerprint': sourceFingerprint,
        'p_source_sheet_name': 'Journal',
        'p_lines': lines.map((line) => line.toCommitJson()).toList(),
      },
    );
    return {
      'inserted': (result['inserted'] as num?)?.toInt() ?? 0,
      'replayed': (result['replayed'] as num?)?.toInt() ?? 0,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLines(String householdId) async =>
      (await _client
              .from('historical_analytic_line_status')
              .select()
              .eq('household_id', householdId)
              .order('occurred_on', ascending: true)
              .order('source_row_number', ascending: true))
          .cast<Map<String, dynamic>>();
}

final historicalAnalyticsGatewayProvider = Provider<HistoricalAnalyticsGateway>(
  (ref) =>
      SupabaseHistoricalAnalyticsGateway(ref.watch(supabaseClientProvider)),
);

final historicalDecisionFilePickerProvider =
    Provider<Future<Uint8List?> Function()>(
      (ref) => () async {
        final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['json'],
          withData: true,
        );
        if (selection == null) return null;
        final bytes = selection.files.single.bytes;
        if (bytes == null) throw const FormatException('Fichier illisible.');
        return bytes;
      },
    );
