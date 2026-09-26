import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/money/money.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';

class RemoteEnvelopeBalance {
  const RemoteEnvelopeBalance({
    required this.id,
    required this.name,
    required this.inflows,
    required this.outflows,
    required this.balance,
    required this.isSystem,
    this.isArchived = false,
    this.notes,
    this.lastMovementAt,
    this.systemCode,
  });

  final String id;
  final String name;
  final Money inflows;
  final Money outflows;
  final Money balance;
  final bool isSystem;
  final bool isArchived;
  final String? notes;
  final String? systemCode;
  final DateTime? lastMovementAt;
}

class RemoteEnvelopeMovement {
  const RemoteEnvelopeMovement({
    required this.description,
    required this.type,
    required this.amount,
    required this.direction,
    required this.occurredAt,
  });
  final String description;
  final String type;
  final Money amount;
  final String direction;
  final DateTime occurredAt;

  String get displayType => switch (type) {
    'consumption' => 'Dépense',
    'allocation' => 'Alimentation',
    'transfer_in' => 'Transfert entrant',
    'transfer_out' => 'Transfert sortant',
    'refund' => 'Remboursement',
    'opening' => 'Solde initial',
    'adjustment' => 'Ajustement',
    _ => 'Mouvement',
  };
}

abstract interface class EnvelopeTransferGateway {
  Future<String> transfer(Map<String, Object?> parameters);
}

class EnvelopeDistributionLine {
  const EnvelopeDistributionLine({
    required this.envelopeId,
    required this.amount,
  });

  final String envelopeId;
  final Money amount;
}

abstract interface class ToAllocateDistributionGateway {
  Future<String> distribute(Map<String, Object?> parameters);
}

class SupabaseEnvelopeTransferGateway implements EnvelopeTransferGateway {
  SupabaseEnvelopeTransferGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<String> transfer(Map<String, Object?> parameters) async {
    final result = await _client.rpc(
      'create_envelope_transfer_event',
      params: parameters,
    );
    if (result is! String || result.isEmpty) {
      throw StateError('Le transfert n’a retourné aucun identifiant.');
    }
    return result;
  }
}

class SupabaseToAllocateDistributionGateway
    implements ToAllocateDistributionGateway {
  SupabaseToAllocateDistributionGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<String> distribute(Map<String, Object?> parameters) async {
    final result = await _client.rpc(
      'distribute_to_allocate_envelope_event',
      params: parameters,
    );
    if (result is! String || result.isEmpty) {
      throw StateError('La répartition n’a retourné aucun identifiant.');
    }
    return result;
  }
}

final envelopeTransferGatewayProvider = Provider<EnvelopeTransferGateway>(
  (ref) => SupabaseEnvelopeTransferGateway(ref.watch(supabaseClientProvider)),
);

final toAllocateDistributionGatewayProvider =
    Provider<ToAllocateDistributionGateway>(
      (ref) => SupabaseToAllocateDistributionGateway(
        ref.watch(supabaseClientProvider),
      ),
    );

final distributeToAllocateEnvelopeProvider =
    Provider<
      Future<String> Function({
        required List<EnvelopeDistributionLine> destinations,
        required DateTime occurredAt,
        required String description,
        String? notes,
        required String idempotencyKey,
      })
    >((ref) {
      return ({
        required List<EnvelopeDistributionLine> destinations,
        required DateTime occurredAt,
        required String description,
        String? notes,
        required String idempotencyKey,
      }) async {
        final household = await ref.read(activeHouseholdProvider.future);
        final householdId = household.householdId;
        if (!household.hasActiveHousehold || householdId == null) {
          throw StateError('Aucun foyer actif sans ambiguïté.');
        }
        return ref.read(toAllocateDistributionGatewayProvider).distribute({
          'p_household_id': householdId,
          'p_occurred_at': occurredAt.toUtc().toIso8601String(),
          'p_description': description.trim(),
          'p_destination_allocations': [
            for (final line in destinations)
              {
                'envelope_id': line.envelopeId,
                'amount': line.amount.dirhams.toStringAsFixed(2),
              },
          ],
          'p_notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
          'p_idempotency_key': idempotencyKey,
        });
      };
    });

