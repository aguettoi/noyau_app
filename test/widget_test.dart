import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/noyau_app.dart';
import 'package:noyau_app/features/finance/application/finance_workspace.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';

void main() {
  testWidgets('affiche uniquement la fondation sans donnee fictive', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseUserIdProvider.overrideWith(
            (ref) => Stream.value('test-user'),
          ),
          financeWorkspaceProvider.overrideWith(_TestWorkspaceController.new),
        ],
        child: const NoyauApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fondation financiere'), findsOneWidget);
    expect(
      find.text('Aucune donnee du foyer n est encore importee.'),
      findsOneWidget,
    );
    expect(find.text('Nourriture'), findsNothing);
  });
}

class _TestWorkspaceController extends FinanceWorkspaceController {
  @override
  Future<FinanceWorkspace> build() async => FinanceWorkspace.empty(const []);
}
