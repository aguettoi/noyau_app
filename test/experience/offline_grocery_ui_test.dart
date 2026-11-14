import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/fp_adaptive_navigation.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/experience/application/offline_connectivity.dart';
import 'package:noyau_app/features/experience/application/experience_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/organization/application/daily_life_provider.dart';
import 'package:noyau_app/features/organization/presentation/daily_life_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('local and Universal Add use the same grocery entry workflow', () {
    final dailyLife = File(
      'lib/features/organization/presentation/daily_life_page.dart',
    ).readAsStringSync();
    final shell = File('lib/app/noyau_app.dart').readAsStringSync();
    expect(dailyLife, contains('showGroceryEntryDialog(context, ref)'));
    expect(RegExp(r'_openGroceryEntry').allMatches(shell).length, 3);
    expect(
      RegExp(
        r"FpAddAction\('grocery'.*_openGroceryEntry\)",
      ).allMatches(shell).length,
      2,
    );
    expect(shell, contains('showGroceryEntryDialog(context, ref)'));
  });

  testWidgets('local add remains hit-testable inside the mobile shell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncConnectionStateProvider.overrideWith(
            (ref) => SyncConnectionState.offline,
          ),
          groceryItemsProvider.overrideWith((ref) async => const []),
          remoteHouseholdMembersProvider.overrideWith(
            (ref) async => throw StateError('offline'),
          ),
          homeRecordsProvider.overrideWith((ref) async => const []),
          ownCycleEventsProvider.overrideWith((ref) async => const []),
          ownCycleSharesProvider.overrideWith((ref) async => const {}),
          businessCategoriesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          home: FpAdaptiveNavigation(
            selected: FpUniverse.household,
            onSelected: (_) {},
            onAdd: () {},
            body: const DailyLifePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final localAdd = find.byKey(const Key('grocery-add-button'));
    expect(localAdd, findsOneWidget);
    expect(localAdd.hitTestable(), findsOneWidget);
    await tester.tap(localAdd);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grocery-entry-dialog')), findsOneWidget);
  });

  testWidgets(
    'cached groceries expose stale and pending states without actions',
    (tester) async {
      final capturedAt = DateTime.utc(2026, 11, 13, 10);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groceryItemsProvider.overrideWith(
              (ref) async => const [
                {
                  'id': 'offline-item',
                  'label': 'Pain',
                  'quantity': 2,
                  'unit': '',
                  'status': 'needed',
                  'offline_state': 'pending',
                },
              ],
            ),
            homeRecordsProvider.overrideWith((ref) async => const []),
            ownCycleEventsProvider.overrideWith((ref) async => const []),
            ownCycleSharesProvider.overrideWith((ref) async => const {}),
            businessCategoriesProvider.overrideWith((ref) async => const []),
            remoteHouseholdMembersProvider.overrideWith(
              (ref) async => const [],
            ),
            offlineSnapshotStatusProvider.overrideWith(
              (ref) => {
                'household_groceries': OfflineSnapshotStatus(
                  capturedAt: capturedAt,
                  stale: true,
                ),
              },
            ),
          ],
          child: const MaterialApp(home: DailyLifePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.text('Pain'), findsOneWidget);
      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const Key('grocery-offline-item')),
      );
      final expectedPending = AppWords.of(
        tester.element(find.byKey(const Key('grocery-offline-item'))),
      ).text('offline.pending_item');
      expect(checkbox.onChanged, isNull);
      expect((checkbox.subtitle! as Text).data, contains(expectedPending));
      final expense = tester.widget<TextButton>(
        find.byKey(const Key('grocery-expense-offline-item')),
      );
      expect(expense.onPressed, isNull);
    },
  );

  testWidgets(
    'cached groceries open the canonical form offline and queue a pending item',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = ExperienceStore();
      await store.saveReadSnapshot(
        kind: 'household_groceries',
        householdId: 'household-a',
        userId: 'user-a',
        rows: const [
          {
            'id': 'known-item',
            'label': 'Pain',
            'quantity': 1,
            'unit': null,
            'status': 'needed',
          },
        ],
      );
      var memberReads = 0;
      await tester.pumpWidget(
        ProviderScope(
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
            syncConnectionStateProvider.overrideWith(
              (ref) => SyncConnectionState.offline,
            ),
            groceryItemsProvider.overrideWith((ref) async {
              final drafts = await store.loadDrafts();
              return [
                const {
                  'id': 'known-item',
                  'label': 'Pain',
                  'quantity': 1,
                  'unit': null,
                  'status': 'needed',
                },
                for (final draft in drafts)
                  if (draft.actionKind == 'grocery_item')
                    {
                      'id': draft.idempotencyKey,
                      'label': draft.payload['label'],
                      'quantity': draft.payload['quantity'],
                      'unit': draft.payload['unit'],
                      'status': 'needed',
                      'offline_state': draft.state.name,
                    },
              ];
            }),
            remoteHouseholdMembersProvider.overrideWith((ref) async {
              memberReads++;
              throw StateError('Remote members must not block offline entry.');
            }),
            homeRecordsProvider.overrideWith((ref) async => const []),
            ownCycleEventsProvider.overrideWith((ref) async => const []),
            ownCycleSharesProvider.overrideWith((ref) async => const {}),
            businessCategoriesProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: DailyLifePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pain'), findsOneWidget);
      await tester.tap(find.byKey(const Key('grocery-add-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('grocery-entry-dialog')), findsOneWidget);
      expect(memberReads, 0);
      await tester.enterText(
        find.byKey(const Key('grocery-item-field')),
        'OFFLINE-P1B-1908',
      );
      await tester.tap(find.byKey(const Key('grocery-submit-button')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final drafts = await store.loadDrafts();
      expect(drafts, hasLength(1));
      expect(drafts.single.payload['label'], 'OFFLINE-P1B-1908');
      expect(drafts.single.actionKind, 'grocery_item');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DailyLifePage)),
      );
      final rows = await container.read(groceryItemsProvider.future);
      expect(rows.any((row) => row['label'] == 'OFFLINE-P1B-1908'), isTrue);
      await tester.pump();
      expect(find.text('OFFLINE-P1B-1908'), findsOneWidget);
      final pendingLabel = AppWords.of(
        tester.element(find.text('OFFLINE-P1B-1908')),
      ).text('offline.pending_item');
      expect(find.textContaining(pendingLabel), findsOneWidget);
    },
  );
}
