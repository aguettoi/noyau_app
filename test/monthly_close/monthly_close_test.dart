import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/monthly_close/domain/monthly_close.dart';

void main() {
  test('health distinguishes hard blockers and overridable warnings', () {
    final snapshot = MonthlyCloseSnapshot(
      month: DateTime(2026, 10),
      status: MonthlyCloseStatus.open,
      issues: const [
        CloseIssue(
          code: 'r',
          label: 'Rapprochements',
          count: 1,
          severity: CloseIssueSeverity.blocker,
          destination: 'Comptes',
        ),
        CloseIssue(
          code: 'j',
          label: 'Justificatifs',
          count: 2,
          severity: CloseIssueSeverity.warning,
          destination: 'Historique',
        ),
        CloseIssue(
          code: 'c',
          label: 'Espèces',
          count: 0,
          severity: CloseIssueSeverity.blocker,
          destination: 'Comptes',
        ),
      ],
    );
    expect(snapshot.blockers, 1);
    expect(snapshot.warnings, 2);
    expect(snapshot.ready, isFalse);
    expect(snapshot.healthPercent, 33);
  });

  test('multi-account proposal nets transfers without financial write', () {
    final result = proposeSettlements([
      EnvelopeAccountTarget(
        memberId: 'a',
        accountId: 'account-a',
        envelopeId: 'food',
        current: Money.fromMinorUnits(15000),
        target: Money.fromMinorUnits(10000),
      ),
      EnvelopeAccountTarget(
        memberId: 'b',
        accountId: 'account-b',
        envelopeId: 'food',
        current: Money.fromMinorUnits(2000),
        target: Money.fromMinorUnits(7000),
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.fromAccountId, 'account-a');
    expect(result.single.toAccountId, 'account-b');
    expect(result.single.amount.minorUnits, 5000);
  });

  test('one, two and N members remain data-driven', () {
    for (final members in [1, 2, 4]) {
      final targets = List.generate(
        members,
        (i) => EnvelopeAccountTarget(
          memberId: 'm$i',
          accountId: 'a$i',
          envelopeId: 'e$i',
          current: const Money.fromMinorUnits(1000),
          target: const Money.fromMinorUnits(1000),
        ),
      );
      expect(proposeSettlements(targets), isEmpty);
    }
  });
}
