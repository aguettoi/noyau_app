import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/presentation/widgets/envelope_allocation_dialog.dart';

void main() {
  final envelopes = [
    RemoteEnvelopeBalance(
      id: 'a',
      name: 'Courses',
      inflows: Money.fromMinorUnits(0),
      outflows: Money.fromMinorUnits(0),
      balance: Money.fromMinorUnits(0),
      isSystem: false,
    ),
    RemoteEnvelopeBalance(
      id: 'b',
      name: 'Transport',
      inflows: Money.fromMinorUnits(0),
      outflows: Money.fromMinorUnits(0),
      balance: Money.fromMinorUnits(0),
      isSystem: false,
    ),
  ];
  testWidgets('multi-envelope requires exact cents and supports rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<EnvelopeAllocationResult>(
                context: context,
                builder: (_) => EnvelopeAllocationDialog(
                  amountCents: 10001,
                  envelopes: envelopes,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Reste à affecter : 100.01 MAD'), findsOneWidget);
    await tester.tap(find.text('Ajouter une enveloppe'));
    await tester.pumpAndSettle();
    expect(find.text('Enveloppe'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('abandon can explicitly keep envelopes unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<EnvelopeAllocationResult>(
                context: context,
                builder: (_) => EnvelopeAllocationDialog(
                  amountCents: 30000,
                  envelopes: envelopes,
                  allowNoImpact: true,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('no-envelope-impact')));
    await tester.pumpAndSettle();
    expect(find.text('Confirmer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
