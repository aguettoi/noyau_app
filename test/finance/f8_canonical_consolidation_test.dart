import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261009072429_f8_canonical_security_hardening.sql',
  ).readAsStringSync();
  final remoteGateway = File(
    'lib/features/finance/application/providers/remote_transactions_provider.dart',
  ).readAsStringSync();
  final importsPage = File(
    'lib/features/finance/presentation/imports_page.dart',
  ).readAsStringSync();

  test('legacy financial mutation RPCs are no longer client APIs', () {
    for (final function in const [
      'create_financial_transaction',
      'create_ledger_transaction',
      'create_financial_transaction_with_envelopes',
      'create_envelope_transfer',
      'execute_accounts_import',
      'import_household_envelopes',
    ]) {
      expect(migration, contains(function));
    }
    expect(
      remoteGateway,
      isNot(contains('create_financial_transaction_with_envelopes')),
    );
  });

  test('legacy CSV materialisation is visibly disabled', () {
    expect(importsPage, contains('_legacyCsvMaterializationEnabled = false'));
    expect(importsPage, contains('Matérialisation CSV legacy désactivée'));
  });

  test('opening balance metadata is immutable and ledgers stay protected', () {
    expect(migration, contains('accounts_opening_balance_legacy_guard'));
    expect(
      migration,
      contains('Stored account opening balances are immutable'),
    );
    expect(migration, contains('public.financial_events'));
    expect(migration, contains('public.envelope_movements'));
    expect(migration, contains('public.obligations'));
  });

  test('historical migrations are not edited by F8', () {
    expect(migration, contains('revoke execute'));
    expect(migration, isNot(contains('drop function')));
    expect(migration, isNot(contains('delete from')));
    expect(migration, isNot(contains('update public.financial')));
  });
}
