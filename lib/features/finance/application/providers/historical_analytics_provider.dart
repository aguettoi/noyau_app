import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../historical_analytics.dart';
import 'supabase_client_provider.dart';

abstract interface class HistoricalAnalyticsGateway {
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
