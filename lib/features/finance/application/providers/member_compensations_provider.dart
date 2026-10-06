import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

class MemberCompensation {
  const MemberCompensation({
    required this.id,
    required this.sourceFinancialEventId,
    required this.debtorUserId,
    required this.creditorUserId,
    required this.debtor,
    required this.creditor,
    required this.initial,
    required this.remaining,
    required this.pendingReceipt,
    required this.status,
    required this.reason,
    this.envelopeId,
    this.actualAccountId,
    this.recommendedAccountId,
  });
  final String id, sourceFinancialEventId, debtorUserId, creditorUserId;
  final String debtor, creditor, status, reason;
  final String? envelopeId, actualAccountId, recommendedAccountId;
  final double initial, remaining, pendingReceipt;
}

final memberCompensationsProvider = FutureProvider<List<MemberCompensation>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final id = household.householdId;
  if (id == null) throw StateError('Aucun foyer actif sans ambiguïté.');
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('member_compensation_balances')
      .select(
        'id,source_financial_event_id,debtor_user_id,creditor_user_id,initial_amount,remaining_amount,pending_receipt,status,reason,envelope_id,actual_account_id,recommended_account_id',
      )
      .eq('household_id', id)
      .order('created_at', ascending: false);
  final profiles = await client.from('profiles').select('id,display_name');
  final names = {
    for (final raw in profiles as List<dynamic>)
      (raw as Map)['id'].toString(): (raw['display_name'] ?? 'Membre')
          .toString(),
  };
  return [
    for (final raw in rows as List<dynamic>)
      MemberCompensation(
        id: (raw as Map)['id'].toString(),
        sourceFinancialEventId: raw['source_financial_event_id'].toString(),
        debtorUserId: raw['debtor_user_id'].toString(),
        creditorUserId: raw['creditor_user_id'].toString(),
        debtor: names[raw['debtor_user_id']] ?? 'Membre',
        creditor: names[raw['creditor_user_id']] ?? 'Membre',
        initial: double.parse(raw['initial_amount'].toString()),
        remaining: double.parse(raw['remaining_amount'].toString()),
        pendingReceipt: double.parse((raw['pending_receipt'] ?? 0).toString()),
        status: raw['status'].toString(),
        reason: raw['reason'].toString(),
        envelopeId: raw['envelope_id']?.toString(),
        actualAccountId: raw['actual_account_id']?.toString(),
        recommendedAccountId: raw['recommended_account_id']?.toString(),
      ),
  ];
});

final createMemberCompensationProvider = Provider(
  (ref) =>
      ({
        required String sourceEventId,
        required String debtorUserId,
        required String creditorUserId,
        required double amount,
        required String reason,
        String? envelopeId,
        String? actualAccountId,
        String? recommendedAccountId,
        String? actualPaymentMethodId,
        String? recommendedPaymentMethodId,
        String? idempotencyKey,
      }) async {
        final household = await ref.read(activeHouseholdProvider.future);
        if (household.householdId == null) {
          throw StateError('Aucun foyer actif.');
        }
        final result = await ref
            .read(supabaseClientProvider)
            .rpc(
              'create_member_compensation',
              params: {
                'p_household_id': household.householdId,
                'p_source_event_id': sourceEventId,
                'p_debtor_user_id': debtorUserId,
                'p_creditor_user_id': creditorUserId,
                'p_amount': amount.toStringAsFixed(2),
                'p_reason': reason,
                'p_envelope_id': envelopeId,
                'p_actual_account_id': actualAccountId,
                'p_recommended_account_id': recommendedAccountId,
                'p_actual_payment_method_id': actualPaymentMethodId,
                'p_recommended_payment_method_id': recommendedPaymentMethodId,
                'p_idempotency_key':
                    idempotencyKey ?? newCompensationIdempotencyKey(),
              },
            );
        ref.invalidate(memberCompensationsProvider);
        return result.toString();
      },
);

final compensationActionProvider = Provider(
  (ref) =>
      ({
        required String compensationId,
        required String kind,
        required double amount,
        String? transferEventId,
        required String reason,
        required List<Map<String, Object?>> allocations,
        String? idempotencyKey,
      }) async {
        await ref
            .read(supabaseClientProvider)
            .rpc(
              'record_member_compensation_action',
              params: {
                'p_compensation_id': compensationId,
                'p_action_kind': kind,
                'p_amount': amount.toStringAsFixed(2),
                'p_transfer_event_id': transferEventId,
                'p_reason': reason,
                'p_allocations': allocations,
                'p_idempotency_key':
                    idempotencyKey ?? newCompensationIdempotencyKey(),
              },
            );
        ref.invalidate(memberCompensationsProvider);
      },
);

final compensationCanonicalTransferProvider = Provider(
  (ref) =>
      ({
        required String compensationId,
        required String sourceAccountId,
        required String destinationAccountId,
        required double amount,
        required DateTime occurredAt,
        required String description,
        String? idempotencyKey,
      }) async {
        final result = await ref
            .read(supabaseClientProvider)
            .rpc(
              'create_compensation_account_transfer',
              params: {
                'p_compensation_id': compensationId,
                'p_source_account_id': sourceAccountId,
                'p_destination_account_id': destinationAccountId,
                'p_amount': amount.toStringAsFixed(2),
                'p_occurred_at': occurredAt.toUtc().toIso8601String(),
                'p_description': description,
                'p_idempotency_key':
                    idempotencyKey ?? newCompensationIdempotencyKey(),
              },
            );
        ref.invalidate(memberCompensationsProvider);
        return result.toString();
      },
);

String newCompensationIdempotencyKey() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
