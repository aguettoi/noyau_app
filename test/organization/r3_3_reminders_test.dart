import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';

void main() {
  test('snooze et Pas encore masquent temporairement sans résoudre', () {
    final now = DateTime.utc(2026, 10, 18, 12);
    final state = UserAlertState(
      key: 'r3.1:occurrence:day',
      snoozedUntil: now.add(const Duration(hours: 4)),
      lastAction: 'not_yet',
    );
    expect(state.visibleAt(now), isFalse);
    expect(state.visibleAt(now.add(const Duration(hours: 5))), isTrue);
    expect(state.dismissedAt, isNull);
  });

  test('un rappel masqué ne redevient pas actif', () {
    final now = DateTime.utc(2026, 10, 18);
    expect(
      UserAlertState(
        key: 'risk',
        dismissedAt: now,
      ).visibleAt(now.add(const Duration(days: 2))),
      isFalse,
    );
  });

  test('une règle conserve priorité, destinataire et paramètres', () {
    const rule = ReminderRule(
      type: 'expected_occurrence',
      enabled: true,
      priority: HouseholdTaskPriority.high,
      parameters: {'before_days': 2, 'after_days': 1, 'hour': 20},
      recipientUserId: 'member-a',
    );
    expect(rule.parameters['before_days'], 2);
    expect(rule.recipientUserId, 'member-a');
  });
}
