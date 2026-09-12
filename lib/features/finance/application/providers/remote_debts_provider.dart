import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money/money.dart';
import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

class RemoteDebtBalance {
  const RemoteDebtBalance({
    required this.id,
    required this.description,
    required this.initialAmount,
    required this.settledAmount,
    this.writtenOffAmount = const Money.fromMinorUnits(0),
    required this.remainingAmount,
    required this.status,
    this.creditorName,
    this.dueAt,
  });

  final String id;
  final String description;
  final String? creditorName;
  final Money initialAmount;
  final Money settledAmount;
  final Money writtenOffAmount;
  final Money remainingAmount;
  final String status;
  final DateTime? dueAt;

  String get displayStatus => switch (status) {
    'settled' => 'Soldée',
    'written_off' => 'Éteinte par abandon',
    _ when settledAmount.minorUnits > 0 => 'Partiellement réglée',
    _ => 'Ouverte',
  };
}

final remoteDebtBalancesProvider = FutureProvider<List<RemoteDebtBalance>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('obligation_balances')
      .select(
        'obligation_id, description, counterparty_name, initial_amount, settled_amount, written_off_amount, remaining_amount, status, due_at',
      )
      .eq('household_id', householdId)
      .eq('obligation_kind', 'debt')
      .order('created_at', ascending: false);
  return List.unmodifiable(
    (rows as List<dynamic>).map((raw) {
      final row = Map<String, Object?>.from(raw as Map);
      return RemoteDebtBalance(
        id: row['obligation_id'] as String,
        description: row['description'] as String,
        creditorName: row['counterparty_name'] as String?,
        initialAmount: _money(row['initial_amount']),
        settledAmount: _money(row['settled_amount']),
        writtenOffAmount: _money(row['written_off_amount']),
        remainingAmount: _money(row['remaining_amount']),
        status: row['status'] as String,
        dueAt: row['due_at'] is String
            ? DateTime.tryParse(row['due_at'] as String)
            : null,
      );
    }),
  );
});

class RemoteReceivableBalance {
  const RemoteReceivableBalance({
    required this.id,
    required this.description,
    required this.kind,
    required this.initialAmount,
    required this.settledAmount,
    this.writtenOffAmount = const Money.fromMinorUnits(0),
    required this.remainingAmount,
    required this.status,
    this.counterpartyName,
    this.recoverySourceEnvelopeId,
  });

  final String id;
  final String description;
  final String kind;
  final String? counterpartyName;
  final String? recoverySourceEnvelopeId;
  final Money initialAmount;
  final Money settledAmount;
  final Money writtenOffAmount;
  final Money remainingAmount;
  final String status;

  String get displayKind =>
      kind == 'recovery' ? 'Remboursement / Recovery' : 'Revenu à encaisser';
  String get displayStatus => switch (status) {
    'settled' => 'Soldée',
    'written_off' => 'Éteinte par abandon',
    _ when settledAmount.minorUnits > 0 => 'Partiellement encaissée',
    _ => 'Ouverte',
  };
}

class RemoteSettlementEnvelopeMovement {
  const RemoteSettlementEnvelopeMovement({
    required this.id,
    required this.envelopeName,
    required this.amount,
  });

  final String id;
  final String envelopeName;
  final Money amount;
}

class RemoteSettlementReversal {
  const RemoteSettlementReversal({
    required this.id,
    required this.recordedAt,
    required this.amount,
    required this.reason,
    required this.notes,
    required this.netAmountAfter,
    required this.actor,
    this.envelopeMovements = const [],
  });

  final String id;
  final DateTime recordedAt;
  final Money amount;
  final String reason;
  final String? notes;
  final Money netAmountAfter;
  final RemoteHistoryActor actor;
  final List<RemoteSettlementEnvelopeMovement> envelopeMovements;
}

/// The authenticated user who performed an immutable financial event.
/// This is intentionally distinct from a counterparty, account holder or
/// budget member.
class RemoteHistoryActor {
  const RemoteHistoryActor({required this.userId, required this.displayName});

  final String userId;
  final String displayName;
}

class RemoteSettlementHistoryItem {
  const RemoteSettlementHistoryItem({
    required this.id,
    required this.recordedAt,
    required this.grossAmount,
    required this.reversedAmount,
    required this.accountName,
    required this.envelopeMovements,
    required this.reversals,
    required this.actor,
  });

  final String id;
  final DateTime recordedAt;
  final Money grossAmount;
  final Money reversedAmount;
  final String? accountName;
  final List<RemoteSettlementEnvelopeMovement> envelopeMovements;
  final List<RemoteSettlementReversal> reversals;
  final RemoteHistoryActor actor;

