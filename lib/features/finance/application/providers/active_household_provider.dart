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

enum HouseholdClassification { operational, technical }

class HouseholdMembership {
  const HouseholdMembership({
    required this.householdId,
    required this.classification,
  });

  final String householdId;
  final HouseholdClassification classification;
}

abstract interface class HouseholdMembershipGateway {
  Future<List<HouseholdMembership>> householdsForUser(String userId);
}

class SupabaseHouseholdMembershipGateway implements HouseholdMembershipGateway {
  SupabaseHouseholdMembershipGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<HouseholdMembership>> householdsForUser(String userId) async {
    try {
      final response = await _client
          .from('household_members')
          .select('household_id, households!inner(classification)')
          .eq('user_id', userId);
      return (response as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map((item) {
            final household = item['households'];
            final householdMap = household is Map
                ? Map<String, dynamic>.from(household)
                : const <String, dynamic>{};
            final householdId = item['household_id'];
            final classification = householdMap['classification'];
            if (householdId is! String ||
                (classification != 'operational' &&
                    classification != 'technical')) {
              throw StateError('Un foyer accessible est incomplet.');
            }
            return HouseholdMembership(
              householdId: householdId,
              classification: classification == 'technical'
                  ? HouseholdClassification.technical
                  : HouseholdClassification.operational,
            );
          })
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
    final memberships = await ref
        .watch(householdMembershipGatewayProvider)
        .householdsForUser(userId);
    final householdIds = memberships
        .where(
          (membership) =>
              membership.classification == HouseholdClassification.operational,
        )
        .map((membership) => membership.householdId)
        .toList(growable: false);
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
