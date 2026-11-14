import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/experience/application/experience_provider.dart';
import 'package:noyau_app/features/experience/application/offline_connectivity.dart';
import 'package:noyau_app/features/experience/domain/offline_draft.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/organization/application/daily_life_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'scoped snapshots reject another user or household and purge on logout',
    () async {
      final store = ExperienceStore();
      await store.saveReadSnapshot(
        kind: 'test',
        householdId: 'household-a',
        userId: 'user-a',
        rows: const [
          {'id': 'private-row'},
        ],
      );

      expect(
        await store.loadReadSnapshot(
          kind: 'test',
          householdId: 'household-b',
          userId: 'user-a',
        ),
        isNull,
      );
      await store.saveReadSnapshot(
        kind: 'test',
        householdId: 'household-a',
        userId: 'user-a',
        rows: const [
          {'id': 'private-row'},
        ],
      );
      await store.purgePrivateState();
      expect(
        await store.loadReadSnapshot(
          kind: 'test',
          householdId: 'household-a',
          userId: 'user-a',
        ),
        isNull,
      );
    },
  );

  test(
    'groceries fall back to cached rows and expose pending drafts',
    () async {
      final store = ExperienceStore();
      await store.saveReadSnapshot(
        kind: 'household_groceries',
        householdId: 'household-a',
        userId: 'user-a',
        capturedAt: DateTime.utc(2026, 11, 12, 18),
        rows: const [
          {'id': 'cached', 'label': 'Lait', 'quantity': 1, 'status': 'needed'},
        ],
      );
      await store.enqueueDraft(
        OfflineDraft(
          idempotencyKey: '00000000-0000-4000-8000-000000000099',
          actionKind: 'grocery_item',
          updatedAt: DateTime.utc(2026, 11, 12, 19),
          state: OfflineDraftState.pending,
          householdId: 'household-a',
          memberId: 'user-a',
          payload: const {'label': 'Pain', 'quantity': 2},
        ),
      );
      final client = _offlineClient();
      addTearDown(client.dispose);
      final container = _container(client, store);
      addTearDown(container.dispose);

      final rows = await container.read(groceryItemsProvider.future);

      expect(rows.map((row) => row['label']), containsAll(['Lait', 'Pain']));
      expect(
        rows.singleWhere((row) => row['label'] == 'Pain')['offline_state'],
        OfflineDraftState.pending.name,
      );
      expect(
        container.read(syncConnectionStateProvider),
        SyncConnectionState.offline,
      );
      expect(
        container
            .read(offlineSnapshotStatusProvider)['household_groceries']
            ?.stale,
        isTrue,
      );
    },
  );

  test(
    'envelopes retain their last scoped snapshot during a network loss',
    () async {
      final store = ExperienceStore();
      await store.saveReadSnapshot(
        kind: 'envelopes',
        householdId: 'household-a',
        userId: 'user-a',
        capturedAt: DateTime.utc(2026, 11, 12, 18),
        rows: const [
          {
            'id': 'envelope-a',
            'name': 'Courses',
            'inflows_minor': 10000,
            'outflows_minor': 2500,
            'balance_minor': 7500,
            'is_system': false,
            'is_archived': false,
            'recommendation_definition': <String, Object?>{},
            'economic_rule': 'unconfigured',
          },
        ],
      );
      final client = _offlineClient();
      addTearDown(client.dispose);
      final container = _container(client, store);
      addTearDown(container.dispose);

      final rows = await container.read(remoteEnvelopeHistoryProvider.future);

      expect(rows.single.name, 'Courses');
      expect(rows.single.balance.minorUnits, 7500);
      expect(
        container.read(offlineSnapshotStatusProvider)['envelopes']?.stale,
        isTrue,
      );
    },
  );

  test('cache absent keeps a network failure explicit and safe', () async {
    final store = ExperienceStore();
    final client = _offlineClient();
    addTearDown(client.dispose);
    final container = _container(client, store);
    addTearDown(container.dispose);

    await expectLater(
      container.read(groceryItemsProvider.future),
      throwsA(isA<http.ClientException>()),
    );
    expect(
      container.read(syncConnectionStateProvider),
      SyncConnectionState.offline,
    );
    expect(
      container.read(offlineSnapshotStatusProvider)['household_groceries'],
      isNull,
    );
  });

  test(
    'remote rows populate a fresh snapshot reused after a restart',
    () async {
      final store = ExperienceStore();
      final onlineClient = _onlineGroceriesClient();
      addTearDown(onlineClient.dispose);
      final online = _container(onlineClient, store);
      addTearDown(online.dispose);

      final fresh = await online.read(groceryItemsProvider.future);
      expect(fresh.single['label'], 'Tomates');
      expect(
        online
            .read(offlineSnapshotStatusProvider)['household_groceries']
            ?.stale,
        isFalse,
      );

      final offlineClient = _offlineClient();
      addTearDown(offlineClient.dispose);
      final restarted = _container(offlineClient, store);
      addTearDown(restarted.dispose);

      final cached = await restarted.read(groceryItemsProvider.future);
      expect(cached.single['label'], 'Tomates');
      expect(
        restarted
            .read(offlineSnapshotStatusProvider)['household_groceries']
            ?.stale,
        isTrue,
      );
    },
  );

  test(
    'automatic probe confirms reconnection without a manual retry',
    () async {
      var probes = 0;
      final container = ProviderContainer(
        overrides: [
          offlineConnectivityProbeProvider.overrideWithValue(() async {
            probes++;
          }),
          offlineReconnectIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(offlineReconnectMonitorProvider);
      container.read(syncConnectionStateProvider.notifier).state =
          SyncConnectionState.offline;

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(probes, greaterThanOrEqualTo(1));
      expect(
        container.read(syncConnectionStateProvider),
        SyncConnectionState.synchronized,
      );
    },
  );

  test(
    'initial connecting state is actively probed and becomes online',
    () async {
      var probes = 0;
      final container = ProviderContainer(
        overrides: [
          offlineConnectivityProbeProvider.overrideWithValue(() async {
            probes++;
          }),
          offlineReconnectIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 50),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(offlineReconnectMonitorProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(probes, 1);
      expect(
        container.read(syncConnectionStateProvider),
        SyncConnectionState.synchronized,
      );
    },
  );

  test('a hanging probe times out without concurrent probes', () async {
    var probes = 0;
    final never = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        offlineConnectivityProbeProvider.overrideWithValue(() {
          probes++;
          return never.future;
        }),
        offlineProbeTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
        offlineReconnectIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 2),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(offlineReconnectMonitorProvider);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(probes, 1);

    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(
      container.read(syncConnectionStateProvider),
      SyncConnectionState.offline,
    );
    expect(probes, lessThanOrEqualTo(2));
  });
}

ProviderContainer _container(SupabaseClient client, ExperienceStore store) =>
    ProviderContainer(
      overrides: [
        experienceStoreProvider.overrideWithValue(store),
        currentUserIdProvider.overrideWith((ref) => 'user-a'),
        activeHouseholdProvider.overrideWith(
          (ref) async => const ActiveHouseholdState(
            status: ActiveHouseholdStatus.singleHousehold,
            householdId: 'household-a',
            householdIds: ['household-a'],
          ),
        ),
        supabaseClientProvider.overrideWithValue(client),
      ],
    );

SupabaseClient _offlineClient() => SupabaseClient(
  'https://example.supabase.co',
  'test-key',
  httpClient: MockClient(
    (request) async =>
        throw http.ClientException('Failed to fetch', request.url),
  ),
);

SupabaseClient _onlineGroceriesClient() => SupabaseClient(
  'https://example.supabase.co',
  'test-key',
  httpClient: MockClient((request) async {
    expect(request.url.path, contains('household_grocery_items'));
    return http.Response(
      '[{"id":"server-row","label":"Tomates","quantity":3,"status":"needed"}]',
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }),
);
