import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V1 has no locally seeded account source', () {
    expect(
      File(
        'lib/features/finance/data/local_accounts_repository.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/finance/application/accounts_controller.dart',
      ).existsSync(),
      isFalse,
    );

    final files = Directory('lib').listSync(recursive: true).whereType<File>();
    for (final file in files.where((file) => file.path.endsWith('.dart'))) {
      final contents = file.readAsStringSync();
      expect(
        contents,
        isNot(contains('financial_accounts_v1')),
        reason: file.path,
      );
      expect(
        contents,
        isNot(contains('LocalAccountsRepository')),
        reason: file.path,
      );
    }
  });

  test('V1 uses the remote account provider', () {
    final page = File(
      'lib/features/finance/presentation/accounts_page.dart',
    ).readAsStringSync();
    expect(page, contains('remoteAccountsProvider'));
    expect(page, contains('supabaseAccountsRepositoryProvider'));
  });
}
