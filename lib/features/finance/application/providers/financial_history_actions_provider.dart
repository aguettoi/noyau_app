import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'active_household_provider.dart';
import 'remote_transactions_provider.dart';
import 'supabase_client_provider.dart';

class FinancialHistoryActions {
  FinancialHistoryActions(this._client, this._householdId, this._ref);
  final SupabaseClient _client;
  final String _householdId;
  final Ref _ref;

  Future<String> reverse({
    required String eventId,
    required DateTime occurredAt,
    required String reasonCode,
    required String reason,
    required String idempotencyKey,
  }) async {
    final result = await _client.rpc(
      'reverse_daily_financial_event',
      params: {
        'p_household_id': _householdId,
        'p_original_event_id': eventId,
        'p_occurred_at': occurredAt.toUtc().toIso8601String(),
        'p_reason_code': reasonCode,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      },
    );
    _ref.invalidate(remoteTransactionsProvider);
    _ref.invalidate(filteredTransactionsProvider);
    return result as String;
  }

  Future<void> upload({
    required String eventId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final id = _uuid();
    final path =
        await _client.rpc(
              'register_financial_event_attachment',
              params: {
                'p_household_id': _householdId,
                'p_financial_event_id': eventId,
                'p_original_filename': filename,
                'p_mime_type': mimeType,
                'p_file_size': bytes.length,
                'p_attachment_id': id,
              },
            )
            as String;
    try {
      await _client.storage
          .from('financial-evidence')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
    } catch (_) {
      await _client.rpc(
        'soft_delete_financial_event_attachment',
        params: {'p_attachment_id': id},
      );
      rethrow;
    }
    _ref.invalidate(remoteTransactionsProvider);
    _ref.invalidate(filteredTransactionsProvider);
  }

  Future<String> signedUrl(String path) =>
      _client.storage.from('financial-evidence').createSignedUrl(path, 300);

  Future<void> delete(String attachmentId) async {
    final path =
        await _client.rpc(
              'soft_delete_financial_event_attachment',
              params: {'p_attachment_id': attachmentId},
            )
            as String;
    await _client.storage.from('financial-evidence').remove([path]);
    _ref.invalidate(remoteTransactionsProvider);
    _ref.invalidate(filteredTransactionsProvider);
  }
}

final financialHistoryActionsProvider = Provider<FinancialHistoryActions>((
  ref,
) {
  final household = ref.watch(activeHouseholdProvider).requireValue;
  final id = household.householdId;
  if (id == null) throw StateError('Aucun foyer actif sans ambiguïté.');
  return FinancialHistoryActions(ref.watch(supabaseClientProvider), id, ref);
});

String newFinancialHistoryIdempotencyKey() => _uuid();

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
