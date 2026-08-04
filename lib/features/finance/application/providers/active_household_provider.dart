import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';

enum ActiveHouseholdStatus {
  noAuthenticatedUser,
  noHousehold,
  singleHousehold,
  multipleHouseholds,
  error,
}

class ActiveHouseholdState {
  const ActiveHouseholdState({
    required this.status,
    this.householdId,
    this.householdIds = const [],
    this.error,
  });

  final ActiveHouseholdStatus status;
  final String? householdId;
  final List<String> householdIds;
  final Object? error;

  bool get hasActiveHousehold =>
      status == ActiveHouseholdStatus.singleHousehold && householdId != null;
}

abstract interface class HouseholdMembershipGateway {
  Future<List<String>> householdIdsForUser(String userId);
}

class SupabaseHouseholdMembershipGateway implements HouseholdMembershipGateway {
  SupabaseHouseholdMembershipGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<String>> householdIdsForUser(String userId) async {
    try {
      final response = await _client
          .from('household_members')
          .select('household_id')
          .eq('user_id', userId);
      return (response as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map((item) => item['household_id'])
          .whereType<String>()
          .toList(growable: false);
    } on Exception catch (error) {
      throw Exception('Impossible de charger les foyers : $error');
    }
  }
}

final householdMembershipGatewayProvider = Provider<HouseholdMembershipGateway>(
  (ref) =>
      SupabaseHouseholdMembershipGateway(ref.watch(supabaseClientProvider)),
);

final activeHouseholdProvider = FutureProvider<ActiveHouseholdState>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return const ActiveHouseholdState(
      status: ActiveHouseholdStatus.noAuthenticatedUser,
    );
  }

  try {
    final householdIds = await ref
        .watch(householdMembershipGatewayProvider)
        .householdIdsForUser(userId);
    if (householdIds.isEmpty) {
      return const ActiveHouseholdState(
        status: ActiveHouseholdStatus.noHousehold,
      );
    }
    if (householdIds.length == 1) {
      return ActiveHouseholdState(
        status: ActiveHouseholdStatus.singleHousehold,
        householdId: householdIds.single,
        householdIds: List.unmodifiable(householdIds),
      );
    }
    return ActiveHouseholdState(
      status: ActiveHouseholdStatus.multipleHouseholds,
      householdIds: List.unmodifiable(householdIds),
    );
  } catch (error) {
    return ActiveHouseholdState(
      status: ActiveHouseholdStatus.error,
      error: error,
    );
  }
});
