import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';

import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

class MemberCompensation {
  const MemberCompensation({
    required this.id,
    required this.debtor,
    required this.creditor,
    required this.initial,
    required this.remaining,
    required this.status,
    required this.reason,
  });
  final String id, debtor, creditor, status, reason;
  final double initial, remaining;
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
        'id,debtor_user_id,creditor_user_id,initial_amount,remaining_amount,status,reason',
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
        debtor: names[raw['debtor_user_id']] ?? 'Membre',
        creditor: names[raw['creditor_user_id']] ?? 'Membre',
        initial: double.parse(raw['initial_amount'].toString()),
        remaining: double.parse(raw['remaining_amount'].toString()),
        status: raw['status'].toString(),
        reason: raw['reason'].toString(),
      ),
  ];
});

final compensationActionProvider = Provider(
  (ref) =>
      ({
        required String compensationId,
        required String kind,
        required double amount,
        String? transferEventId,
        required String reason,
        required List<Map<String, Object?>> allocations,
      }) async {
        await ref
            .read(supabaseClientProvider)
            .rpc(
              'record_member_compensation_action',
              params: {
                'p_compensation_id': compensationId,
                'p_action_kind': kind,
                'p_amount': amount,
                'p_transfer_event_id': transferEventId,
                'p_reason': reason,
                'p_allocations': allocations,
                'p_idempotency_key': _uuid(),
              },
            );
        ref.invalidate(memberCompensationsProvider);
      },
);

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
