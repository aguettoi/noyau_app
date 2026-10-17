import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261017141823_r2_14_deferred_initial_positions.sql',
  ).readAsStringSync();

  test(
    'R2.14 persists an unknown envelope without a fake account position',
    () {
      expect(sql, contains('envelope_account_initial_position_unknowns'));
      expect(sql, contains('public.is_household_member(p_household_id)'));
      expect(sql, contains('household_id=p_household_id'));
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(sql, isNot(contains('account_id')));
      expect(sql, isNot(contains('financial_events')));
      expect(sql, isNot(contains('financial_transactions')));
      expect(sql, isNot(contains('envelope_movements')));
    },
  );

  test('R2.14 connects both shared draft tables to Realtime', () {
    final realtime = File(
      'supabase/migrations/20261017142626_r2_14_draft_realtime.sql',
    ).readAsStringSync();
    expect(realtime, contains('supabase_realtime'));
    expect(realtime, contains('envelope_account_initial_position_drafts'));
    expect(realtime, contains('envelope_account_initial_position_unknowns'));
  });
}
