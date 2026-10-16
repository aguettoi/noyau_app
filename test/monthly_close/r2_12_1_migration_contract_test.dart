import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261015222456_r2_12_1_structural_recommendation_corrections.sql',
  ).readAsStringSync();

  test('R2.12.1 corrects only the two confirmed structural rules', () {
    expect(
      sql,
      contains("('Voyages','Islamique / Arreda Ibrahim','single_account')"),
    );
    expect(sql, contains("('Vignette','Banque Nora','single_account')"));
    expect(sql, contains("where x.envelope_name in ('Voyages', 'Vignette')"));
    expect(sql, contains('historical_position_proof'));
    expect(sql, contains("'r2_12_1_user_confirmed_correction'"));
  });

  test('R2.12.1 cannot create financial or inventory records', () {
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(
      sql,
      isNot(contains('insert into public.financial_transaction_lines')),
    );
    expect(sql, isNot(contains('insert into public.envelope_movements')));
    expect(
      sql,
      isNot(contains('insert into public.envelope_account_position_entries')),
    );
    expect(
      sql,
      isNot(contains('insert into public.envelope_account_position_batches')),
    );
  });
}
