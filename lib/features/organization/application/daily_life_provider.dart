import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_failure.dart';
import '../../experience/application/experience_provider.dart';
import '../../experience/application/offline_connectivity.dart';
import '../../experience/domain/offline_draft.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../domain/cycle_tracking.dart';
import '../domain/organization_models.dart';

Map<String, Object?> _map(dynamic value) =>
    Map<String, Object?>.from(value as Map);

final groceryItemsProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  final userId = ref.watch(currentUserIdProvider);
  if (householdId == null || userId == null) return const [];
  final store = ref.watch(experienceStoreProvider);
  final cached = await store.loadReadSnapshot(
    kind: 'household_groceries',
    householdId: householdId,
    userId: userId,
  );
  final connection = ref.read(syncConnectionStateProvider);
  if (connection == SyncConnectionState.offline ||
      connection == SyncConnectionState.reconnecting) {
    if (cached == null) {
      throw StateError('Aucune copie locale des courses disponible.');
    }
    setOfflineSnapshotStatus(
      ref,
      'household_groceries',
      OfflineSnapshotStatus(capturedAt: cached.capturedAt, stale: true),
    );
    return _mergePendingGroceries(
      cached.rows,
      await store.loadDrafts(),
      householdId,
      userId,
    );
  }
  try {
    final rows = await ref
        .watch(supabaseClientProvider)
        .from('household_grocery_items')
        .select()
        .eq('household_id', householdId)
        .order('created_at');
    final serverRows = [for (final row in rows as List<dynamic>) _map(row)];
    final capturedAt = DateTime.now().toUtc();
    await store.saveReadSnapshot(
      kind: 'household_groceries',
      householdId: householdId,
      userId: userId,
      rows: serverRows,
      capturedAt: capturedAt,
    );
    setOfflineSnapshotStatus(
      ref,
      'household_groceries',
      OfflineSnapshotStatus(capturedAt: capturedAt, stale: false),
    );
    return _mergePendingGroceries(
      serverRows,
      await store.loadDrafts(),
      householdId,
      userId,
    );
  } catch (error) {
    if (!isNetworkFailure(error)) rethrow;
    reportOfflineFailure(ref);
    if (cached == null) rethrow;
    setOfflineSnapshotStatus(
      ref,
      'household_groceries',
      OfflineSnapshotStatus(capturedAt: cached.capturedAt, stale: true),
    );
    return _mergePendingGroceries(
      cached.rows,
      await store.loadDrafts(),
      householdId,
      userId,
    );
  }
});

List<Map<String, Object?>> _mergePendingGroceries(
  List<Map<String, Object?>> rows,
  List<OfflineDraft> drafts,
  String householdId,
  String userId,
) {
  final ids = rows.map((row) => row['id']).whereType<String>().toSet();
  return [
    ...rows,
    for (final draft in drafts)
      if (draft.actionKind == 'grocery_item' &&
          draft.householdId == householdId &&
          draft.memberId == userId &&
          !ids.contains(draft.idempotencyKey))
        {
          'id': draft.idempotencyKey,
          'label': draft.payload['label'],
          'quantity': draft.payload['quantity'] ?? 1,
          'unit': draft.payload['unit'],
          'assignee_user_id': draft.payload['assignee_user_id'],
          'status': 'needed',
          'offline_state': draft.state.name,
        },
  ];
}

final homeRecordsProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  final h = await ref.watch(activeHouseholdProvider.future);
  if (h.householdId == null) return const [];
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('household_home_records')
      .select()
      .eq('household_id', h.householdId!)
      .isFilter('archived_at', null)
      .order('due_on');
  return [for (final row in rows as List<dynamic>) _map(row)];
});

final cycleEventsProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  final h = await ref.watch(activeHouseholdProvider.future);
  if (h.householdId == null) return const [];
  final rows = await ref
      .watch(supabaseClientProvider)
      .rpc(
        'read_shared_cycle_calendar',
        params: {'p_household_id': h.householdId},
      );
  return [for (final row in rows as List<dynamic>) _map(row)];
});

final ownCycleEventsProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  final h = await ref.watch(activeHouseholdProvider.future);
  final user = ref.watch(currentUserIdProvider);
  if (h.householdId == null || user == null) return const [];
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('member_cycle_events')
      .select()
      .eq('household_id', h.householdId!)
      .eq('owner_user_id', user)
      .isFilter('archived_at', null)
      .order('starts_on', ascending: false);
  return [for (final row in rows as List<dynamic>) _map(row)];
});

final ownCycleSharesProvider = FutureProvider<Set<String>>((ref) async {
  final h = await ref.watch(activeHouseholdProvider.future);
  final user = ref.watch(currentUserIdProvider);
  if (h.householdId == null || user == null) return const {};
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('member_cycle_calendar_shares')
      .select('recipient_user_id')
      .eq('household_id', h.householdId!)
      .eq('owner_user_id', user);
  return {
    for (final row in rows as List<dynamic>)
      (row as Map)['recipient_user_id'] as String,
  };
});

final ownCyclePrivateEntriesProvider =
    FutureProvider<List<Map<String, Object?>>>((ref) async {
      final h = await ref.watch(activeHouseholdProvider.future);
      final user = ref.watch(currentUserIdProvider);
      if (h.householdId == null || user == null) return const [];
      final rows = await ref
          .watch(supabaseClientProvider)
          .from('member_cycle_private_entries')
          .select()
          .eq('household_id', h.householdId!)
          .eq('owner_user_id', user)
          .isFilter('archived_at', null)
          .order('occurred_on', ascending: false);
      return [for (final row in rows as List<dynamic>) _map(row)];
    });

