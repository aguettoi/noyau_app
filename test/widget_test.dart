import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/noyau_app.dart';

void main() {
  testWidgets('affiche uniquement la fondation sans donnee fictive', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: NoyauApp()));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Fondation financiere'), findsOneWidget);
    expect(
      find.text('Aucune donnee du foyer n est encore importee.'),
      findsOneWidget,
    );
    expect(find.text('Nourriture'), findsNothing);
  });
}