String newEnvelopeDistributionIdempotencyKey() {
  final random = Random.secure();
  final values = List<int>.generate(16, (_) => random.nextInt(256));
  values[6] = (values[6] & 0x0f) | 0x40;
  values[8] = (values[8] & 0x3f) | 0x80;
  String group(int start, int end) => values
      .sublist(start, end)
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${group(0, 4)}-${group(4, 6)}-${group(6, 8)}-${group(8, 10)}-${group(10, 16)}';
}

final createRemoteEnvelopeTransferProvider =
    Provider<
      Future<String> Function({
        required String sourceEnvelopeId,
        required String destinationEnvelopeId,
        required Money amount,
        required DateTime occurredAt,
        required String description,
        required String idempotencyKey,
      })
    >((ref) {
      return ({
        required String sourceEnvelopeId,
        required String destinationEnvelopeId,
        required Money amount,
        required DateTime occurredAt,
        required String description,
        required String idempotencyKey,
      }) async {
        final household = await ref.read(activeHouseholdProvider.future);
        final householdId = household.householdId;
        if (!household.hasActiveHousehold || householdId == null) {
          throw StateError('Aucun foyer actif sans ambiguïté.');
        }
        return ref.read(envelopeTransferGatewayProvider).transfer({
          'p_household_id': householdId,
          'p_source_envelope_id': sourceEnvelopeId,
          'p_destination_envelope_id': destinationEnvelopeId,
          'p_amount': amount.dirhams.toStringAsFixed(2),
          'p_occurred_at': occurredAt.toUtc().toIso8601String(),
          'p_description': description.trim(),
          'p_notes': null,
          'p_idempotency_key': idempotencyKey,
        });
      };
    });

final createRemoteEnvelopeProvider =
    Provider<
      Future<void> Function({
        required String name,
        required Money openingBalance,
        String? notes,
      })
    >((ref) {
      return ({
        required String name,
        required Money openingBalance,
        String? notes,
      }) async {
        final household = await ref.read(activeHouseholdProvider.future);
        final householdId = household.householdId;
        if (!household.hasActiveHousehold || householdId == null) {
          throw StateError('Aucun foyer actif sans ambiguïté.');
        }
        await ref
            .read(supabaseClientProvider)
            .rpc(
              'create_household_envelope',
              params: {
                'p_household_id': householdId,
                'p_name': name.trim(),
                'p_opening_balance': openingBalance.dirhams.toStringAsFixed(2),
                'p_notes': notes?.trim(),
              },
            );
      };
    });

final updateRemoteEnvelopeProvider =
    Provider<
      Future<void> Function({
        required String envelopeId,
        required String name,
        String? notes,
        required bool archived,
      })
    >((ref) {
      return ({
        required String envelopeId,
        required String name,
        String? notes,
        required bool archived,
      }) async {
        final household = await ref.read(activeHouseholdProvider.future);
        final householdId = household.householdId;
        if (!household.hasActiveHousehold || householdId == null) {
          throw StateError('Aucun foyer actif sans ambiguïté.');
        }
        await ref
            .read(supabaseClientProvider)
            .rpc(
              'update_household_envelope',
              params: {
                'p_household_id': householdId,
                'p_envelope_id': envelopeId,
                'p_name': name.trim(),
                'p_notes': notes?.trim(),
                'p_archived': archived,
              },
            );
      };
    });

final deleteRemoteEnvelopeProvider = Provider<Future<void> Function(String)>((
  ref,
) {
  return (envelopeId) async {
    final household = await ref.read(activeHouseholdProvider.future);
    final householdId = household.householdId;
    if (!household.hasActiveHousehold || householdId == null) {
      throw StateError('Aucun foyer actif sans ambiguïté.');
    }
    await ref
        .read(supabaseClientProvider)
        .rpc(
          'delete_household_envelope',
          params: {'p_household_id': householdId, 'p_envelope_id': envelopeId},
        );
  };
});