final ownCycleForecastProvider = Provider<AsyncValue<CycleForecast>>((ref) {
  return ref.watch(ownCycleEventsProvider).whenData((rows) {
    final periods = rows
        .where((row) => row['phase'] == 'period')
        .map(
          (row) => CyclePeriod(
            startsOn: DateTime.parse(row['starts_on'] as String),
            endsOn: row['ends_on'] == null
                ? null
                : DateTime.parse(row['ends_on'] as String),
          ),
        )
        .toList();
    return CycleForecastEngine.estimate(periods);
  });
});

final businessCategoriesProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  final h = await ref.watch(activeHouseholdProvider.future);
  if (h.householdId == null) return const [];
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('categories')
      .select()
      .eq('household_id', h.householdId!)
      .isFilter('archived_at', null)
      .order('name');
  return [for (final row in rows as List<dynamic>) _map(row)];
});

final dailyLifeActionsProvider = Provider((ref) => DailyLifeActions(ref));

class DailyLifeActions {
  DailyLifeActions(this.ref);
  final Ref ref;

  Future<(String, String)> _context() async {
    final h = await ref.read(activeHouseholdProvider.future);
    final u = ref.read(currentUserIdProvider);
    if (h.householdId == null || u == null) {
      throw StateError('Session indisponible.');
    }
    return (h.householdId!, u);
  }

  Future<void> addGrocery(
    String label, {
    String? idempotencyKey,
    String? assignee,
    double quantity = 1,
    String? unit,
  }) async {
    final (h, u) = await _context();
    await ref
        .read(supabaseClientProvider)
        .from('household_grocery_items')
        .insert({
          'id': ?idempotencyKey,
          'household_id': h,
          'label': label.trim(),
          'quantity': quantity,
          'unit': unit?.trim().isEmpty == true ? null : unit?.trim(),
          'assignee_user_id': assignee,
          'created_by': u,
        });
    ref.invalidate(groceryItemsProvider);
  }

  Future<void> setGroceryStatus(String id, String status) async {
    await ref
        .read(supabaseClientProvider)
        .from('household_grocery_items')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
    ref.invalidate(groceryItemsProvider);
  }

  Future<void> addHomeRecord(Map<String, Object?> values) async {
    final (h, u) = await _context();
    await ref
        .read(supabaseClientProvider)
        .from('household_home_records')
        .insert({...values, 'household_id': h, 'created_by': u});
    ref.invalidate(homeRecordsProvider);
  }

  Future<void> addCycleEvent(Map<String, Object?> values) async {
    final (h, u) = await _context();
    await ref.read(supabaseClientProvider).from('member_cycle_events').insert({
      ...values,
      'household_id': h,
      'owner_user_id': u,
    });
    ref.invalidate(ownCycleEventsProvider);
    ref.invalidate(cycleEventsProvider);
    ref.invalidate(ownCycleSharesProvider);
  }

  Future<void> updateCycleEvent(String id, Map<String, Object?> values) async {
    final (_, u) = await _context();
    await ref
        .read(supabaseClientProvider)
        .from('member_cycle_events')
        .update({
          ...values,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('owner_user_id', u);
    ref.invalidate(ownCycleEventsProvider);
    ref.invalidate(cycleEventsProvider);
  }

  Future<void> setCycleShare(String recipient, bool shared) async {
    final (h, u) = await _context();
    final table = ref
        .read(supabaseClientProvider)
        .from('member_cycle_calendar_shares');
    if (shared) {
      await table.upsert({
        'household_id': h,
        'owner_user_id': u,
        'recipient_user_id': recipient,
      });
    } else {
      await table
          .delete()
          .eq('household_id', h)
          .eq('owner_user_id', u)
          .eq('recipient_user_id', recipient);
    }
    ref.invalidate(ownCycleSharesProvider);
    ref.invalidate(cycleEventsProvider);
  }

  Future<void> addCyclePrivateEntry(Map<String, Object?> values) async {
    final (h, u) = await _context();
    await ref
        .read(supabaseClientProvider)
        .from('member_cycle_private_entries')
        .insert({...values, 'household_id': h, 'owner_user_id': u});
    ref.invalidate(ownCyclePrivateEntriesProvider);
  }

  Future<void> archiveCycleEvent(String id) async {
    final (_, u) = await _context();
    await ref
        .read(supabaseClientProvider)
        .from('member_cycle_events')
        .update({'archived_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .eq('owner_user_id', u);
    ref.invalidate(ownCycleEventsProvider);
    ref.invalidate(cycleEventsProvider);
  }

  Future<void> addCategory(String name) async {
    final (h, _) = await _context();
    await ref.read(supabaseClientProvider).from('categories').insert({
      'household_id': h,
      'name': name.trim(),
    });
    ref.invalidate(businessCategoriesProvider);
  }

  Future<void> archiveCategory(String id) async {
    await ref
        .read(supabaseClientProvider)
        .from('categories')
        .update({'archived_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
    ref.invalidate(businessCategoriesProvider);
  }
}

List<CalendarEntry> homeRecordCalendarEntries(
  Iterable<Map<String, Object?>> records,
) => [
  for (final record in records)
    if (record['due_on'] != null)
      CalendarEntry(
        key: 'home-record:${record['id']}',
        title: record['label'] as String,
        date: DateTime.parse(record['due_on'] as String),
        source: CalendarSource.homeAuto,
        assigneeUserId: record['responsible_user_id'] as String?,
        sourceId: record['id'] as String,
        detail: record['kind'] as String,
      ),
];
