import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noyau_app/core/theme/app_design_system.dart';
import 'package:noyau_app/features/experience/presentation/help_center_page.dart';
import 'package:noyau_app/features/experience/presentation/landing_page.dart';

void main() {
  test('design system enforces a 48 logical pixel touch target', () {
    expect(AppControlSize.minimumTouchTarget, greaterThanOrEqualTo(48));
    expect(AppControlSize.buttonHeight, greaterThanOrEqualTo(48));
    expect(AppControlSize.inputHeight, greaterThanOrEqualTo(48));
  });

  testWidgets('help is keyboard reachable and exposes labeled semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: HelpCenterPage()));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byKey(const Key('help-search')), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('help-search'))).label,
      contains('Rechercher dans l’aide'),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('landing remains usable with large text scaling', (tester) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(home: LandingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing-login')), findsOneWidget);
    expect(find.byKey(const Key('landing-signup')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
