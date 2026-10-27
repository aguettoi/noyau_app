import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../organization/application/daily_life_provider.dart';
import '../../organization/application/organization_provider.dart';
import '../domain/offline_draft.dart';
import 'experience_provider.dart';

abstract interface class OfflineDraftAdapter {
  String get actionKind;
  Future<void> submit(OfflineDraft draft);
}

class OfflineSyncReport {
  const OfflineSyncReport({required this.synced, required this.remaining});
  final int synced;
  final List<OfflineDraft> remaining;
}

class OfflineSyncCoordinator {
  OfflineSyncCoordinator(this.store, this.adapters);
  final ExperienceStore store;
  final Map<String, OfflineDraftAdapter> adapters;
  Future<OfflineSyncReport>? _inFlight;

  Future<OfflineSyncReport> synchronize() {
    final current = _inFlight;
    if (current != null) return current;
    final operation = _synchronize();
    late final Future<OfflineSyncReport> guarded;
    guarded = operation.whenComplete(() {
      if (identical(_inFlight, guarded)) _inFlight = null;
    });
    _inFlight = guarded;
    return guarded;
  }

  Future<OfflineSyncReport> _synchronize() async {
    final drafts = await store.loadDrafts();
    final remaining = <OfflineDraft>[];
    var synced = 0;
    for (final draft in drafts) {
      final adapter = adapters[draft.actionKind];
      if (adapter == null ||
          classifyOfflineAction(draft.actionKind) ==
              OfflineCapability.serverRequired) {
        remaining.add(draft.copyWith(state: OfflineDraftState.actionRequired));
        continue;
      }
      try {
        await adapter.submit(draft.copyWith(state: OfflineDraftState.syncing));
        synced++;
      } catch (_) {
        remaining.add(draft.copyWith(state: OfflineDraftState.actionRequired));
      }
    }
    await store.saveDrafts(remaining);
    return OfflineSyncReport(synced: synced, remaining: remaining);
  }
}

class _TaskDraftAdapter implements OfflineDraftAdapter {
  const _TaskDraftAdapter(this.ref);
  final Ref ref;
  @override
  String get actionKind => 'task';
  @override
  Future<void> submit(OfflineDraft draft) async {
    final household = await ref.read(activeHouseholdProvider.future);
    final user = ref.read(currentUserIdProvider);
    if (household.householdId != draft.householdId ||
        user == null ||
        user != draft.memberId) {
      throw StateError('Le contexte du brouillon a changé.');
    }
    try {
      await ref.read(organizationGatewayProvider).createTask(
        household.householdId!,
        user,
        {'id': draft.idempotencyKey, ...draft.payload},
      );
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
  }
}

class _GroceryDraftAdapter implements OfflineDraftAdapter {
  const _GroceryDraftAdapter(this.ref);
  final Ref ref;
  @override
  String get actionKind => 'grocery_item';
  @override
  Future<void> submit(OfflineDraft draft) async {
    final household = await ref.read(activeHouseholdProvider.future);
    final user = ref.read(currentUserIdProvider);
    if (household.householdId != draft.householdId ||
        user == null ||
        user != draft.memberId) {
      throw StateError('Le contexte du brouillon a changé.');
    }
    try {
      await ref
          .read(dailyLifeActionsProvider)
          .addGrocery(
            draft.payload['label']! as String,
            idempotencyKey: draft.idempotencyKey,
            quantity: (draft.payload['quantity'] as num?)?.toDouble() ?? 1,
            unit: draft.payload['unit'] as String?,
            assignee: draft.payload['assignee_user_id'] as String?,
          );
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
  }
}

final offlineSyncCoordinatorProvider = Provider((ref) {
  final adapters = <OfflineDraftAdapter>[
    _TaskDraftAdapter(ref),
    _GroceryDraftAdapter(ref),
  ];
  return OfflineSyncCoordinator(ref.watch(experienceStoreProvider), {
    for (final adapter in adapters) adapter.actionKind: adapter,
  });
});
