import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F2A migration defines isolated payment methods and recommendations', () {
    final sql = File(
      'supabase/migrations/20261005100000_f2a_payment_methods_and_recommendations.sql',
    ).readAsStringSync();
    expect(sql, contains('create table if not exists public.payment_methods'));
    expect(
      sql,
      contains('create or replace function public.create_payment_method'),
    );
    expect(
      sql,
      contains('create or replace function public.update_payment_method'),
    );
    expect(
      sql,
      contains('create or replace function public.set_envelope_recommendation'),
    );
    expect(sql, contains('recommended_account_id'));
    expect(sql, contains('recommended_payment_method_id'));
    expect(
      sql,
      contains('grant execute on function public.create_payment_method'),
    );
    expect(
      sql,
      contains('revoke all on function public.create_payment_method'),
    );
  });

  test(
    'F2A hardening keeps writes RPC-only and validates household ownership',
    () {
      final sql = File(
        'supabase/migrations/20261005113000_f2a_payment_methods_hardening.sql',
      ).readAsStringSync();
      expect(sql, contains('from public, anon'));
      expect(sql, contains('grant select on table public.payment_methods'));
      expect(sql, isNot(contains('for insert')));
      expect(sql, isNot(contains('for update')));
      expect(sql, contains('Account household mismatch'));
      expect(sql, contains('Holder household mismatch'));
      expect(sql, contains('Payment method access denied'));
      expect(sql, isNot(contains('financial_events')));
      expect(sql, isNot(contains('postings')));
      expect(sql, isNot(contains('envelope_movements')));
    },
  );
}
