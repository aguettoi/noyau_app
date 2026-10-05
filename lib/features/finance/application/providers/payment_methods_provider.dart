import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.label,
    required this.type,
    this.accountId,
    this.holderUserId,
    required this.active,
  });
  final String id, label, type;
  final String? accountId, holderUserId;
  final bool active;
}

abstract interface class PaymentMethodsGateway {
  Future<List<PaymentMethod>> list(String householdId);
  Future<void> create({
    required String householdId,
    String? accountId,
    String? holderUserId,
    required String type,
    required String label,
  });
  Future<void> update({
    required String id,
    String? accountId,
    String? holderUserId,
    required String type,
    required String label,
    required bool active,
  });
  Future<void> setEnvelopeRecommendation({
    required String envelopeId,
    String? accountId,
    String? paymentMethodId,
  });
}

class SupabasePaymentMethodsGateway implements PaymentMethodsGateway {
  SupabasePaymentMethodsGateway(this.client);
  final SupabaseClient client;
  @override
  Future<List<PaymentMethod>> list(String householdId) async {
    final rows = await client
        .from('payment_methods')
        .select('id,label,method_type,account_id,holder_user_id,active')
        .eq('household_id', householdId)
        .order('label', ascending: true);
    return (rows as List)
        .map((r) {
          final m = Map<String, dynamic>.from(r);
          return PaymentMethod(
            id: m['id'] as String,
            label: m['label'] as String,
            type: m['method_type'] as String,
            accountId: m['account_id'] as String?,
            holderUserId: m['holder_user_id'] as String?,
            active: m['active'] as bool,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> create({
    required String householdId,
    String? accountId,
    String? holderUserId,
    required String type,
    required String label,
  }) async => client.rpc(
    'create_payment_method',
    params: {
      'p_household_id': householdId,
      'p_account_id': accountId,
      'p_holder_user_id': holderUserId,
      'p_method_type': type,
      'p_label': label,
    },
  );
  @override
  Future<void> update({
    required String id,
    String? accountId,
    String? holderUserId,
    required String type,
    required String label,
    required bool active,
  }) async => client.rpc(
    'update_payment_method',
    params: {
      'p_id': id,
      'p_account_id': accountId,
      'p_holder_user_id': holderUserId,
      'p_method_type': type,
      'p_label': label,
      'p_active': active,
    },
  );

  @override
  Future<void> setEnvelopeRecommendation({
    required String envelopeId,
    String? accountId,
    String? paymentMethodId,
  }) async => client.rpc(
    'set_envelope_recommendation',
    params: {
      'p_envelope_id': envelopeId,
      'p_account_id': accountId,
      'p_payment_method_id': paymentMethodId,
    },
  );
}

final paymentMethodsGatewayProvider = Provider<PaymentMethodsGateway>(
  (ref) => SupabasePaymentMethodsGateway(ref.watch(supabaseClientProvider)),
);
final paymentMethodsProvider = FutureProvider<List<PaymentMethod>>((ref) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final id = household.householdId;
  if (id == null) throw StateError('Aucun foyer actif sans ambiguïté.');
  return ref.watch(paymentMethodsGatewayProvider).list(id);
});

final paymentMethodTypesProvider = Provider<List<String>>(
  (_) => const ['bank_card', 'cash', 'bank_transfer', 'other'],
);

final setEnvelopeRecommendationProvider = Provider(
  (ref) =>
      ({
        required String envelopeId,
        String? accountId,
        String? paymentMethodId,
      }) async {
        await ref
            .read(paymentMethodsGatewayProvider)
            .setEnvelopeRecommendation(
              envelopeId: envelopeId,
              accountId: accountId,
              paymentMethodId: paymentMethodId,
            );
      },
);
