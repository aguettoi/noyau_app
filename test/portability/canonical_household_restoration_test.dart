import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/portability/domain/canonical_household_archive.dart';

void main() {
  const codec = HouseholdArchiveCodec();
  const restorer = IsolatedHouseholdRestorer();

  test('restores a balanced household and remaps every identity', () {
    final bytes = codec.encode(_archive(memberCount: 3));
    final target = IsolatedHouseholdStore();
    final result = restorer.restore(
      archiveBytes: bytes,
      target: target,
      targetHouseholdId: 'target-household',
      memberIdentityMap: const {
        'member-1': 'target-member-1',
        'member-2': 'target-member-2',
        'member-3': 'target-member-3',
      },
    );

    expect(result.alreadyRestored, isFalse);
    expect(result.rowsRestored, greaterThan(10));
    expect(target.tables['households']!.single['id'], 'target-household');
    expect(
      target.tables['household_members']!.map((row) => row['user_id']),
      containsAll(['target-member-1', 'target-member-2', 'target-member-3']),
    );
    expect(
      target.tables['account_privacy_settings']!.single['visibility'],
      'private',
    );
    expect(
      target.tables['account_balance_observations']!.single['denominations'],
      {'200': 2, '100': 1},
    );
  });

  test('supports 1, 2 and N members without a couple assumption', () {
    for (final count in [1, 2, 5]) {
      final target = IsolatedHouseholdStore();
      restorer.restore(
        archiveBytes: codec.encode(_archive(memberCount: count)),
        target: target,
        targetHouseholdId: 'target-$count',
        memberIdentityMap: {
          for (var index = 1; index <= count; index++)
            'member-$index': 'identity-$count-$index',
        },
      );
      expect(target.tables['household_members'], hasLength(count));
    }
  });

  test('second restoration is idempotently detected', () {
    final bytes = codec.encode(_archive());
    final target = IsolatedHouseholdStore();
    final arguments = (
      archiveBytes: bytes,
      target: target,
      targetHouseholdId: 'target',
      memberIdentityMap: const {'member-1': 'target-member'},
    );
    restorer.restore(
      archiveBytes: arguments.archiveBytes,
      target: arguments.target,
      targetHouseholdId: arguments.targetHouseholdId,
      memberIdentityMap: arguments.memberIdentityMap,
    );
    final second = restorer.restore(
      archiveBytes: arguments.archiveBytes,
      target: arguments.target,
      targetHouseholdId: arguments.targetHouseholdId,
      memberIdentityMap: arguments.memberIdentityMap,
    );
    expect(second.alreadyRestored, isTrue);
    expect(second.rowsRestored, 0);
    expect(target.tables['financial_events'], hasLength(1));
  });

  test('rejects corrupt archives and incompatible versions', () {
    final bytes = codec.encode(_archive());
    final zip = ZipDecoder().decodeBytes(bytes);
    final corrupt = _replaceFile(zip, 'data/accounts.json', utf8.encode('[]'));
    expect(
      () => codec.decode(corrupt),
      throwsA(isA<HouseholdArchiveException>()),
    );

    final incompatible = _replaceManifest(bytes, (manifest) {
      manifest['version'] = 999;
    });
    expect(
      () => codec.decode(incompatible),
      throwsA(isA<HouseholdArchiveException>()),
    );
  });

  test('rejects user exports as non-restorable', () {
    final archive = Archive();
    final manifest = utf8.encode(
      jsonEncode({
        'format': 'financiel-pilote-user-export',
        'version': 1,
        'restore_eligible': false,
      }),
    );
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    expect(
      () => codec.decode(ZipEncoder().encode(archive)!),
      throwsA(isA<HouseholdArchiveException>()),
    );
  });

  test('orphan or unbalanced ledger fails atomically', () {
    for (final broken in [
      _archive(orphanAccount: true),
      _archive(unbalancedLedger: true),
    ]) {
      final target = IsolatedHouseholdStore();
      expect(
        () => restorer.restore(
          archiveBytes: codec.encode(broken),
          target: target,
          targetHouseholdId: 'target',
          memberIdentityMap: const {'member-1': 'target-member'},
        ),
        throwsA(isA<HouseholdArchiveException>()),
      );
      expect(target.isEmpty, isTrue);
      expect(target.restoredArchiveDigests, isEmpty);
    }
  });

  test('rejects cross-household rows before restoration', () {
    final archive = _archive();
    archive.datasets['accounts']!.single['household_id'] = 'other-household';
    expect(
      () => codec.encode(archive),
      throwsA(isA<HouseholdArchiveException>()),
    );
  });

  test('restores a dataset materially larger than C3 in bounded time', () {
    final archive = _archive();
    for (var index = 2; index <= 300; index++) {
      archive.datasets['financial_events']!.add({
        'id': 'event-$index',
        'household_id': 'source-household',
        'event_type': 'cash_expense',
        'created_by': 'member-1',
      });
      archive.datasets['financial_transactions']!.add({
        'id': 'transaction-$index',
        'household_id': 'source-household',
        'event_id': 'event-$index',
        'source_account_id': 'account-1',
        'created_by': 'member-1',
      });
      archive.datasets['financial_transaction_lines']!.addAll([
        {
          'id': 'line-$index-a',
          'household_id': 'source-household',
          'transaction_id': 'transaction-$index',
          'account_id': 'account-1',
          'debit': 1,
          'credit': 0,
        },
        {
          'id': 'line-$index-b',
          'household_id': 'source-household',
          'transaction_id': 'transaction-$index',
          'account_id': 'account-1',
          'debit': 0,
          'credit': 1,
        },
      ]);
    }
    final watch = Stopwatch()..start();
    final result = restorer.restore(
      archiveBytes: codec.encode(archive),
      target: IsolatedHouseholdStore(),
      targetHouseholdId: 'performance-target',
      memberIdentityMap: const {'member-1': 'performance-member'},
    );
    watch.stop();
    expect(result.rowsRestored, greaterThan(900));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

CanonicalHouseholdArchive _archive({
  int memberCount = 1,
  bool orphanAccount = false,
  bool unbalancedLedger = false,
}) {
  const household = 'source-household';
  Map<String, Object?> row(Map<String, Object?> value) => {
    'household_id': household,
    ...value,
  };
  return CanonicalHouseholdArchive(
    sourceHouseholdId: household,
    createdAt: DateTime.utc(2026, 10, 25, 20),
    datasets: {
      'households': [
        {'id': household, 'name': 'Foyer source'},
      ],
      'household_members': [
        for (var index = 1; index <= memberCount; index++)
          row({
            'user_id': 'member-$index',
            'role': index == 1 ? 'owner' : 'member',
          }),
      ],
      'accounts': [
        row({'id': 'account-1', 'name': 'Compte privé'}),
      ],
      'account_holders': [
        row({'account_id': 'account-1', 'user_id': 'member-1'}),
      ],
      'account_privacy_settings': [
        row({
          'account_id': 'account-1',
          'visibility': 'private',
          'changed_by': 'member-1',
        }),
      ],
      'envelopes': [
        row({
          'id': 'envelope-1',
          'name': 'Maison',
          'recommended_account_id': 'account-1',
        }),
      ],
      'budget_goals': const [],
      'financial_events': [
        row({
          'id': 'event-1',
          'event_type': 'cash_expense',
          'created_by': 'member-1',
        }),
      ],
      'financial_transactions': [
        row({
          'id': 'transaction-1',
          'event_id': 'event-1',
          'source_account_id': 'account-1',
          'created_by': 'member-1',
        }),
      ],
      'financial_transaction_lines': [
        row({
          'id': 'line-1',
          'transaction_id': 'transaction-1',
          'account_id': orphanAccount ? 'missing-account' : 'account-1',
          'debit': 100,
          'credit': 0,
        }),
        row({
          'id': 'line-2',
          'transaction_id': 'transaction-1',
          'account_id': 'account-1',
          'debit': 0,
          'credit': unbalancedLedger ? 90 : 100,
        }),
      ],
      'envelope_movements': [
        row({
          'id': 'movement-1',
          'envelope_id': 'envelope-1',
          'financial_transaction_id': 'transaction-1',
          'event_id': 'event-1',
          'amount': 100,
          'direction': 'outflow',
          'created_by': 'member-1',
        }),
      ],
      'obligations': [
        row({
          'id': 'obligation-1',
          'origin_event_id': 'event-1',
          'origin_transaction_id': 'transaction-1',
          'origin_envelope_id': 'envelope-1',
          'initial_amount': 500,
          'created_by': 'member-1',
        }),
      ],
      'obligation_settlements': const [],
      'wealth_assets': [
        row({
          'id': 'asset-1',
          'label': 'Actif',
          'created_by': 'member-1',
          'updated_by': 'member-1',
        }),
      ],
      'wealth_asset_valuations': [
        row({
          'id': 'valuation-1',
          'asset_id': 'asset-1',
          'estimated_value': 1000,
          'created_by': 'member-1',
        }),
      ],
      'wealth_asset_owners': [
        row({'asset_id': 'asset-1', 'user_id': 'member-1'}),
      ],
      'investment_products': const [],
      'investment_valuations': const [],
      'investment_operations': const [],
      'financing_profiles': const [],
      'account_balance_observations': [
        row({
          'id': 'observation-1',
          'account_id': 'account-1',
          'observed_balance': 500,
          'denominations': {'200': 2, '100': 1},
          'created_by': 'member-1',
        }),
      ],
    },
  );
}

List<int> _replaceManifest(
  List<int> bytes,
  void Function(Map<String, Object?> manifest) change,
) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.findFile('manifest.json')!;
  final manifest = Map<String, Object?>.from(
    jsonDecode(utf8.decode(file.content as List<int>)) as Map,
  );
  change(manifest);
  return _replaceFile(
    archive,
    'manifest.json',
    utf8.encode(jsonEncode(manifest)),
  );
}

List<int> _replaceFile(Archive source, String name, List<int> replacement) {
  final output = Archive();
  for (final file in source.files) {
    final content = file.name == name
        ? replacement
        : List<int>.from(file.content as List<int>);
    output.addFile(ArchiveFile(file.name, content.length, content));
  }
  return ZipEncoder().encode(output)!;
}
