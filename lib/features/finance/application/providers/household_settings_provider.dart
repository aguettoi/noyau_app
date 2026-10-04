import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

class HouseholdSettings {
  const HouseholdSettings({
    required this.id,
    required this.name,
    required this.budgetValidationMode,
  });
  final String id;
  final String name;
  final String budgetValidationMode;
  bool get jointBudgetValidation => budgetValidationMode == 'joint_required';
}

class HouseholdInvitationAdmin {
  const HouseholdInvitationAdmin({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    required this.expiresAt,
  });
  final String id;
  final String email;
  final String role;
  final String status;
  final DateTime expiresAt;
}

abstract interface class HouseholdSettingsGateway {
  Future<HouseholdSettings> load(String householdId);
  Future<void> update({
    required String householdId,
    required String name,
    required String budgetValidationMode,
  });
  Future<void> updateProfile(String displayName);
  Future<List<HouseholdInvitationAdmin>> listInvitations(String householdId);
  Future<void> revokeInvitation(String invitationId);
  Future<void> changeRole({
    required String householdId,
    required String userId,
    required String role,
  });
  Future<void> leave(String householdId);
  Future<void> removeMember({
    required String householdId,
    required String userId,
  });
}

class SupabaseHouseholdSettingsGateway implements HouseholdSettingsGateway {
  SupabaseHouseholdSettingsGateway(this.client);
  final SupabaseClient client;

  @override
  Future<HouseholdSettings> load(String householdId) async {
    final row = await client
        .from('households')
        .select('id, name, budget_validation_mode')
        .eq('id', householdId)
        .single();
    return HouseholdSettings(
      id: row['id'] as String,
      name: row['name'] as String,
      budgetValidationMode:
          row['budget_validation_mode'] as String? ?? 'authorized_member',
    );
  }

  @override
  Future<void> update({
    required String householdId,
    required String name,
    required String budgetValidationMode,
  }) async {
    await client.rpc(
      'update_household_settings',
      params: {
        'p_household_id': householdId,
        'p_name': name,
        'p_budget_validation_mode': budgetValidationMode,
      },
    );
  }

  @override
  Future<void> updateProfile(String displayName) async {
    await client.rpc(
      'update_my_profile',
      params: {'p_display_name': displayName},
    );
  }

  @override
  Future<List<HouseholdInvitationAdmin>> listInvitations(
    String householdId,
  ) async {
    final rows =
        await client.rpc(
              'list_household_invitations',
              params: {'p_household_id': householdId},
            )
            as List<dynamic>;
    return rows
        .map((row) {
          final item = Map<String, dynamic>.from(row as Map);
          return HouseholdInvitationAdmin(
            id: item['invitation_id'] as String,
            email: item['invited_email'] as String,
            role: item['proposed_role'] as String,
            status: item['status'] as String,
            expiresAt: DateTime.parse(item['expires_at'] as String),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> revokeInvitation(String invitationId) async => client.rpc(
    'revoke_household_invitation',
    params: {'p_invitation_id': invitationId},
  );

  @override
  Future<void> changeRole({
    required String householdId,
    required String userId,
    required String role,
  }) async => client.rpc(
    'change_household_member_role',
    params: {
      'p_household_id': householdId,
      'p_user_id': userId,
      'p_role': role,
    },
  );

  @override
  Future<void> leave(String householdId) async =>
      client.rpc('leave_household', params: {'p_household_id': householdId});

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) async => client.rpc(
    'remove_household_member',
    params: {'p_household_id': householdId, 'p_user_id': userId},
  );
}

final householdSettingsGatewayProvider = Provider<HouseholdSettingsGateway>(
  (ref) => SupabaseHouseholdSettingsGateway(ref.watch(supabaseClientProvider)),
);

final householdSettingsProvider = FutureProvider<HouseholdSettings>((
  ref,
) async {
  final state = await ref.watch(activeHouseholdProvider.future);
  final id = state.householdId;
  if (id == null) throw StateError('Aucun foyer actif sans ambiguïté.');
  return ref.watch(householdSettingsGatewayProvider).load(id);
});

final currentProfileProvider = FutureProvider<Map<String, String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) throw StateError('Session absente.');
  final row = await client
      .from('profiles')
      .select('display_name, email')
      .eq('id', user.id)
      .maybeSingle();
  return {
    'display_name': (row?['display_name'] as String?)?.trim().isNotEmpty == true
        ? row!['display_name'] as String
        : (user.userMetadata?['display_name'] as String?) ?? '',
    'email': user.email ?? (row?['email'] as String?) ?? '',
  };
});
