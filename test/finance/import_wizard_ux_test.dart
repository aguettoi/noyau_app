import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/finance/presentation/import_preview_page.dart';
import 'package:noyau_app/features/finance/presentation/import_wizard_components.dart';

void main() {
  for (final size in const [
    Size(390, 760),
    Size(430, 860),
    Size(800, 900),
    Size(1280, 900),
    Size(1920, 1080),
  ]) {
    testWidgets('assistant Import responsive sans overflow à ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentUserIdProvider.overrideWithValue(null)],
          child: const MaterialApp(home: Scaffold(body: ImportPreviewPage())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Importer mes données'), findsOneWidget);
      expect(find.byKey(const Key('import-wizard-stepper')), findsOneWidget);
      expect(find.text('Fichier Excel'), findsOneWidget);
      expect(find.text('Google Sheets'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('le stepper desktop expose les cinq étapes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ImportWizardStepper(currentStep: 3)),
      ),
    );

    for (final label in ImportWizardStepper.labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('les badges technique et opérationnel restent explicites', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ImportDecisionBadge(
                label: 'ENVIRONNEMENT TECHNIQUE',
                tone: ImportDecisionTone.technical,
              ),
              ImportDecisionBadge(
                label: 'ENVIRONNEMENT OPÉRATIONNEL',
                tone: ImportDecisionTone.operational,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('ENVIRONNEMENT TECHNIQUE'), findsOneWidget);
    expect(find.text('ENVIRONNEMENT OPÉRATIONNEL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('les décisions créer match et conflit sont distinctes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ImportDecisionBadge(
                label: 'CRÉER',
                tone: ImportDecisionTone.create,
              ),
              ImportDecisionBadge(
                label: 'MATCH',
                tone: ImportDecisionTone.match,
              ),
              ImportDecisionBadge(
                label: 'CONFLIT',
                tone: ImportDecisionTone.conflict,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('CRÉER'), findsOneWidget);
    expect(find.text('MATCH'), findsOneWidget);
    expect(find.text('CONFLIT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('après succès le bouton d exécution disparaît', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CutoverExecutionPanel(
            confirmed: true,
            executing: false,
            onExecute: () {},
            result: _result(status: 'RECONCILED'),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('cutover-reconciliation-panel')),
      findsOneWidget,
    );
    expect(find.textContaining('écart zéro'), findsOneWidget);
    expect(find.byKey(const Key('cutover-execute-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un résultat non réconcilié est clairement signalé', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CutoverExecutionPanel(
            confirmed: true,
            executing: false,
            onExecute: () {},
            result: _result(status: 'NOT_RECONCILED', difference: 12),
          ),
        ),
      ),
    );

    expect(find.textContaining('écarts à vérifier'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.byKey(const Key('cutover-execute-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _result({required String status, num difference = 0}) => {
  'status': status,
  'financial_events': 3,
  'gl_transactions': 2,
  'envelope_movements': 3,
  'accounts': [
    {
      'name': 'Banque A',
      'expected': 1000,
      'actual': 1000 - difference,
      'difference': difference,
    },
  ],
  'envelopes': [
    {'name': 'Nourriture', 'expected': 500, 'actual': 500, 'difference': 0},
  ],
};
