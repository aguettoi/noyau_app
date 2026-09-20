import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/finance/presentation/import_preview_page.dart';

void main() {
  testWidgets('l assistant se quitte sans créer ni confirmer un import', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserIdProvider.overrideWithValue(null)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ImportPreviewPage(),
                    ),
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('exit-import-assistant-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('exit-import-assistant-button')));
    await tester.pumpAndSettle();

    expect(find.text('Ouvrir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
