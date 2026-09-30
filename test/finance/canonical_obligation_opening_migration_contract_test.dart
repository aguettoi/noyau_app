import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260930063315_canonical_obligation_openings.sql',
    ).readAsStringSync();
  });

  test('opening is audit-only, authenticated and idempotent', () {
    expect(migration, contains("'obligation_opening'"));
    expect(migration, contains('create_obligation_opening_event'));
    expect(migration, contains("'debt'"));
    expect(migration, contains('origin_transaction_id'));
    expect(migration, contains('null,\n    p_amount'));
    expect(migration, contains('for update'));
    expect(migration, contains('idempotency conflict'));
    expect(migration, contains('auth.uid()'));
    expect(migration, contains('to authenticated'));
  });

  test('opening does not manufacture GL, account or envelope movements', () {
    final function = migration.substring(
      migration.indexOf(
        'create or replace function public.create_obligation_opening_event',
      ),
      migration.indexOf(
        'revoke all on function public.create_obligation_opening_event',
      ),
    );
    expect(function, isNot(contains('financial_transactions')));
    expect(function, isNot(contains('postings')));
    expect(function, isNot(contains('envelope_movements')));
    expect(function, isNot(contains('accounts')));
  });
}