  Money get netAmount =>
      Money.fromMinorUnits(grossAmount.minorUnits - reversedAmount.minorUnits);

  Money get reversibleAmount => netAmount;
}

class RemoteObligationCreationHistoryItem {
  const RemoteObligationCreationHistoryItem({
    required this.recordedAt,
    required this.actor,
  });

  final DateTime recordedAt;
  final RemoteHistoryActor actor;
}

class RemoteObligationWriteoffHistoryItem {
  const RemoteObligationWriteoffHistoryItem({
    required this.id,
    required this.recordedAt,
    required this.amount,
    required this.reason,
    required this.notes,
    required this.actor,
  });

  final String id;
  final DateTime recordedAt;
  final Money amount;
  final String reason;
  final String? notes;
  final RemoteHistoryActor actor;
}

class RemoteObligationHistory {
  const RemoteObligationHistory({
    required this.creation,
    required this.settlements,
    required this.writeoffs,
  });

  final RemoteObligationCreationHistoryItem? creation;
  final List<RemoteSettlementHistoryItem> settlements;
  final List<RemoteObligationWriteoffHistoryItem> writeoffs;
}

final obligationSettlementHistoryProvider =
    FutureProvider.family<RemoteObligationHistory, String>((
      ref,
      obligationId,
    ) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      final client = ref.watch(supabaseClientProvider);
      final obligationRows = await client
          .from('obligations')
          .select('origin_event_id')
          .eq('household_id', householdId)
          .eq('id', obligationId)
          .limit(1);
      final obligationRow = (obligationRows as List<dynamic>)
          .cast<Map<dynamic, dynamic>>()
          .map((raw) => Map<String, Object?>.from(raw))
          .firstOrNull;
      if (obligationRow == null) {
        throw StateError('Obligation introuvable.');
      }
      final settlementRows = await client
          .from('obligation_settlements')
          .select('id, event_id, financial_transaction_id, amount, occurred_at')
          .eq('household_id', householdId)
          .eq('obligation_id', obligationId)
          .order('occurred_at', ascending: false);
      final rows = (settlementRows as List<dynamic>)
          .map((raw) => Map<String, Object?>.from(raw as Map))
          .toList(growable: false);
      final settlementIds = rows.map((row) => row['id'] as String).toList();
      final eventIds = rows.map((row) => row['event_id'] as String).toList();
      final transactionIds = rows
          .map((row) => row['financial_transaction_id'] as String)
          .toList();
      final reversalRows = await client
          .from('obligation_settlement_reversals')
          .select(
            'id, source_settlement_id, financial_event_id, amount, occurred_at, reason, notes',
          )
          .eq('household_id', householdId)
          .inFilter(
            'source_settlement_id',
            settlementIds.isEmpty
                ? const <String>['00000000-0000-0000-0000-000000000000']
                : settlementIds,
          )
          .order('occurred_at');
      final reversalEventIds = <String>[
        for (final raw in reversalRows as List<dynamic>)
          (raw as Map)['financial_event_id'] as String,
      ];
      final writeoffRows = await client
          .from('obligation_adjustments')
          .select('id, financial_event_id, amount, occurred_at, reason, notes')
          .eq('household_id', householdId)
          .eq('obligation_id', obligationId)
          .eq('adjustment_kind', 'writeoff')
          .order('occurred_at');
      final reversalsBySettlement = <String, int>{};
      final reversalRowsBySettlement = <String, List<Map<String, Object?>>>{};
      for (final raw in reversalRows as List<dynamic>) {
        final row = Map<String, Object?>.from(raw as Map);
        final id = row['source_settlement_id'] as String;
        reversalsBySettlement[id] =
            (reversalsBySettlement[id] ?? 0) + _money(row['amount']).minorUnits;
        reversalRowsBySettlement.putIfAbsent(id, () => []).add(row);
      }
      final movementRows = await client
          .from('envelope_movements')
          .select('id, event_id, envelope_id, amount, direction')
          .eq('household_id', householdId)
          .inFilter(
            'event_id',
            eventIds.isEmpty
                ? const <String>['00000000-0000-0000-0000-000000000000']
                : eventIds,
          )
          .neq('movement_type', 'reversal');
      final reversalMovementRows = await client
          .from('envelope_movements')
          .select('id, event_id, envelope_id, amount, direction')
          .eq('household_id', householdId)
          .eq('movement_type', 'reversal')
          .inFilter(
            'event_id',
            reversalEventIds.isEmpty
                ? const <String>['00000000-0000-0000-0000-000000000000']
                : reversalEventIds,
          );
      final envelopeIds = <String>{
        for (final raw in movementRows as List<dynamic>)
          raw['envelope_id'] as String,
        for (final raw in reversalMovementRows as List<dynamic>)
          raw['envelope_id'] as String,
      };
      final envelopes = envelopeIds.isEmpty
          ? const <dynamic>[]
          : await client
                .from('envelopes')
                .select('id, name')
                .inFilter('id', envelopeIds.toList());
      final envelopeNames = <String, String>{
        for (final raw in envelopes) raw['id']: raw['name'] as String,
      };
      final movementsByEvent =
          <String, List<RemoteSettlementEnvelopeMovement>>{};
      for (final raw in movementRows as List<dynamic>) {
        final row = Map<String, Object?>.from(raw as Map);
        if (row['direction'] != 'inflow') continue;
        final eventId = row['event_id'] as String;
        movementsByEvent
            .putIfAbsent(eventId, () => [])
            .add(
              RemoteSettlementEnvelopeMovement(
                id: row['id'] as String,
                envelopeName:
                    envelopeNames[row['envelope_id'] as String] ??
                    'Enveloppe supprimée',
                amount: _money(row['amount']),
              ),
            );
      }
      final reversalMovementsByEvent =
          <String, List<RemoteSettlementEnvelopeMovement>>{};
      for (final raw in reversalMovementRows as List<dynamic>) {
        final row = Map<String, Object?>.from(raw as Map);
        if (row['direction'] != 'outflow') continue;
        final eventId = row['event_id'] as String;
        reversalMovementsByEvent
            .putIfAbsent(eventId, () => [])
            .add(
              RemoteSettlementEnvelopeMovement(
                id: row['id'] as String,
                envelopeName:
                    envelopeNames[row['envelope_id'] as String] ??
                    'Enveloppe supprimée',
                amount: _money(row['amount']),
              ),
            );
      }
      final transactionRows = await client
          .from('financial_transactions')
          .select('id, source_account_id, destination_account_id')
          .inFilter(
            'id',
            transactionIds.isEmpty
                ? const <String>['00000000-0000-0000-0000-000000000000']
                : transactionIds,
          );
      final accountIds = <String>{
        for (final raw in transactionRows as List<dynamic>) ...[
          if (raw['source_account_id'] is String)
            raw['source_account_id'] as String,
          if (raw['destination_account_id'] is String)
            raw['destination_account_id'] as String,
        ],
      };
      final accounts = accountIds.isEmpty
          ? const <dynamic>[]
          : await client
                .from('accounts')
                .select('id, name')
                .inFilter('id', accountIds.toList());
      final accountNames = <String, String>{
        for (final raw in accounts) raw['id']: raw['name'] as String,
      };
      final accountByTransaction = <String, String?>{};
      for (final raw in transactionRows as List<dynamic>) {
        final row = raw;
        final accountId =
            (row['source_account_id'] ?? row['destination_account_id'])
                as String?;
        accountByTransaction[row['id'] as String] = accountId == null
            ? null
            : accountNames[accountId];
      }
      final allEventIds = <String>{
        obligationRow['origin_event_id'] as String,
        ...eventIds,
        for (final raw in reversalRows as List<dynamic>)
          (raw as Map)['financial_event_id'] as String,
        for (final raw in writeoffRows as List<dynamic>)
          (raw as Map)['financial_event_id'] as String,
      };
      final eventRows = await client
          .from('financial_events')
          .select('id, created_by, created_at')
          .eq('household_id', householdId)
          .inFilter('id', allEventIds.toList());
      final eventById = <String, Map<String, Object?>>{
        for (final raw in eventRows as List<dynamic>)
          (raw as Map)['id'] as String: Map<String, Object?>.from(raw),
      };
      final actorIds = <String>{
        for (final event in eventById.values)
          if (event['created_by'] is String) event['created_by'] as String,
      };
      final profiles = actorIds.isEmpty
          ? const <dynamic>[]
          : await client
                .from('profiles')
                .select('id, display_name')
                .inFilter('id', actorIds.toList());
      final namesByActorId = <String, String>{
        for (final raw in profiles)
          if ((raw as Map)['id'] is String && raw['display_name'] is String)
            raw['id'] as String: (raw['display_name'] as String).trim(),
      };
      RemoteHistoryActor actorFor(String eventId) {
        final actorId = eventById[eventId]?['created_by'] as String?;
        return RemoteHistoryActor(
          userId: actorId ?? '',
          displayName: actorId == null || actorId.isEmpty
              ? 'Utilisateur inconnu'
              : namesByActorId[actorId]?.isNotEmpty == true
              ? namesByActorId[actorId]!
              : 'Utilisateur inconnu',
        );
      }

      DateTime recordedAtFor(String eventId, Object? fallback) =>
          DateTime.tryParse(
            eventById[eventId]?['created_at'] as String? ?? '',
          ) ??
          DateTime.parse(fallback as String);
      final settlements = List<RemoteSettlementHistoryItem>.unmodifiable(
        rows.map((row) {
          final id = row['id'] as String;
          var netMinorUnits = _money(row['amount']).minorUnits;
          final reversals = <RemoteSettlementReversal>[
            for (final reversal in reversalRowsBySettlement[id] ?? const [])
              RemoteSettlementReversal(
                id: reversal['id'] as String,
                recordedAt: recordedAtFor(
                  reversal['financial_event_id'] as String,
                  reversal['occurred_at'],
                ),
                amount: _money(reversal['amount']),
                reason: reversal['reason'] as String,
                notes: reversal['notes'] as String?,
                netAmountAfter: Money.fromMinorUnits(
                  netMinorUnits -= _money(reversal['amount']).minorUnits,
                ),
                actor: actorFor(reversal['financial_event_id'] as String),
                envelopeMovements: List.unmodifiable(
                  reversalMovementsByEvent[reversal['financial_event_id']
                          as String] ??
                      const [],
                ),
              ),
          ];
          return RemoteSettlementHistoryItem(
            id: id,
            recordedAt: recordedAtFor(
              row['event_id'] as String,
              row['occurred_at'],
            ),
            grossAmount: _money(row['amount']),
            reversedAmount: Money.fromMinorUnits(
              reversalsBySettlement[id] ?? 0,
            ),
            accountName:
                accountByTransaction[row['financial_transaction_id'] as String],
            envelopeMovements: List.unmodifiable(
              movementsByEvent[row['event_id'] as String] ?? const [],
            ),
            reversals: List.unmodifiable(reversals),
            actor: actorFor(row['event_id'] as String),
          );
        }),
      );
      final creationEventId = obligationRow['origin_event_id'] as String;
      final creation = eventById.containsKey(creationEventId)
          ? RemoteObligationCreationHistoryItem(
              recordedAt: recordedAtFor(
                creationEventId,
                DateTime.now().toIso8601String(),
              ),
              actor: actorFor(creationEventId),
            )
          : null;
      final writeoffs = List<RemoteObligationWriteoffHistoryItem>.unmodifiable(
        (writeoffRows as List<dynamic>).map((raw) {
          final row = Map<String, Object?>.from(raw as Map);
          final eventId = row['financial_event_id'] as String;
          return RemoteObligationWriteoffHistoryItem(
            id: row['id'] as String,
            recordedAt: recordedAtFor(eventId, row['occurred_at']),
            amount: _money(row['amount']),
            reason: row['reason'] as String,
            notes: row['notes'] as String?,
            actor: actorFor(eventId),
          );
        }),
      );
      return RemoteObligationHistory(
        creation: creation,
        settlements: settlements,
        writeoffs: writeoffs,
      );
    });

