import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261010224500_r2_2_envelope_account_positions.sql',
  ).readAsStringSync();
  final projectionSql = File(
    'supabase/migrations/20261010231000_r2_2_canonical_event_projection.sql',
  ).readAsStringSync();
  test('R2.2 is append-only, scoped and uses canonical transfers', () {
    expect(sql, contains('envelope_account_position_entries'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('create_account_transfer_event'));
    expect(sql, contains('Proposal is stale'));
    expect(sql, isNot(contains('on conflict')));
    expect(sql, isNot(contains('update public.accounts')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });
  test('legacy history is not backfilled or inferred', () {
    expect(sql, contains('explicit_snapshot'));
    expect(sql, contains('Snapshot does not reconcile account balances'));
    expect(sql, contains('Snapshot does not reconcile envelope balances'));
    expect(sql, isNot(contains('opening_balance')));
  });
  test('future unambiguous canonical movements maintain the projection', () {
    expect(
      projectionSql,
      contains('after insert on public.envelope_movements'),
    );
    expect(projectionSql, contains('not a.is_system'));
    expect(projectionSql, contains('v_account_count<>1 then return new'));
    expect(projectionSql, contains('source_envelope_movement_id'));
  });
}
