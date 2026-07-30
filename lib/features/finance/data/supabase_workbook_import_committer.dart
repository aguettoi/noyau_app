import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/workbook_import.dart';

/// Persists the immutable source archive only after an explicit confirmation.
/// Business importers remain responsible for their own validated mappings.
class SupabaseWorkbookImportCommitter implements WorkbookImportCommitter {
  SupabaseWorkbookImportCommitter(this._client, {required this.householdId});

  final SupabaseClient _client;
  final String householdId;

  @override
  Future<ImportCommitResult> commit(ConfirmedWorkbookImport import) async {
    final analysis = import.analysis;
    final sessionId = await _client.rpc(
      'archive_workbook_import',
      params: {
        'p_household_id': householdId,
        'p_source_file_name': analysis.fileName,
        'p_source_fingerprint': analysis.sourceFingerprint,
        'p_sheets': analysis.toArchivePayload(
          importerIds: import.selectedImporterIds,
        ),
      },
    );
    return ImportCommitResult(importSessionId: sessionId as String);
  }

  @override
  Future<void> undo(String importSessionId, {required String reason}) => _client
      .rpc(
        'undo_workbook_import',
        params: {'p_import_session_id': importSessionId, 'p_reason': reason},
      )
      .then<void>((_) {});
}
