import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'marques personnelles sont RLS et ne créent aucune écriture financière',
    () {
      final sql = File(
        'supabase/migrations/20261024121000_l2_5_timeline_significance_marks.sql',
      ).readAsStringSync().toLowerCase();
      expect(sql, contains('enable row level security'));
      expect(sql, contains('user_id=(select auth.uid())'));
      expect(sql, contains('revoke all'));
      expect(sql, contains('source_kind'));
      for (final forbidden in [
        'insert into public.financial_events',
        'insert into public.gl_transactions',
        'insert into public.gl_postings',
        'insert into public.envelope_movements',
      ]) {
        expect(sql, isNot(contains(forbidden)));
      }
    },
  );
}