final remoteReceivableBalancesProvider =
    FutureProvider<List<RemoteReceivableBalance>>((ref) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      final rows = await ref
          .watch(supabaseClientProvider)
          .from('obligation_balances')
          .select(
            'obligation_id, description, receivable_kind, counterparty_name, recovery_source_envelope_id, initial_amount, settled_amount, written_off_amount, remaining_amount, status',
          )
          .eq('household_id', householdId)
          .eq('obligation_kind', 'receivable')
          .order('created_at', ascending: false);
      return List.unmodifiable(
        (rows as List<dynamic>).map((raw) {
          final row = Map<String, Object?>.from(raw as Map);
          return RemoteReceivableBalance(
            id: row['obligation_id'] as String,
            description: row['description'] as String,
            kind: row['receivable_kind'] as String? ?? 'income',
            counterpartyName: row['counterparty_name'] as String?,
            recoverySourceEnvelopeId:
                row['recovery_source_envelope_id'] as String?,
            initialAmount: _money(row['initial_amount']),
            settledAmount: _money(row['settled_amount']),
            writtenOffAmount: _money(row['written_off_amount']),
            remainingAmount: _money(row['remaining_amount']),
            status: row['status'] as String,
          );
        }),
      );
    });

class RecoveryExpenseSource {
  const RecoveryExpenseSource({
    required this.eventId,
    required this.description,
    required this.occurredAt,
    required this.sourceAmount,
    required this.committedAmount,
    required this.maximumAmount,
    this.accountName,
    this.envelopeId,
    this.envelopeName,
  });

