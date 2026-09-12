import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202608100004_budget_allocation_run_snapshot.sql',
  ).readAsStringSync();
  final precheck = File(
    'docs/SANDBOX_BUDGET_ALLOCATION_RUN_SNAPSHOT_PRE.sql',
  ).readAsStringSync().toLowerCase();
  final postcheck = File(
    'docs/SANDBOX_BUDGET_ALLOCATION_RUN_SNAPSHOT_POST.sql',
  ).readAsStringSync().toLowerCase();

  test(
    'snapshot persistence is one atomic server operation without financial writes',
    () {
      expect(
        migration,
        contains(
          'create or replace function public.save_budget_allocation_run',
        ),
      );
      expect(migration, contains('security definer'));
      expect(migration, contains('insert into public.budget_allocation_runs'));
      expect(
        migration,
        contains('insert into public.budget_allocation_run_lines'),
      );
      expect(migration, isNot(contains('allocate_budget_event')));
      expect(migration, isNot(contains('envelope_movements')));
      expect(migration, isNot(contains('financial_transactions')));
    },
  );

  test('snapshot RPC accepts a JSON array and checks its planned total', () {
    expect(migration, contains("jsonb_typeof(p_lines) <> 'array'"));
    expect(migration, contains('Budget run total does not match its lines'));
    expect(migration, contains('jsonb_array_elements(p_lines)'));
  });

  test(
    'run snapshots are immutable while approval and application remain allowed',
    () {
      expect(migration, contains('protect_budget_allocation_run_snapshot'));
      expect(
        migration,
        contains('protect_budget_allocation_run_line_snapshot'),
      );
      expect(
        migration,
        contains('Budget allocation run snapshots are immutable'),
      );
      expect(
        migration,
        contains("old.status = 'simulated' and new.status = 'approved'"),
      );
      expect(
        migration,
        contains("old.status = 'approved' and new.status = 'applied'"),
      );
      expect(
        migration,
        contains(
          'revoke insert, update, delete on public.budget_allocation_runs',
        ),
      );
    },
  );

  test('pre and post diagnostics remain read only one-row summaries', () {
    for (final script in [precheck, postcheck]) {
      expect(script, contains('select'));
      expect(script, isNot(contains('insert ')));
      expect(script, isNot(contains('update ')));
      expect(script, isNot(contains('delete ')));
      expect(script, isNot(contains('alter ')));
      expect(script, isNot(contains('create ')));
      expect(script, isNot(contains('drop ')));
    }
    expect(precheck, contains('pre_migration_ready'));
    expect(postcheck, contains('post_migration_ready'));
  });
}
