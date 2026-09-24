import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260924185505_canonical_reconciliation_mvp.sql',
  ).readAsStringSync();

  test(
    'fige le rapprochement côté serveur avec la convention réel moins GL',
    () {
      expect(migration, contains('theoretical_balance_snapshot'));
      expect(
        migration,
        contains(
          'difference_snapshot = actual_balance - theoretical_balance_snapshot',
        ),
      );
      expect(
        migration,
        contains('select theoretical_balance into v_theoretical'),
      );
      expect(migration, contains('p_actual_balance - v_theoretical'));
    },
  );

  test('préserve les constats legacy et rend les résolutions append-only', () {
    expect(
      migration,
      contains("when o.snapshot_version is null then 'legacy_unfrozen'"),
    );
    expect(migration, contains('account_reconciliation_resolutions'));
    expect(migration, contains('enable row level security'));
    expect(
      migration,
      isNot(contains('create policy "members update reconciliation')),
    );
  });

  test(
    'borne les liens financiers et interdit les ajustements inexpliqués',
    () {
      expect(
        migration,
        contains('Financial event exceeds reconciliation remainder'),
      );
      expect(
        migration,
        contains('Financial event has no impact on this account'),
      );
      expect(migration, isNot(contains('reconciliation_adjustment')));
    },
  );
}