  final String eventId;
  final String description;
  final DateTime occurredAt;
  final Money sourceAmount;
  final Money committedAmount;
  final Money maximumAmount;
  final String? accountName;
  final String? envelopeId;
  final String? envelopeName;

  static Money? remainingFor({
    required Money sourceAmount,
    required Money committedAmount,
  }) {
    final remaining = sourceAmount.minorUnits - committedAmount.minorUnits;
    return remaining > 0 ? Money.fromMinorUnits(remaining) : null;
  }
}

final eligibleRecoverySourcesProvider =
    FutureProvider<List<RecoveryExpenseSource>>((ref) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      final rows = await ref
          .watch(supabaseClientProvider)
          .from('financial_transactions')
          .select(
            'event_id, description, occurred_at, amount, '
            'accounts!financial_transactions_source_account_id_fkey(name), '
            'envelope_movements(envelope_id, amount, movement_type, direction, envelopes(name))',
          )
          .eq('household_id', householdId)
          .eq('type', 'expense')
          .not('event_id', 'is', null)
          .isFilter('archived_at', null)
          .order('occurred_at', ascending: false);
      final eventIds = (rows as List<dynamic>)
          .map((row) => (row as Map)['event_id'] as String?)
          .whereType<String>()
          .toSet();
      final committedByEvent = <String, Money>{};
      if (eventIds.isNotEmpty) {
        final committedRows = await ref
            .watch(supabaseClientProvider)
            .from('obligations')
            .select('recovery_source_event_id, initial_amount')
            .eq('household_id', householdId)
            .eq('obligation_kind', 'receivable')
            .eq('receivable_kind', 'recovery')
            .inFilter('recovery_source_event_id', eventIds.toList());
        for (final committedRaw in committedRows as List<dynamic>) {
          final committed = Map<String, Object?>.from(committedRaw as Map);
          final eventId = committed['recovery_source_event_id'] as String?;
          if (eventId == null) continue;
          committedByEvent[eventId] =
              (committedByEvent[eventId] ?? Money.fromMinorUnits(0)) +
              _money(committed['initial_amount']);
        }
      }

      final sources = <RecoveryExpenseSource>[];
      for (final raw in rows as List<dynamic>) {
        final row = Map<String, Object?>.from(raw as Map);
        final eventId = row['event_id'] as String?;
        final occurredAt = row['occurred_at'] is String
            ? DateTime.tryParse(row['occurred_at'] as String)
            : null;
        if (eventId == null || occurredAt == null) continue;
        final sourceAmount = _money(row['amount']);
        final committedAmount =
            committedByEvent[eventId] ?? Money.fromMinorUnits(0);
        final remainingAmount = RecoveryExpenseSource.remainingFor(
          sourceAmount: sourceAmount,
          committedAmount: committedAmount,
        );
        if (remainingAmount == null) continue;
        final account = row['accounts'] as Map?;
        final movements = row['envelope_movements'] as List? ?? const [];
        var hasConsumption = false;
        for (final movementRaw in movements) {
          final movement = Map<String, Object?>.from(movementRaw as Map);
          if (movement['movement_type'] != 'consumption' ||
              movement['direction'] != 'outflow') {
            continue;
          }
          final amount = _money(movement['amount']);
          if (amount.minorUnits <= 0) continue;
          hasConsumption = true;
          final envelope = movement['envelopes'] as Map?;
          sources.add(
            RecoveryExpenseSource(
              eventId: eventId,
              description: row['description'] as String,
              occurredAt: occurredAt,
              sourceAmount: sourceAmount,
              committedAmount: committedAmount,
              maximumAmount: remainingAmount,
              accountName: account?['name'] as String?,
              envelopeId: movement['envelope_id'] as String?,
              envelopeName: envelope?['name'] as String?,
            ),
          );
        }
        if (!hasConsumption) {
          sources.add(
            RecoveryExpenseSource(
              eventId: eventId,
              description: row['description'] as String,
              occurredAt: occurredAt,
              sourceAmount: sourceAmount,
              committedAmount: committedAmount,
              maximumAmount: remainingAmount,
              accountName: account?['name'] as String?,
            ),
          );
        }
      }
      return List.unmodifiable(sources);
    });

Money _money(Object? value) {
  final match = RegExp(
    r'^(-?)(\d+)(?:[.,](\d{1,2}))?$',
  ).firstMatch(value.toString());
  if (match == null) throw StateError('Montant de dette invalide.');
  final cents =
      int.parse(match.group(2)!) * 100 +
      int.parse((match.group(3) ?? '').padRight(2, '0'));
  return Money.fromMinorUnits(match.group(1) == '-' ? -cents : cents);
}
