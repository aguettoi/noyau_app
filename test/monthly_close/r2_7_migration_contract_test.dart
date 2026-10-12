import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20261011222215_r2_7_envelope_structural_configuration.sql',
    ).readAsStringSync();
  });

  test(
    'matérialise les 26 règles sans confondre recommandation et position',
    () {
      expect(sql, contains("('Epargne','Islamique / Arreda Ibrahim'"));
      expect(sql, contains("('Habits',null,'scenario_split'"));
      expect(
        sql,
        contains(
          "('Reste epargne (primes Ibrahim et Nora)',null,'member_beneficiary'",
        ),
      );
      expect(sql, contains("('À répartir',null,'system'"));
      expect(sql, contains("('Assurance','Banque Nora'"));
      expect(sql, contains('opening_split_status'));
    },
  );

  test('limite le sweep aux trois sources certifiées', () {
    expect(
      'month_end_sweep_destination'.allMatches(sql).length,
      greaterThanOrEqualTo(6),
    );
    for (final source in ['Navette', 'Nourriture', 'Sorties WE']) {
      expect(
        RegExp("\\('$source'.*month_end_sweep_destination").hasMatch(sql),
        isTrue,
      );
    }
    expect(
      sql,
      contains(
        "recommendation_definition->>'month_end_sweep_destination'='Epargne'",
      ),
    );
    expect(sql, contains('<>3'));
  });

  test('sweep idempotent, mensuel et sans transfert bancaire fictif', () {
    expect(
      sql,
      contains('unique(household_id,month_start,source_envelope_id)'),
    );
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('create_envelope_transfer_event'));
    expect(sql, isNot(contains('create_account_transfer_event(')));
    expect(sql, contains("'creates_bank_transfer',false"));
    expect(sql, contains("'monthly_savings_sweep'"));
    expect(
      sql,
      contains('Current account x envelope positions must be reliable'),
    );
  });

  test('la clôture inclut le sweep avant de figer son audit', () {
    expect(sql, contains('v_sweep:=public.execute_monthly_savings_sweep'));
    expect(sql, contains("jsonb_build_object('savings_sweep',v_sweep)"));
    expect(
      sql,
      contains('if v_period.status=\'closed\' then return v_period.id'),
    );
  });
}