final undoLastEnvelopeImportProvider = Provider<Future<int> Function()>((ref) {
  return () async {
    final household = await ref.read(activeHouseholdProvider.future);
    final householdId = household.householdId;
    if (!household.hasActiveHousehold || householdId == null) {
      throw StateError('Aucun foyer actif sans ambiguïté.');
    }
    final result = await ref
        .read(supabaseClientProvider)
        .rpc(
          'undo_last_envelope_import',
          params: {'p_household_id': householdId},
        );
    return result as int;
  };
});

final remoteEnvelopeHistoryProvider = FutureProvider<List<RemoteEnvelopeBalance>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  final client = ref.watch(supabaseClientProvider);
  final envelopeRows = await client
      .from('envelopes')
      .select('id, name, notes, archived_at, is_system, system_code')
      .eq('household_id', householdId)
      .order('name', ascending: true);
  final rows = await client
      .from('envelope_ledger_balances')
      .select(
        'envelope_id, envelope_name, inflows, outflows, balance, is_system, system_code, last_movement_at',
      )
      .eq('household_id', householdId)
      .order('envelope_name', ascending: true);
  final balanceRowsByEnvelopeId = <String, Map<String, Object?>>{
    for (final raw in rows as List<dynamic>)
      (raw as Map)['envelope_id'] as String: Map<String, Object?>.from(raw),
  };
  return List.unmodifiable(
    (envelopeRows as List<dynamic>).map((raw) {
      final envelope = Map<String, Object?>.from(raw as Map);
      final id = envelope['id'] as String;
      final balance = balanceRowsByEnvelopeId[id];
      return RemoteEnvelopeBalance(
        id: id,
        name: envelope['name'] as String,
        inflows: _money(balance?['inflows'] ?? 0),
        outflows: _money(balance?['outflows'] ?? 0),
        balance: _money(balance?['balance'] ?? 0),
        isSystem: envelope['is_system'] == true,
        systemCode: envelope['system_code'] as String?,
        isArchived: envelope['archived_at'] != null,
        notes: envelope['notes'] as String?,
        lastMovementAt: balance?['last_movement_at'] is String
            ? DateTime.tryParse(balance!['last_movement_at'] as String)
            : null,
      );
    }),
  );
});

final remoteEnvelopeBalancesProvider =
    FutureProvider<List<RemoteEnvelopeBalance>>((ref) async {
      final history = await ref.watch(remoteEnvelopeHistoryProvider.future);
      return List.unmodifiable(
        history.where((envelope) => !envelope.isArchived && !envelope.isSystem),
      );
    });

final remoteEnvelopeMovementsProvider =
    FutureProvider.family<List<RemoteEnvelopeMovement>, String>((
      ref,
      envelopeId,
    ) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      final rows = await ref
          .watch(supabaseClientProvider)
          .from('envelope_movements')
          .select('description, movement_type, amount, direction, occurred_at')
          .eq('household_id', householdId)
          .eq('envelope_id', envelopeId)
          .order('occurred_at', ascending: false);
      return List.unmodifiable(
        (rows as List<dynamic>).map((raw) {
          final row = Map<String, Object?>.from(raw as Map);
          return RemoteEnvelopeMovement(
            description: row['description'] as String,
            type: row['movement_type'] as String,
            amount: _money(row['amount']),
            direction: row['direction'] as String,
            occurredAt: DateTime.parse(row['occurred_at'] as String),
          );
        }),
      );
    });

Money _money(Object? value) {
  final match = RegExp(
    r'^(-?)(\d+)(?:[.,](\d{1,2}))?$',
  ).firstMatch(value.toString());
  if (match == null) {
    throw StateError('Montant d’enveloppe invalide.');
  }
  final cents =
      int.parse(match.group(2)!) * 100 +
      int.parse((match.group(3) ?? '').padRight(2, '0'));
  return Money.fromMinorUnits(match.group(1) == '-' ? -cents : cents);
}
