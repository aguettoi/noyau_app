import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_household_provider.dart';
import 'remote_accounts_provider.dart';
import 'supabase_client_provider.dart';

class AccountPrivacyRequest {
  const AccountPrivacyRequest({
    required this.id,
    required this.accountId,
    required this.requestedVisibility,
    required this.status,
    required this.requestedBy,
    required this.decisions,
  });

  final String id;
  final String accountId;
  final String requestedVisibility;
  final String status;
  final String requestedBy;
  final Map<String, String> decisions;

  bool hasDecision(String userId) => decisions.containsKey(userId);
  int get approvalCount =>
      decisions.values.where((decision) => decision == 'approve').length;
}

final accountPrivacyRequestsProvider =
    FutureProvider<List<AccountPrivacyRequest>>((ref) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (householdId == null) return const [];
      final client = ref.watch(supabaseClientProvider);
      final rawRequests = await client
          .from('account_privacy_requests')
          .select(
            'id,account_id,requested_visibility,status,requested_by,created_at',
          )
          .eq('household_id', householdId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      final requests = (rawRequests as List<dynamic>)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList(growable: false);
      if (requests.isEmpty) return const [];
      final requestIds = requests.map((row) => row['id'] as String).toList();
      final rawConsents = await client
          .from('account_privacy_consents')
          .select('request_id,user_id,decision')
          .inFilter('request_id', requestIds);
      final decisions = <String, Map<String, String>>{};
      for (final item in rawConsents as List<dynamic>) {
        final row = Map<String, Object?>.from(item as Map);
        final requestId = row['request_id'] as String;
        decisions.putIfAbsent(
          requestId,
          () => <String, String>{},
        )[row['user_id'] as String] = row['decision'] as String;
      }
      return List.unmodifiable(
        requests.map((row) {
          final id = row['id'] as String;
          return AccountPrivacyRequest(
            id: id,
            accountId: row['account_id'] as String,
            requestedVisibility: row['requested_visibility'] as String,
            status: row['status'] as String,
            requestedBy: row['requested_by'] as String,
            decisions: Map.unmodifiable(decisions[id] ?? const {}),
          );
        }),
      );
    });

final accountPrivacyActionsProvider = Provider<AccountPrivacyActions>(
  AccountPrivacyActions.new,
);

class AccountPrivacyActions {
  AccountPrivacyActions(this.ref);

  final Ref ref;

  Future<void> request(String accountId, String visibility) async {
    await ref
        .read(supabaseClientProvider)
        .rpc(
          'request_account_privacy_change',
          params: {'p_account_id': accountId, 'p_visibility': visibility},
        );
    _refresh();
  }

  Future<void> decide(String requestId, String decision) async {
    await ref
        .read(supabaseClientProvider)
        .rpc(
          'decide_account_privacy_change',
          params: {'p_request_id': requestId, 'p_decision': decision},
        );
    _refresh();
  }

  Future<void> cancel(String requestId) async {
    await ref
        .read(supabaseClientProvider)
        .rpc(
          'cancel_account_privacy_change',
          params: {'p_request_id': requestId},
        );
    _refresh();
  }

  void _refresh() {
    ref.invalidate(accountPrivacyRequestsProvider);
    ref.invalidate(remoteAccountsProvider);
  }
}
