import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/household_member.dart';
import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

abstract interface class HouseholdMembersGateway {
  Future<List<HouseholdMember>> fetchMembers(String householdId);
}

class SupabaseHouseholdMembersGateway implements HouseholdMembersGateway {
  SupabaseHouseholdMembersGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<HouseholdMember>> fetchMembers(String householdId) async {
    try {
      final response = await _client
          .from('household_members')
          .select('user_id')
          .eq('household_id', householdId)
          .order('created_at');
      final rows = response as List<dynamic>;
      final memberIds = rows
          .map((item) => Map<String, dynamic>.from(item as Map)['user_id'])
          .whereType<String>()
          .map((userId) => userId.trim())
          .where((userId) => userId.isNotEmpty)
          .toList(growable: false);
      if (memberIds.length != rows.length) {
        throw StateError('Un membre du foyer est incomplet.');
      }

      final namesByUserId = <String, String>{};
      final emailsByUserId = <String, String>{};
      if (memberIds.isNotEmpty) {
        try {
          final profiles = await _loadProfiles(memberIds);
          for (final item in profiles as List<dynamic>) {
            final profile = Map<String, dynamic>.from(item as Map);
            final id = profile['id'] as String?;
            final displayName = profile['display_name'] as String?;
            final email = profile['email'] as String?;
            if (id != null &&
                displayName != null &&
                displayName.trim().isNotEmpty) {
              namesByUserId[id] = displayName.trim();
            }
            if (id != null && email != null && email.trim().isNotEmpty) {
              emailsByUserId[id] = email.trim();
            }
          }
        } on Exception {
          // Les identifiants restent utilisables ; le libellé générique évite
          // d'exposer un UUID si la lecture du profil est momentanément refusée.
        }
      }

      final members = householdMembersForDisplay(
        userIds: memberIds,
        displayNamesByUserId: namesByUserId,
        emailsByUserId: emailsByUserId,
      );
      return members;
    } on Exception catch (error) {
      throw Exception('Impossible de charger les membres du foyer : $error');
    }
  }

  Future<dynamic> _loadProfiles(List<String> memberIds) async {
    try {
      return await _client
          .from('profiles')
          .select('id, display_name, email')
          .inFilter('id', memberIds);
    } on Exception {
      return _client
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', memberIds);
    }
  }
}

List<HouseholdMember> householdMembersForDisplay({
  required List<String> userIds,
  required Map<String, String> displayNamesByUserId,
  Map<String, String> emailsByUserId = const {},
}) => List.unmodifiable(
  List<HouseholdMember>.generate(userIds.length, (index) {
    final userId = userIds[index];
    final displayName = displayNamesByUserId[userId]?.trim();
    final email = emailsByUserId[userId]?.trim();
    return HouseholdMember(
      id: userId,
      displayName: displayName != null && displayName.isNotEmpty
          ? displayName
          : email != null && email.isNotEmpty
          ? email
          : 'Membre du foyer',
    );
  }),
);

final householdMembersGatewayProvider = Provider<HouseholdMembersGateway>(
  (ref) => SupabaseHouseholdMembersGateway(ref.watch(supabaseClientProvider)),
);

final remoteHouseholdMembersProvider = FutureProvider<List<HouseholdMember>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  return ref.watch(householdMembersGatewayProvider).fetchMembers(householdId);
});
