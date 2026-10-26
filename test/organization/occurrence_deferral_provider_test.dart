import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/cashflow_projection/application/cashflow_projection_provider.dart';
import 'package:noyau_app/features/cashflow_projection/domain/cashflow_projection.dart';
import 'package:noyau_app/features/dashboard/application/providers/remote_financial_dashboard_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/member_compensations_provider.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/organization/application/organization_provider.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';

void main() {
  testWidgets('refresh, réouverture et expiration relisent la phase courante', (
    tester,
  ) async {
    final gateway = _Gateway();
    ProviderContainer open(String user) => ProviderContainer(
      overrides: [
        activeHouseholdProvider.overrideWith(
          (ref) async => const ActiveHouseholdState(
            status: ActiveHouseholdStatus.singleHousehold,
            householdId: 'h',
          ),
        ),
        currentUserIdProvider.overrideWithValue(user),
        householdTasksProvider.overrideWith((ref) async => []),
        financialDashboardProvider.overrideWith((ref) async => _Dashboard()),
        memberCompensationsProvider.overrideWith((ref) async => []),
        cashflowProjectionProvider.overrideWith((ref) async => _Projection()),
        notificationPreferencesProvider.overrideWith((ref) async => {}),
        organizationGatewayProvider.overrideWithValue(gateway),
        organizationClockProvider.overrideWithValue(DateTime(2026, 10, 26, 12)),
      ],
    );
    var a = open('a');
    expect(await a.read(organizationAlertsProvider.future), isEmpty);
    gateway.phase = 'after';
    a.invalidate(organizationAlertsProvider); // Same invalidation as Realtime.
    expect(await a.read(organizationAlertsProvider.future), isEmpty);
    a.dispose();
    a = open('a'); // Persisted state is fetched again after reopening.
    expect(await a.read(organizationAlertsProvider.future), isEmpty);
    final b = open('b');
    expect(
      (await b.read(organizationAlertsProvider.future)).single.key,
      'r3.1:o:after',
    );
    b.dispose();
    gateway.until = DateTime.now().subtract(const Duration(seconds: 1));
    // The provider timer re-fetches server state after the original deadline.
    await tester.pump(const Duration(seconds: 4));
    expect(
      (await a.read(organizationAlertsProvider.future)).single.key,
      'r3.1:o:after',
    );
    a.dispose();
  });
}

class _Gateway implements OrganizationGateway {
  DateTime until = DateTime.now().add(const Duration(seconds: 2));
  String phase = 'day';
  @override
  Future<Map<String, UserAlertState>> fetchAlertStates(
    String h,
    String u,
  ) async => u == 'a'
      ? {
          'reminder-source:r3_1_occurrence:o': UserAlertState(
            key: 'reminder-source:r3_1_occurrence:o',
            snoozedUntil: until,
            lastAction: 'snoozed',
          ),
        }
      : {};
  @override
  Future<List<AppAlert>> fetchReminders(String h, String u) async => [
    AppAlert(
      key: 'r3.1:o:$phase',
      title: phase,
      detail: '',
      category: 'reminders',
      source: CalendarSource.recurringFinance,
      sourceId: 'o',
      actionType: 'open_occurrence',
    ),
  ];
  @override
  Future<List<ReminderRule>> fetchReminderRules(String h) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Dashboard implements FinancialDashboardSnapshot {
  @override
  List<Never> get alerts => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Projection implements CashflowProjection {
  @override
  List<Never> get risks => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
