import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/theme/app_design_system.dart';
import 'package:noyau_app/core/theme/noyau_theme.dart';

void main() {
  test('breakpoints are width-driven and platform-independent', () {
    expect(AppLayout.windowClass(390), AppWindowClass.compact);
    expect(AppLayout.windowClass(700), AppWindowClass.medium);
    expect(AppLayout.windowClass(1200), AppWindowClass.expanded);
    expect(AppLayout.windowClass(1600), AppWindowClass.large);
  });

  testWidgets('shared KPI remains readable on compact and expanded widths', (
    tester,
  ) async {
    for (final size in const [Size(320, 640), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: NoyauTheme.light,
          home: const Scaffold(
            body: FpKpiCard(
              title: 'Valeur nette',
              value: '1 234 567,89 MAD',
              detail: 'Actifs moins passifs',
              icon: Icons.account_balance_wallet_outlined,
            ),
          ),
        ),
      );
      expect(find.text('Valeur nette'), findsOneWidget);
      expect(find.text('1 234 567,89 MAD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('common loading empty and error states are accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NoyauTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              FpLoadingState(label: 'Chargement du foyer…'),
              FpEmptyState(
                title: 'Aucune donnée',
                message: 'Ajoutez un élément.',
              ),
              FpErrorState(message: 'Réessayez plus tard.'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Chargement du foyer…'), findsOneWidget);
    expect(find.text('Aucune donnée'), findsOneWidget);
    expect(find.text('Réessayez plus tard.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page header stacks actions on compact widths', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: NoyauTheme.light,
        home: Scaffold(
          body: FpPageHeader(
            title: 'Comptes',
            subtitle: 'Positions réelles',
            actions: [
              FilledButton(onPressed: () {}, child: const Text('Ajouter')),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Comptes'), findsOneWidget);
    expect(find.text('Ajouter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
