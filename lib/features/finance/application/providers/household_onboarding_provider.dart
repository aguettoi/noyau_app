import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'active_household_provider.dart';
import 'remote_household_members_provider.dart';
import 'supabase_client_provider.dart';

class HouseholdInvitation {
  const HouseholdInvitation({
    required this.id,
    required this.householdId,
    required this.householdName,
    required this.invitedByName,
    required this.expiresAt,
  });

  final String id;
  final String householdId;
  final String householdName;
  final String invitedByName;
  final DateTime expiresAt;

  factory HouseholdInvitation.fromJson(Map<String, dynamic> json) =>
      HouseholdInvitation(
        id: json['invitation_id'] as String,
        householdId: json['household_id'] as String,
        householdName: json['household_name'] as String,
        invitedByName: json['invited_by_name'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

abstract interface class HouseholdOnboardingGateway {
  Future<String> createHousehold(String name);
  Future<List<HouseholdInvitation>> pendingInvitations();
  Future<String> acceptInvitation(String invitationId);
  Future<void> inviteMember({
    required String householdId,
    required String email,
  });
}

class SupabaseHouseholdOnboardingGateway implements HouseholdOnboardingGateway {
  SupabaseHouseholdOnboardingGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<String> createHousehold(String name) async {
    final result = await _client.rpc(
      'create_household',
      params: {'household_name': name.trim()},
    );
    return result as String;
  }

  @override
  Future<List<HouseholdInvitation>> pendingInvitations() async {
    final result = await _client.rpc('list_my_pending_household_invitations');
    return (result as List<dynamic>)
        .map(
          (row) => HouseholdInvitation.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<String> acceptInvitation(String invitationId) async {
    final result = await _client.rpc(
      'accept_household_invitation',
      params: {'p_invitation_id': invitationId},
    );
    return result as String;
  }

  @override
  Future<void> inviteMember({
    required String householdId,
    required String email,
  }) async {
    await _client.rpc(
      'create_household_invitation',
      params: {'p_household_id': householdId, 'p_invited_email': email.trim()},
    );
  }
}

final householdOnboardingGatewayProvider = Provider<HouseholdOnboardingGateway>(
  (ref) =>
      SupabaseHouseholdOnboardingGateway(ref.watch(supabaseClientProvider)),
);

final pendingHouseholdInvitationsProvider =
    FutureProvider<List<HouseholdInvitation>>(
      (ref) =>
          ref.watch(householdOnboardingGatewayProvider).pendingInvitations(),
    );

void refreshHouseholdContext(WidgetRef ref) {
  ref.invalidate(activeHouseholdProvider);
  ref.invalidate(remoteHouseholdMembersProvider);
  ref.invalidate(pendingHouseholdInvitationsProvider);
}
