import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C4C migration is additive, append-only and non-financial', () {
    final sql = File(
      'supabase/migrations/20260930202804_historical_analytic_storage.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('create table public.historical_analytic_lines'));
    expect(sql, contains('create table public.historical_analytic_decisions'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('security_invoker = true'));
    expect(sql, contains('historical analytical records are append-only'));
    expect(sql, contains('source_content_hash'));
    expect(sql, contains('historical source identity conflict'));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
    expect(sql, isNot(contains('update public.accounts')));
    expect(sql, isNot(contains('update public.envelopes')));
  });
}
